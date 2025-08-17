#!/usr/bin/env bash
# /*
# Copyright 2025 UTA-LugNuts Authors.
# Licensed under the Apache License, Version 2.0
# */

# @file LnOS-installer.sh
# @brief Interactive installer for LnOS (Arch-based) on x86_64 (UEFI/BIOS)
# @authors
#   Original: Betim-Hodza, Ric3y, rcghpge
#   This revision: keeps interfaces, adds btrfs subvols, BIOS-GPT, mkinitcpio hardening
# @date 2025

set -Eeuo pipefail

FLAVOR="${FLAVOR:-sandbox}"         # recorded into /etc/os-release
TZ="${TZ:-America/Chicago}"
KERNEL_CHOICE="${KERNEL_CHOICE:-hardened}"  # hardened|vanilla

# ---- UX helpers (gum optional) ----
if ! command -v gum >/dev/null 2>&1; then
  pacman -Sy --noconfirm gum >/dev/null 2>&1 || true
fi
_gum() { if command -v gum >/dev/null 2>&1; then gum "$@"; else shift; echo "$*"; fi; }
echo_b()  { _gum style --border normal  --margin "1 2" --padding "1 3" --border-foreground 33  "$*"; }
echo_ok() { _gum style --border normal  --margin "1 2" --padding "1 3" --border-foreground 82  "$*"; }
echo_w()  { _gum style --border normal  --margin "1 2" --padding "1 3" --border-foreground 208 "$*"; }
echo_e()  { _gum style --border double  --margin "1 2" --padding "1 3" --border-foreground 196 "$*"; }
trap 'echo_e "Installation failed on line $LINENO (command: ${BASH_COMMAND:-?})."' ERR

require_root() { if [[ $EUID -ne 0 ]]; then echo_e "Please run as root (use sudo)."; exit 1; fi; }

# ---- Prep ----
require_root
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || true
pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1 || true

ensure_net() {
  echo_b "Connect to the internet (installer needs it)."
  if command -v nmtui >/dev/null 2>&1; then
    if _gum confirm "Open nmtui now?"; then nmtui || true; fi
  fi
  if ! ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
    echo_w "No ping yet. We’ll proceed; pacstrap will fail if offline."
  fi
}

# ---- Disk selection & partitioning ----
DISK=""; UEFI=0; NVME=0; GPT=0
ESP_PART=; BIOS_GRUB_PART=; BOOT_PART=; SWAP_PART=; ROOT_PART=

select_kernel() {
  local sel
  sel="$(_gum choose --header 'Choose kernel' 'linux-hardened (default)' 'linux (vanilla)')"
  case "$sel" in
    linux\ \(vanilla\)) KERNEL_CHOICE="vanilla" ;;
    *)                  KERNEL_CHOICE="hardened" ;;
  esac
  echo_ok "Kernel: $KERNEL_CHOICE"
}

select_disk() {
  local rows choice
  rows=$(lsblk -d -o NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print}')
  [[ -z "$rows" ]] && { echo_e "No disks found."; exit 1; }
  echo_b "Available disks:"; lsblk -o NAME,SIZE,MODEL,TYPE
  choice=$(echo "$rows" | _gum choose --header "Select target disk (ERASES ALL DATA):")
  [[ -z "$choice" ]] && { echo_e "No disk selected."; exit 1; }
  DISK="/dev/$(awk '{print $1}' <<<"$choice")"
  [[ "$DISK" == *nvme* ]] && NVME=1 || NVME=0
  [[ -d /sys/firmware/efi ]] && UEFI=1 || UEFI=0
  echo_w "Target: $DISK | Firmware: $([[ $UEFI -eq 1 ]] && echo UEFI || echo BIOS)"
  _gum confirm "FINAL CONFIRM: WIPE and partition $DISK?" || { echo_w "Aborted."; exit 1; }
}

