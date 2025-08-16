#!/usr/bin/env bash

# /*
# Copyright 2025 UTA-LugNuts Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */

#
# @file LnOS-installer.sh
# @brief Interactive installer for LnOS (Arch-based) on x86_64 (UEFI/BIOS)
# @authors Betim-Hodza, Ric3y, rcghpge
# @date 2025
#

set -Eeuo pipefail

### -------------------------------------------------------------
### Helpers & UX
### -------------------------------------------------------------
if ! command -v gum >/dev/null 2>&1; then
  pacman -Sy --noconfirm gum || true
fi

# shellcheck disable=SC2312
_gum() {
  if command -v gum >/dev/null 2>&1; then gum "$@"; else shift; echo "$*"; fi
}

echo_b()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 33  "$*"; }
echo_ok() { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 82  "$*"; }
echo_w()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 208 "$*"; }
echo_e()  { _gum style --border double --margin "1 2" --padding "1 3" --border-foreground 196 "$*"; }

trap 'echo_e "Installation failed on line $LINENO (command: ${BASH_COMMAND:-?})."' ERR

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo_e "Please run as root (use sudo)."; exit 1
  fi
}

### -------------------------------------------------------------
### Environment checks
### -------------------------------------------------------------
require_root

# Speed up pacman a bit on the live environment
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || true

# Keyring sanity (usually prepped on ArchISO already)
pacman -Sy --noconfirm archlinux-keyring || true

ensure_net() {
  echo_b "Connect to the internet (the installer needs it)."
  if ! _gum confirm "Open nmtui now?"; then
    echo_e "Network is required. Aborting."; exit 1
  fi
  nmtui || true
  if ! ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
    echo_w "No ping yet. We'll try pacman later; continue for now."
  fi
}

### -------------------------------------------------------------
### Disk partitioning & filesystems
### -------------------------------------------------------------
DISK=""; UEFI=0; NVME=0; ESP_PART=; BOOT_PART=; SWAP_PART=; ROOT_PART=

select_disk() {
  local rows
  rows=$(lsblk -d -o NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print}')
  [[ -z "$rows" ]] && { echo_e "No disks found."; exit 1; }
  local choice
  choice=$(echo "$rows" | _gum choose --header "Select target disk (ERASES ALL DATA):")
  [[ -z "$choice" ]] && { echo_e "No disk selected."; exit 1; }
  DISK="/dev/$(awk '{print $1}' <<<"$choice")"
  [[ "$DISK" == *nvme* ]] && NVME=1 || NVME=0
  [[ -d /sys/firmware/efi ]] && UEFI=1 || UEFI=0
  echo_w "Target: $DISK | Firmware: $([[ $UEFI -eq 1 ]] && echo UEFI || echo BIOS)"
  _gum confirm "Proceed to WIPE and partition $DISK?" || { echo_w "Aborted by user."; exit 1; }
}