mkparts_and_format() {
  # Sizes (MiB)
  local ESP_START=1 ESP_END=513     # 512MiB ESP
  local BOOT_SIZE=1025              # 1GiB /boot ext4

  # Swap policy: 4GiB if < 15GiB RAM
  local ram_gb; ram_gb=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
  local SWAP_SIZE=0
  if (( ram_gb < 15 )); then SWAP_SIZE=4096; echo_b "RAM ${ram_gb}G -> creating 4GiB swap"; fi

  echo_w "Wiping signatures on $DISK"
  wipefs -a "$DISK" || true

  if (( UEFI == 1 )); then
    parted -s "$DISK" mklabel gpt
    GPT=1
    parted -s "$DISK" mkpart ESP fat32 ${ESP_START}MiB ${ESP_END}MiB
    parted -s "$DISK" set 1 esp on
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
    # BIOS: prefer GPT + bios_grub to avoid legacy disk weirdness
    parted -s "$DISK" mklabel gpt
    GPT=1
    parted -s "$DISK" mkpart bios_grub 1MiB 2MiB
    parted -s "$DISK" set 1 bios_grub on
    parted -s "$DISK" mkpart boot ext4 2MiB $((2 + BOOT_SIZE))MiB
    if (( SWAP_SIZE > 0 )); then
      parted -s "$DISK" mkpart swap linux-swap $((2 + BOOT_SIZE))MiB $((2 + BOOT_SIZE + SWAP_SIZE))MiB
      parted -s "$DISK" mkpart root btrfs $((2 + BOOT_SIZE + SWAP_SIZE))MiB 100%
      BIOS_GRUB_PART=1; BOOT_PART=2; SWAP_PART=3; ROOT_PART=4
    else
      parted -s "$DISK" mkpart root btrfs $((2 + BOOT_SIZE))MiB 100%
      BIOS_GRUB_PART=1; BOOT_PART=2; ROOT_PART=3
    fi
  fi

  # Format ESP/BOOT
  if (( UEFI == 1 )); then
    if (( NVME == 1 )); then
      mkfs.fat -F32 "${DISK}p${ESP_PART}"
      mkfs.ext4 -F   "${DISK}p${BOOT_PART}"
    else
      mkfs.fat -F32 "${DISK}${ESP_PART}"
      mkfs.ext4 -F   "${DISK}${BOOT_PART}"
    fi
  else
    if (( NVME == 1 )); then mkfs.ext4 -F "${DISK}p${BOOT_PART}"; else mkfs.ext4 -F "${DISK}${BOOT_PART}"; fi
  fi

  # Swap
  if [[ -n "${SWAP_PART:-}" ]]; then
    if (( NVME == 1 )); then mkswap "${DISK}p${SWAP_PART}"; swapon "${DISK}p${SWAP_PART}" || true
    else mkswap "${DISK}${SWAP_PART}"; swapon "${DISK}${SWAP_PART}" || true
    fi
  fi

  # Btrfs root
  if (( NVME == 1 )); then mkfs.btrfs -f "${DISK}p${ROOT_PART}"; else mkfs.btrfs -f "${DISK}${ROOT_PART}"; fi

  # Create subvolumes
  local ROOTDEV
  ROOTDEV=$([[ $NVME -eq 1 ]] && echo "${DISK}p${ROOT_PART}" || echo "${DISK}${ROOT_PART}")
  mount "$ROOTDEV" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@log
  btrfs subvolume create /mnt/@pkg
  umount /mnt

  # Mount with options
  local opts="noatime,compress=zstd:3"
  # Add ssd option if drive appears as non-rotational
  if [[ -r /sys/block/$(basename "$DISK")/queue/rotational ]] && [[ "$(cat /sys/block/$(basename "$DISK")/queue/rotational)" -eq 0 ]]; then
    opts="$opts,ssd"
  fi
  mount -o subvol=@,$opts "$ROOTDEV" /mnt
  mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot}
  mount -o subvol=@home,$opts "$ROOTDEV" /mnt/home
  mount -o subvol=@log,$opts  "$ROOTDEV" /mnt/var/log
  mount -o subvol=@pkg,$opts  "$ROOTDEV" /mnt/var/cache/pacman/pkg

  # ESP/BOOT mounts
  if (( UEFI == 1 )); then
    mkdir -p /mnt/boot/efi
    if (( NVME == 1 )); then
      mount "${DISK}p${BOOT_PART}" /mnt/boot
      mount "${DISK}p${ESP_PART}"  /mnt/boot/efi
    else
      mount "${DISK}${BOOT_PART}" /mnt/boot
      mount "${DISK}${ESP_PART}"  /mnt/boot/efi
    fi
  else
    if (( NVME == 1 )); then mount "${DISK}p${BOOT_PART}" /mnt/boot; else mount "${DISK}${BOOT_PART}" /mnt/boot; fi
  fi
}