mkparts_and_format() {
  # Sizes (MiB)
  local ESP_START=1 ESP_END=513       # 512MiB ESP for UEFI
  local BOOT_SIZE=1025                # 1GiB /boot (ext4)

  # Swap policy: 4GiB if < 15GiB RAM
  local ram_gb; ram_gb=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
  local SWAP_SIZE=0
  if (( ram_gb < 15 )); then SWAP_SIZE=4096; echo_b "RAM ${ram_gb}G -> creating 4GiB swap"; fi

  echo_w "Wiping existing signatures on $DISK"
  wipefs -a "$DISK" || true

  if (( UEFI == 1 )); then
    # UEFI layout: 512MiB ESP + 1GiB /boot (ext4) + optional swap + btrfs root
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 ${ESP_START}MiB ${ESP_END}MiB
    parted -s "$DISK" set 1 esp on
    # /boot immediately after ESP
    parted -s "$DISK" mkpart boot ext4 ${ESP_END}MiB $((ESP_END + BOOT_SIZE))MiB
    if (( SWAP_SIZE > 0 )); then
      parted -s "$DISK" mkpart swap linux-swap $((ESP_END + BOOT_SIZE))MiB $((ESP_END + BOOT_SIZE + SWAP_SIZE))MiB
      parted -s "$DISK" mkpart root btrfs $((ESP_END + BOOT_SIZE + SWAP_SIZE))MiB 100%
      ESP_PART=1; BOOT_PART=2; SWAP_PART=3; ROOT_PART=4
    else
      parted -s "$DISK" mkpart root btrfs $((ESP_END + BOOT_SIZE))MiB 100%
      ESP_PART=1; BOOT_PART=2; ROOT_PART=3
    fi
  else
    # BIOS layout: 1GiB /boot (ext4, boot flag) + optional swap + btrfs root
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary ext4 1MiB $((1 + BOOT_SIZE))MiB
    parted -s "$DISK" set 1 boot on
    if (( SWAP_SIZE > 0 )); then
      parted -s "$DISK" mkpart primary linux-swap $((1 + BOOT_SIZE))MiB $((1 + BOOT_SIZE + SWAP_SIZE))MiB
      parted -s "$DISK" mkpart primary btrfs $((1 + BOOT_SIZE + SWAP_SIZE))MiB 100%
      BOOT_PART=1; SWAP_PART=2; ROOT_PART=3
    else
      parted -s "$DISK" mkpart primary btrfs $((1 + BOOT_SIZE))MiB 100%
      BOOT_PART=1; ROOT_PART=2
    fi
  fi

  # Format partitions
  if (( UEFI == 1 )); then
    if (( NVME == 1 )); then
      mkfs.fat -F32 "${DISK}p${ESP_PART}"
      mkfs.ext4 -F   "${DISK}p${BOOT_PART}"
    else
      mkfs.fat -F32 "${DISK}${ESP_PART}"
      mkfs.ext4 -F   "${DISK}${BOOT_PART}"
    fi
  else
    if (( NVME == 1 )); then
      mkfs.ext4 -F   "${DISK}p${BOOT_PART}"
    else
      mkfs.ext4 -F   "${DISK}${BOOT_PART}"
    fi
  fi

  if [[ -n "${SWAP_PART:-}" ]]; then
    if (( NVME == 1 )); then mkswap "${DISK}p${SWAP_PART}"; else mkswap "${DISK}${SWAP_PART}"; fi
    swapon "$([[ $NVME -eq 1 ]] && echo "${DISK}p${SWAP_PART}" || echo "${DISK}${SWAP_PART}")" || true
  fi

  if (( NVME == 1 )); then mkfs.btrfs -f "${DISK}p${ROOT_PART}"; else mkfs.btrfs -f "${DISK}${ROOT_PART}"; fi

  # Mount root
  local ROOTDEV
  ROOTDEV=$([[ $NVME -eq 1 ]] && echo "${DISK}p${ROOT_PART}" || echo "${DISK}${ROOT_PART}")
  mount "$ROOTDEV" /mnt

  # Mount /boot and ESP
  if (( UEFI == 1 )); then
    mkdir -p /mnt/boot /mnt/boot/efi
    if (( NVME == 1 )); then
      mount "${DISK}p${BOOT_PART}" /mnt/boot
      mount "${DISK}p${ESP_PART}"  /mnt/boot/efi
    else
      mount "${DISK}${BOOT_PART}" /mnt/boot
      mount "${DISK}${ESP_PART}"  /mnt/boot/efi
    fi
  else
    mkdir -p /mnt/boot
    if (( NVME == 1 )); then mount "${DISK}p${BOOT_PART}" /mnt/boot; else mount "${DISK}${BOOT_PART}" /mnt/boot; fi
  fi
}

### -------------------------------------------------------------
### Copy LnOS repo to target (for post-install use)
### -------------------------------------------------------------
LNOS_REPO="/root/LnOS"           # expected on our ISO
copy_lnos_files() {
  if [[ -d "$LNOS_REPO" ]]; then
    mkdir -p /mnt/root/LnOS
    # copy curated bits used post-install
    cp -r "$LNOS_REPO/scripts/pacman_packages" /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$LNOS_REPO/scripts/paru_packages"   /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$LNOS_REPO/docs"                    /mnt/root/LnOS/ 2>/dev/null || true
    for f in README.md LICENSE AUTHORS SUMMARY.md TODO.md; do
      [[ -f "$LNOS_REPO/$f" ]] && cp "$LNOS_REPO/$f" /mnt/root/LnOS/ || true
    done
    echo_ok "Copied LnOS payload to /mnt/root/LnOS"
  else
    echo_w "LnOS repo not found at $LNOS_REPO (live ISO recommended). Skipping copy."
  fi
}