# ---- Copy LnOS payload (optional) ----
LNOS_REPO="/root/LnOS"
copy_lnos_files() {
  if [[ -d "$LNOS_REPO" ]]; then
    mkdir -p /mnt/root/LnOS
    cp -r "$LNOS_REPO/scripts/pacman_packages" /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$LNOS_REPO/scripts/paru_packages"   /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$LNOS_REPO/docs"                    /mnt/root/LnOS/ 2>/dev/null || true
    for f in README.md LICENSE AUTHORS SUMMARY.md TODO.md; do
      [[ -f "$LNOS_REPO/$f" ]] && cp "$LNOS_REPO/$f" /mnt/root/LnOS/ || true
    done
    echo_ok "Copied LnOS payload to /mnt/root/LnOS"
  else
    echo_w "LnOS repo not found at $LNOS_REPO (live ISO recommended). Skipping payload copy."
  fi
}

# ---- Chroot script ----
write_chroot_script() {
  cat > /mnt/root/.lnos-post.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v gum >/dev/null 2>&1; then pacman -Sy --noconfirm gum >/dev/null 2>&1 || true; fi
_gum() { if command -v gum >/dev/null 2>&1; then gum "$@"; else shift; echo "$*"; fi; }
echo_b()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 33  "$*"; }
echo_ok() { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 82  "$*"; }
echo_w()  { _gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 208 "$*"; }
echo_e()  { _gum style --border double --margin "1 2" --padding "1 3" --border-foreground 196 "$*"; }

# Base locale/time/host
ln -sf /usr/share/zoneinfo/__TZ__ /etc/localtime
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

# NetworkManager
pacman -S --noconfirm networkmanager >/dev/null 2>&1 || true
systemctl enable NetworkManager.service 2>/dev/null || true

# Sudo for wheel
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

# User
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
done

# Keep system current
pacman -Syu --noconfirm || true

# os-release (keep ID=arch)
if [ -L /etc/os-release ]; then rm -f /etc/os-release; fi
cat > /etc/os-release <<'OSR'
NAME="LnOS"
PRETTY_NAME="LnOS (Arch Linux) - __FLAVOR__"
ID=arch
ID_LIKE=arch
VARIANT="LnOS"
VARIANT_ID=lnos
BUILD_ID=rolling
BUILD_FLAVOR="__FLAVOR__"
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/uta-lug-nuts/LnOS"
DOCUMENTATION_URL="https://github.com/uta-lug-nuts/LnOS"
SUPPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
BUG_REPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
OSR

# Kernel selector (injected)
case "__KERNEL__" in
  hardened) pacman -S --noconfirm linux-hardened linux-firmware ;;
  *)        pacman -S --noconfirm linux linux-firmware ;;
esac

# Microcode (safe to install both; only one will be used)
pacman -S --noconfirm intel-ucode amd-ucode

# mkinitcpio: ensure btrfs is available
if grep -q '^HOOKS=' /etc/mkinitcpio.conf; then
  sed -i 's/^\(HOOKS=.*\)filesystems\(.*\)$/\1btrfs filesystems\2/' /etc/mkinitcpio.conf || true
fi
mkinitcpio -P || true

# Desktop Environment
choose_de() {
  _gum choose --header "Choose Desktop Environment" \
    "GNOME (friendly, Mac-like)" \
    "KDE Plasma (friendly, Windows-like)" \
    "Hyprland (tiling, DIY)" \
    "TTY only (no GUI)"
}
install_de() {
  case "$1" in
    GNOME*)      pacman -S --noconfirm xorg-server gnome gdm && systemctl enable gdm.service ;;
    KDE\ Plasma*)pacman -S --noconfirm xorg-server plasma kde-applications sddm && systemctl enable sddm.service ;;
    Hyprland*)   pacman -S --noconfirm wayland xorg-xwayland hyprland noto-fonts noto-fonts-emoji kitty ;;
    TTY\ only*)  : ;;
  esac
}
DESEL="$(choose_de || echo 'TTY only (no GUI)')"
_gum confirm "Install: $DESEL ?" && install_de "$DESEL"