### -------------------------------------------------------------
### Chroot-side configuration script (written then executed)
### -------------------------------------------------------------
write_chroot_script() {
  cat > /mnt/root/.lnos-post.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail

# Ensure gum in chroot
pacman -Sy --noconfirm gum >/dev/null 2>&1 || true

_gum() { if command -v gum >/dev/null 2>&1; then gum "$@"; else shift; echo "$*"; fi }

echo_b()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 33  "$*"; }
echo_ok() { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 82  "$*"; }
echo_w()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 208 "$*"; }
echo_e()  { _gum style --border double --margin "1 2" --padding "1 3" --border-foreground 196 "$*"; }

# --- Base system config ---
ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
hwclock --systohc || true

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "LnOS" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 LnOS
EOF

# Keep networking simple: NetworkManager only
systemctl enable NetworkManager.service || true

# Sudo setup for wheel
pacman -S --noconfirm sudo >/dev/null 2>&1 || true
install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO

# Root password
while true; do
  r1=$(_gum input --password --placeholder="Enter root password:")
  r2=$(_gum input --password --placeholder="Confirm root password:")
  [[ "$r1" == "$r2" && -n "$r1" ]] && { echo "root:$r1" | chpasswd; break; }
  _gum confirm "Passwords do not match. Try again?" || exit 1
done

# User account
uname=""
while [[ -z "${uname}" ]]; do
  uname=$(_gum input --placeholder "Enter username:")
  [[ -z "$uname" ]] && echo_e "Username cannot be empty."
done
useradd -m -G wheel,audio,video,input,sys,lp,adm,log,rfkill -s /bin/bash "$uname"
while true; do
  p1=$(_gum input --password --placeholder="Enter password for $uname:")
  p2=$(_gum input --password --placeholder="Confirm password for $uname:")
  [[ "$p1" == "$p2" && -n "$p1" ]] && { echo "$uname:$p1" | chpasswd; break; }
  _gum confirm "Passwords do not match. Try again?" || exit 1
DONE

# Keep system current
pacman -Syu --noconfirm || true

# --- Safe os-release override (keeps ID=arch) ---
if [ -L /etc/os-release ]; then rm -f /etc/os-release; fi
cat > /etc/os-release <<'OSR'
NAME="LnOS"
PRETTY_NAME="LnOS (Arch Linux)"
ID=arch
ID_LIKE=arch
VARIANT="LnOS"
VARIANT_ID=lnos
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/uta-lug-nuts/LnOS"
DOCUMENTATION_URL="https://github.com/uta-lug-nuts/LnOS"
SUPPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
BUG_REPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
OSR

# --- Desktop & packages ---
choose_de() {
  local de
  de=$(_gum choose --header "Choose Desktop Environment" \
    "GNOME (friendly, Mac-like)" \
    "KDE Plasma (friendly, Windows-like)" \
    "Hyprland (tiling, DIY)" \
    "TTY only (no GUI)")
  printf '%s' "$de"
}

install_de() {
  local choice="$1"
  case "$choice" in
    "GNOME*" )
      pacman -S --noconfirm xorg-server gnome gdm
      systemctl enable gdm.service
      ;;
    "KDE Plasma*" )
      pacman -S --noconfirm xorg-server plasma kde-applications sddm
      systemctl enable sddm.service
      ;;
    "Hyprland*" )
      pacman -S --noconfirm wayland hyprland noto-fonts noto-fonts-emoji kitty
      ;;
    "TTY only*" ) ;;
  esac
}

# Prompt & install DE
DESEL=$(choose_de)
_gum confirm "Install: $DESEL ?" && install_de "$DESEL"

# Package profiles
profile=$(_gum choose --header "Choose installation profile" CSE Custom)
if [[ "$profile" == "CSE" ]]; then
  # Read curated package lists if present
  if [[ -f /root/LnOS/pacman_packages/CSE_packages.txt ]]; then
    pac_pkgs=$(tr '
' ' ' < /root/LnOS/pacman_packages/CSE_packages.txt)
    _gum spin --spinner dot --title "Installing pacman packages (CSE)" -- \
      bash -lc "pacman -S --noconfirm $pac_pkgs"
  fi
  if [[ -f /root/LnOS/paru_packages/paru_packages.txt ]]; then
    # Build paru
    pacman -S --noconfirm base-devel git
    tmpd=$(mktemp -d); pushd "$tmpd" >/dev/null
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
    popd >/dev/null; rm -rf "$tmpd"
    aur_pkgs=$(tr '
' ' ' < /root/LnOS/paru_packages/paru_packages.txt)
    _gum style --foreground 255 --border-foreground 130 --border double --width 100 --margin "1 2" --padding "1 2" \
      'AUR is community-maintained. LnOS uses signed releases where possible.'
    _gum confirm "Proceed with AUR packages?" && paru -S --noconfirm $aur_pkgs || true
  fi
else
  read -r -p "Enter pacman packages (space-separated): " pac_pkgs || true
  [[ -n "${pac_pkgs:-}" ]] && pacman -S --noconfirm $pac_pkgs || true
  _gum style --foreground 255 --border-foreground 130 --border double --width 100 --margin "1 2" --padding "1 2" \
    'AUR is community-maintained. Continue only if you trust the packages.'
  if _gum confirm "Install AUR packages (requires building)?"; then
    pacman -S --noconfirm base-devel git
    tmpd=$(mktemp -d); pushd "$tmpd" >/dev/null
    git clone https://aur.archlinux.org/paru.git
    cd paru && makepkg -si --noconfirm
    popd >/dev/null; rm -rf "$tmpd"
    read -r -p "Enter paru packages (space-separated): " aur_pkgs || true
    [[ -n "${aur_pkgs:-}" ]] && paru -S --noconfirm $aur_pkgs || true
  fi
fi

echo_ok "Chroot configuration complete."
CHROOT
  chmod +x /mnt/root/.lnos-post.sh
}

run_chroot_script() {
  arch-chroot /mnt /root/.lnos-post.sh
}

### -------------------------------------------------------------
### Bootloader (GRUB) install
### -------------------------------------------------------------
install_bootloader() {
  if (( UEFI == 1 )); then
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  else
    arch-chroot /mnt pacman -S --noconfirm grub
    arch-chroot /mnt grub-install --target=i386-pc "$DISK"
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

### -------------------------------------------------------------
### Main flow (x86_64)
### -------------------------------------------------------------
install_x86_64() {
  ensure_net
  select_disk
  mkparts_and_format

  echo_b "Installing base system (this may take a while)"
  # Default to hardened kernel for student systems; include microcode
  local base_pkgs=(base linux-hardened linux-firmware intel-ucode amd-ucode btrfs-progs networkmanager xdg-user-dirs vim git wget curl gum)
  _gum spin --spinner dot --title "pacstrap base + core packages" -- \
    pacstrap /mnt "${base_pkgs[@]}"

  # Console font config from live (optional)
  [[ -f /etc/vconsole.conf ]] && install -Dm644 /etc/vconsole.conf /mnt/etc/vconsole.conf

  # fstab (captures /boot and /boot/efi mounts)
  genfstab -U /mnt >> /mnt/etc/fstab

  # Copy LnOS payload (pkg lists, docs)
  copy_lnos_files

  # Post-install inside chroot
  write_chroot_script
  run_chroot_script

  # Bootloader
  install_bootloader

  # Done
  umount -R /mnt || true
  for i in {10..1}; do echo_ok "Installation complete. Rebooting in $i..."; sleep 1; done
  reboot
}

### -------------------------------------------------------------
### CLI
### -------------------------------------------------------------
usage() {
  cat <<USG
Usage: $0 --target=x86_64 | -h

Options:
  --target=x86_64   Install LnOS on an x86_64 system (UEFI or BIOS)
  -h, --help        Show this help

Notes:
 • Do NOT run this from within the installed system. Use it from a live ISO.
 • The installer wipes the selected disk entirely.
USG
}

main() {
  case "${1:-}" in
    --target=x86_64) install_x86_64 ;;
    -h|--help|*)     usage ;;
  esac
}

main "$@"