# Package profiles
profile=$(_gum choose --header "Choose installation profile" CSE Custom)
if [[ "$profile" == "CSE" ]]; then
  if [[ -f /root/LnOS/pacman_packages/CSE_packages.txt ]]; then
    pac_pkgs=$(tr '\n' ' ' < /root/LnOS/pacman_packages/CSE_packages.txt)
    _gum spin --spinner dot --title "Installing pacman packages (CSE)" -- bash -lc "pacman -S --noconfirm $pac_pkgs"
  fi
  if [[ -f /root/LnOS/paru_packages/paru_packages.txt ]]; then
    pacman -S --noconfirm base-devel git
    tmpd=$(mktemp -d); pushd "$tmpd" >/dev/null
    git clone https://aur.archlinux.org/paru.git
    cd paru && makepkg -si --noconfirm
    popd >/dev/null; rm -rf "$tmpd"
    aur_pkgs=$(tr '\n' ' ' < /root/LnOS/paru_packages/paru_packages.txt)
    _gum style --foreground 255 --border-foreground 130 --border double --width 100 --margin "1 2" --padding "1 2" \
      'AUR is community-maintained. LnOS prefers signed releases.'
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

  sed -i "s#__TZ__#${TZ}#g" /mnt/root/.lnos-post.sh
  sed -i "s#__FLAVOR__#${FLAVOR}#g" /mnt/root/.lnos-post.sh
  sed -i "s#__KERNEL__#${KERNEL_CHOICE}#g" /mnt/root/.lnos-post.sh
  chmod +x /mnt/root/.lnos-post.sh
}

run_chroot_script() { arch-chroot /mnt /root/.lnos-post.sh; }

# ---- Bootloader ----
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

# ---- Main flow ----
install_x86_64() {
  ensure_net
  select_kernel
  select_disk
  mkparts_and_format

  echo_b "Installing base system"
  # Base + minimum to chroot; kernel added in chroot to honor selection
  local base_pkgs=(base btrfs-progs xdg-user-dirs vim git wget curl gum)
  _gum spin --spinner dot --title "pacstrap base + core packages" -- pacstrap /mnt "${base_pkgs[@]}"

  [[ -f /etc/vconsole.conf ]] && install -Dm644 /etc/vconsole.conf /mnt/etc/vconsole.conf
  genfstab -U /mnt >> /mnt/etc/fstab
  echo_ok "Generated fstab:"
  grep -v '^#' /mnt/etc/fstab | sed 's/^/  /'

  copy_lnos_files
  write_chroot_script
  run_chroot_script
  install_bootloader

  umount -R /mnt || true
  for i in {10..1}; do echo_ok "Installation complete. Rebooting in $i..."; sleep 1; done
  reboot
}

usage() {
  cat <<USG
Usage: $0 --target=x86_64 [--flavor=sandbox|stable] [--tz=Region/City] [--kernel=hardened|vanilla] | -h

Options:
  --target=x86_64            Install LnOS on an x86_64 system (UEFI or BIOS)
  --flavor=VALUE             Set build flavor recorded in /etc/os-release (default: sandbox)
  --tz=Region/City           Timezone for installed system (default: America/Chicago)
  --kernel=CHOICE            linux-hardened (default) or linux (vanilla)
  -h, --help                 Show help

Notes:
 • Run this from a live ISO (it will wipe the selected disk).
 • Requires network for full package install.
USG
}

main() {
  local target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target=*) target="${1#*=}"; shift;;
      --flavor=*) FLAVOR="${1#*=}"; shift;;
      --tz=*)     TZ="${1#*=}"; shift;;
      --kernel=*) KERNEL_CHOICE="${1#*=}"; shift;;
      -h|--help)  usage; exit 0;;
      *) echo_w "Ignoring unknown arg: $1"; shift;;
    esac
  done
  case "$target" in
    x86_64) install_x86_64 ;;
    *) usage; exit 1 ;;
  esac
}
main "$@"

# Example usage:
# Typical run (live ISO shell)
# scripts/LnOS-installer.sh --target=x86_64

# TBD for LnOS - set flavor + tz + kernel
# scripts/LnOS-installer.sh --target=x86_64 --flavor=sandbox --tz=America/Chicago --kernel=hardened
