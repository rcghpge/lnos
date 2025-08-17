#!/usr/bin/env bash
# /*
#  Copyright 2025 UTA-LugNuts Authors.
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#      http://www.apache.org/licenses/LICENSE-2.0
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# */
#
# @file LnOS-installer.sh
# @brief End-to-end installer for LnOS on x86_64 and aarch64 (ARM)
# @authors
#   Original: Betim-Hodza, Ric3y
#   Revisions: rcghpge + LugNuts — robust UI, x86_64 & aarch64 flows, btrfs subvols
# @date 2025

set -Eeuo pipefail

# ---------------------- Config (env/flags) ----------------------
FLAVOR=${FLAVOR:-sandbox}
TZ=${TZ:-America/Chicago}
KERNEL_X64=${KERNEL_X64:-hardened}   # hardened|vanilla
REBOOT_ON_FINISH=${REBOOT_ON_FINISH:-1}
LNOS_REPO_DEFAULT="/root/LnOS"

# ---------------------- Detect clone tree ----------------------
CLONED=0
if [[ -f /root/LnOS/pacman_packages/CSE_packages.txt ]] && grep -q "git" /root/LnOS/pacman_packages/CSE_packages.txt; then
  CLONED=0
elif [[ -f /root/LnOS/scripts/pacman_packages/CSE_packages.txt ]] && grep -q "git" /root/LnOS/scripts/pacman_packages/CSE_packages.txt; then
  CLONED=1
fi

# ---------------------- Sanity/host checks ----------------------
require_root() { if [[ $EUID -ne 0 ]]; then echo "[ERR] Run as root." >&2; exit 1; fi; }
require_host_tools() {
  local need=(lsblk parted wipefs mkfs.fat mkfs.ext4 mkfs.btrfs btrfs mount umount pacstrap genfstab arch-chroot)
  local miss=()
  for t in "${need[@]}"; do command -v "$t" >/dev/null 2>&1 || miss+=("$t"); done
  if (( ${#miss[@]} )); then
    echo "[ERR] Missing host tools: ${miss[*]}" >&2
    exit 1
  fi
}
trap 'echo_e "Installation failed on line $LINENO (command: ${BASH_COMMAND:-?})."; umount -R /mnt >/dev/null 2>&1 || true' ERR

# ---------------------- Robust UI helpers (gum optional) ----------------------
_have_gum() { command -v gum >/dev/null 2>&1; }
ui_box() { local c="${1:-33}"; shift || true; if _have_gum; then gum style --border normal --margin "1 2" --padding "1 3" --border-foreground "$c" "$*"; else printf "\n[%s] %s\n\n" "$c" "$*"; fi; }
echo_b()  { ui_box 33  "$*"; }
echo_ok() { ui_box 82  "$*"; }
echo_w()  { ui_box 208 "$*"; }
echo_e()  { ui_box 196 "$*"; }
ui_confirm() { if _have_gum; then gum confirm "$1"; else read -r -p "$1 [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]]; fi }
ui_input() { if _have_gum; then gum input "$@"; else local pw=0; [[ "${1:-}" == "--password" ]] && { pw=1; shift; }; local p="${1:-}"; shift || true; local v; if (( pw )); then read -r -s -p "$p " v; echo; else read -r -p "$p " v; fi; printf "%s" "$v"; fi }
ui_choose() { # header, then args or stdin
  local header="$1"; shift || true
  if _have_gum; then if [[ $# -gt 0 ]]; then gum choose --header "$header" "$@"; else gum choose --header "$header"; fi; return; fi
  local opts=(); if [[ $# -gt 0 ]]; then mapfile -t opts < <(printf "%s\n" "$@"); else if [[ ! -t 0 ]]; then mapfile -t opts; fi; fi
  (( ${#opts[@]} )) || { echo_e "No options available for: $header"; return 1; }
  printf "%s\n" "$header"; local i idx=1; for i in "${opts[@]}"; do printf "  [%d] %s\n" "$idx" "$i"; ((idx++)); done
  local choice; while true; do read -r -p "Enter number: " choice; [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#opts[@]} )) && { printf "%s" "${opts[choice-1]}"; return 0; }; echo "Invalid choice."; done
}

# ---------------------- Bootstrap host (keys, net, gum) ----------------------
bootstrap_host() {
  pacman-key --init >/dev/null 2>&1 || true
  sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || true
  command -v gum >/dev/null 2>&1 || pacman -Sy --noconfirm gum >/dev/null 2>&1 || true
  command -v nmtui >/dev/null 2>&1 || pacman -Sy --noconfirm networkmanager >/dev/null 2>&1 || true
  echo_b "Connect to the internet (nmtui recommended)."
  ui_confirm "Open nmtui now?" && nmtui || true
  if ! ping -c1 -W2 archlinux.org >/dev/null 2>&1; then echo_w "No ping; will proceed (pacstrap may fail offline)."; fi
}

# ---------------------- Shared helpers ----------------------
LNOS_REPO=${LNOS_REPO:-$LNOS_REPO_DEFAULT}
copy_lnos_files() {
  local SRC="$LNOS_REPO"
  if (( CLONED )); then SRC="/root/LnOS"; fi
  if [[ -d "$SRC" ]]; then
    mkdir -p /mnt/root/LnOS
    cp -r "$SRC/scripts/pacman_packages" /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$SRC/scripts/paru_packages"   /mnt/root/LnOS/ 2>/dev/null || true
    cp -r "$SRC/docs"                    /mnt/root/LnOS/ 2>/dev/null || true
    for f in README.md LICENSE AUTHORS SUMMARY.md TODO.md; do [[ -f "$SRC/$f" ]] && cp "$SRC/$f" /mnt/root/LnOS/ || true; done
    echo_ok "LnOS payload copied into target /root/LnOS"
  else
    echo_w "LnOS repo not found at $SRC — skipping payload copy."
  fi
}

write_chroot_script_common() {
  cat > /mnt/root/.lnos-post.sh <<'CHROOT'
#!/usr/bin/env bash
set -Eeuo pipefail
_have_gum() { command -v gum >/dev/null 2>&1; }
ui_box() { local c="${1:-33}"; shift || true; if _have_gum; then gum style --border normal --margin "1 2" --padding "1 3" --border-foreground "$c" "$*"; else printf "\n[%s] %s\n\n" "$c" "$*"; fi; }
echo_b()  { ui_box 33  "$*"; }
echo_ok() { ui_box 82  "$*"; }
echo_w()  { ui_box 208 "$*"; }
echo_e()  { ui_box 196 "$*"; }
ui_confirm() { if _have_gum; then gum confirm "$1"; else read -r -p "$1 [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]]; fi }
ui_input() { if _have_gum; then gum input "$@"; else local pw=0; [[ "${1:-}" == "--password" ]] && { pw=1; shift; }; local p="${1:-}"; shift || true; local v; if (( pw )); then read -r -s -p "$p " v; echo; else read -r -p "$p " v; fi; printf "%s" "$v"; fi }
ui_choose() { local h="$1"; shift || true; if _have_gum; then if [[ $# -gt 0 ]]; then gum choose --header "$h" "$@"; else gum choose --header "$h"; fi; return; fi; local a=(); if [[ $# -gt 0 ]]; then mapfile -t a < <(printf "%s\n" "$@"); else if [[ ! -t 0 ]]; then mapfile -t a; fi; fi; (( ${#a[@]} )) || { echo_e "No options: $h"; return 1; }; printf "%s\n" "$h"; local i idx=1; for i in "${a[@]}"; do printf "  [%d] %s\n" "$idx" "$i"; ((idx++)); done; local c; while true; do read -r -p "Enter number: " c; [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=${#a[@]} )) && { printf "%s" "${a[c-1]}"; return 0; }; echo "Invalid choice."; done }

# Base locale/time/host
ln -sf /usr/share/zoneinfo/__TZ__ /etc/localtime
hwclock --systohc || true
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || true
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LnOS" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 LnOS
EOF

# NetworkManager + sudo
pacman -S --noconfirm networkmanager sudo >/dev/null 2>&1 || true
systemctl enable NetworkManager.service 2>/dev/null || true
install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO

# Root password
while true; do r1=$(ui_input --password "Enter root password:"); r2=$(ui_input --password "Confirm root password:"); [[ "$r1" == "$r2" && -n "$r1" ]] && { echo "root:$r1" | chpasswd; break; }; ui_confirm "Passwords do not match. Try again?" || exit 1; done

# User
uname=""; while [[ -z "${uname}" ]]; do uname=$(ui_input "Enter username:"); [[ -z "$uname" ]] && echo_e "Username cannot be empty."; uname=$(printf "%s" "$uname" | tr 'A-Z' 'a-z'); [[ "$uname" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo_e "Invalid username."; uname=""; }; done
useradd -m -G wheel,audio,video,input,sys,lp,adm,log,rfkill -s /bin/bash "$uname"
while true; do p1=$(ui_input --password "Enter password for $uname:"); p2=$(ui_input --password "Confirm password for $uname:"); [[ "$p1" == "$p2" && -n "$p1" ]] && { echo "$uname:$p1" | chpasswd; break; }; ui_confirm "Passwords do not match. Try again?" || exit 1; done

# DE selection
choose_de() { ui_choose "Choose Desktop Environment" "GNOME (user-friendly)" "KDE Plasma (Windows-like)" "Hyprland (tiling, DIY)" "TTY only (no GUI)"; }
install_de() { case "$1" in GNOME*) pacman -S --noconfirm xorg-server gnome gdm && systemctl enable gdm.service ;; KDE\ Plasma*) pacman -S --noconfirm xorg-server plasma kde-applications sddm && systemctl enable sddm.service ;; Hyprland*) pacman -S --noconfirm wayland xorg-xwayland hyprland noto-fonts noto-fonts-emoji kitty ;; TTY\ only*) : ;; esac }
DESEL="$(choose_de || echo 'TTY only (no GUI)')"; ui_confirm "Install: $DESEL ?" && install_de "$DESEL"

# Package profiles
profile=$(ui_choose "Choose installation profile" CSE Custom)
if [[ "$profile" == "CSE" ]]; then
  if [[ -f /root/LnOS/pacman_packages/CSE_packages.txt ]]; then pac_pkgs=$(tr '\n' ' ' < /root/LnOS/pacman_packages/CSE_packages.txt); fi
  [[ -n "${pac_pkgs:-}" ]] && pacman -S --noconfirm $pac_pkgs || true
  if [[ -f /root/LnOS/paru_packages/paru_packages.txt ]]; then pacman -S --noconfirm base-devel git; tmpd=$(mktemp -d); pushd "$tmpd" >/dev/null; git clone https://aur.archlinux.org/paru.git; cd paru && makepkg -si --noconfirm; popd >/dev/null; rm -rf "$tmpd"; aur_pkgs=$(tr '\n' ' ' < /root/LnOS/paru_packages/paru_packages.txt); echo_w "AUR is community-maintained."; ui_confirm "Proceed with AUR packages?" && paru -S --noconfirm $aur_pkgs || true; fi
else
  read -r -p "Enter pacman packages (space-separated): " pac_pkgs || true; [[ -n "${pac_pkgs:-}" ]] && pacman -S --noconfirm $pac_pkgs || true
  echo_w "AUR is community-maintained."; if ui_confirm "Install AUR packages?"; then pacman -S --noconfirm base-devel git; tmpd=$(mktemp -d); pushd "$tmpd" >/dev/null; git clone https://aur.archlinux.org/paru.git; cd paru && makepkg -si --noconfirm; popd >/dev/null; rm -rf "$tmpd"; read -r -p "Enter paru packages (space-separated): " aur_pkgs || true; [[ -n "${aur_pkgs:-}" ]] && paru -S --noconfirm $aur_pkgs || true; fi
fi

echo_ok "Chroot configuration complete."
CHROOT
  sed -i "s#__TZ__#${TZ}#g" /mnt/root/.lnos-post.sh
  chmod +x /mnt/root/.lnos-post.sh
}

# ---------------------- x86_64 flow ----------------------
select_kernel_x64() {
  local sel
  sel="$(ui_choose 'Choose kernel (x86_64)' 'linux-hardened (default)' 'linux (vanilla)')" || { echo_e "Kernel selection aborted."; exit 1; }
  case "$sel" in 'linux (vanilla)') KERNEL_X64=vanilla ;; *) KERNEL_X64=hardened ;; esac
  echo_ok "Kernel: $KERNEL_X64"
}

select_disk_and_partition() {
  local rows choice name
  rows="$(lsblk -d -o NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print $1"\t"$2"\t"$3}')" || true
  [[ -z "$rows" ]] && { echo_e "No disks found."; exit 1; }
  echo_b "Available disks:"; lsblk -o NAME,SIZE,MODEL,TYPE
  choice="$(printf "%s\n" "$rows" | ui_choose "Select target disk (ERASES ALL DATA):")" || { echo_w "Aborted."; exit 1; }
  name="$(awk '{print $1}' <<<"$choice")"; [[ -b "/dev/$name" ]] || { echo_e "Invalid disk: $name"; exit 1; }
  DISK="/dev/$name"; [[ "$name" == nvme* ]] && NVME=1 || NVME=0; [[ -d /sys/firmware/efi ]] && UEFI=1 || UEFI=0
  echo_w "Target: $DISK | Firmware: $([[ $UEFI -eq 1 ]] && echo UEFI || echo BIOS)"
  ui_confirm "FINAL CONFIRM: WIPE and partition $DISK?" || { echo_w "Aborted."; exit 1; }

  # clean & create table
  wipefs -a "$DISK" || true
  local ESP_START=1 ESP_END=513 BOOT_SIZE=1025
  local ram_gb; ram_gb=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
  local SWAP_SIZE=0; (( ram_gb < 15 )) && SWAP_SIZE=4096

  if (( UEFI )); then
    parted -s "$DISK" mklabel gpt
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
    parted -s "$DISK" mklabel gpt
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

  # format & mount
  local pfx="${DISK}"; (( NVME )) && pfx="${DISK}p"
  if (( UEFI )); then mkfs.fat -F32 "${pfx}${ESP_PART}"; mkfs.ext4 -F "${pfx}${BOOT_PART}"; else mkfs.ext4 -F "${pfx}${BOOT_PART}"; fi
  if [[ -n "${SWAP_PART:-}" ]]; then mkswap "${pfx}${SWAP_PART}"; swapon "${pfx}${SWAP_PART}" || true; fi
  mkfs.btrfs -f "${pfx}${ROOT_PART}"
  mount "${pfx}${ROOT_PART}" /mnt; btrfs subvolume create /mnt/@; btrfs subvolume create /mnt/@home; btrfs subvolume create /mnt/@log; btrfs subvolume create /mnt/@pkg; umount /mnt
  local base=$(basename "$DISK"); local opts="noatime,compress=zstd:3"; [[ -r "/sys/block/$base/queue/rotational" && $(cat "/sys/block/$base/queue/rotational") -eq 0 ]] && opts="$opts,ssd"
  mount -o subvol=@,$opts "${pfx}${ROOT_PART}" /mnt
  mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot}
  mount -o subvol=@home,$opts "${pfx}${ROOT_PART}" /mnt/home
  mount -o subvol=@log,$opts  "${pfx}${ROOT_PART}" /mnt/var/log
  mount -o subvol=@pkg,$opts  "${pfx}${ROOT_PART}" /mnt/var/cache/pacman/pkg
  if (( UEFI )); then mkdir -p /mnt/boot/efi; mount "${pfx}${BOOT_PART}" /mnt/boot; mount "${pfx}${ESP_PART}" /mnt/boot/efi; else mount "${pfx}${BOOT_PART}" /mnt/boot; fi
}

install_base_x64() {
  echo_b "Installing base system (x86_64)"
  local pkgs=(base btrfs-progs xdg-user-dirs vim git wget curl gum networkmanager sudo linux-firmware)
  case "$KERNEL_X64" in hardened) pkgs+=(linux-hardened) ;; *) pkgs+=(linux) ;; esac
  pacstrap /mnt "${pkgs[@]}"
  [[ -f /etc/vconsole.conf ]] && install -Dm644 /etc/vconsole.conf /mnt/etc/vconsole.conf
  genfstab -U /mnt >> /mnt/etc/fstab
  echo_ok "fstab generated"
}

configure_chroot_common() { write_chroot_script_common; arch-chroot /mnt /root/.lnos-post.sh; }

install_bootloader_x64() {
  if [[ -d /sys/firmware/efi ]]; then
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  else
    arch-chroot /mnt pacman -S --noconfirm grub
    arch-chroot /mnt grub-install --target=i386-pc "$DISK"
  fi
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

install_x86_64() {
  select_kernel_x64
  select_disk_and_partition
  install_base_x64
  copy_lnos_files
  configure_chroot_common
  install_bootloader_x64
}

# ---------------------- aarch64 flows ----------------------
# Two modes: (1) Generic UEFI ARM boards (grub-efi-aarch64), (2) Raspberry Pi firmware flow

partition_arm_uefi() {
  select_disk_and_partition # reuse x86_64 partitioner (ESP + /boot ext4 + btrfs root)
}

install_base_arm_uefi() {
  echo_b "Installing base system (aarch64 UEFI)"
  local pkgs=(base linux-aarch64 linux-firmware btrfs-progs xdg-user-dirs vim git wget curl gum networkmanager sudo grub efibootmgr)
  pacstrap /mnt "${pkgs[@]}"
  genfstab -U /mnt >> /mnt/etc/fstab
}

install_bootloader_arm_uefi() {
  arch-chroot /mnt grub-install --target=aarch64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

install_aarch64_uefi() {
  partition_arm_uefi
  install_base_arm_uefi
  copy_lnos_files
  write_chroot_script_common
  # flavor + os-release for ARM
  arch-chroot /mnt bash -lc 'if [ -L /etc/os-release ]; then rm -f /etc/os-release; fi; cat > /etc/os-release <<OSR\nNAME="LnOS"\nPRETTY_NAME="LnOS (Arch Linux ARM) - __FLAVOR__"\nID=arch\nID_LIKE=arch\nVARIANT="LnOS"\nVARIANT_ID=lnos\nBUILD_ID=rolling\nBUILD_FLAVOR="__FLAVOR__"\nANSI_COLOR="38;2;23;147;209"\nHOME_URL="https://github.com/uta-lug-nuts/LnOS"\nDOCUMENTATION_URL="https://github.com/uta-lug-nuts/LnOS"\nSUPPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"\nBUG_REPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"\nOSR'
  sed -i "s#__FLAVOR__#${FLAVOR}#g" /mnt/etc/os-release
  arch-chroot /mnt /root/.lnos-post.sh
  install_bootloader_arm_uefi
}

# ---- Raspberry Pi (firmware boot, no GRUB) ----
# We expect a prebuilt Arch Linux ARM rootfs tarball. We'll prompt for source.
prepare_rpi_rootfs() {
  echo_b "Raspberry Pi rootfs setup"
  local rows choice name
  rows="$(lsblk -d -o NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print $1"\t"$2"\t"$3}')" || true
  [[ -z "$rows" ]] && { echo_e "No disks found for SD card."; exit 1; }
  choice="$(printf "%s\n" "$rows" | ui_choose "Select SD card device (ERASES ALL DATA):")" || { echo_w "Aborted."; exit 1; }
  name="$(awk '{print $1}' <<<"$choice")"; [[ -b "/dev/$name" ]] || { echo_e "Invalid disk: $name"; exit 1; }
  DISK="/dev/$name"; local pfx="${DISK}"; [[ "$name" == nvme* ]] && pfx="${DISK}p"
  ui_confirm "FINAL CONFIRM: wipe $DISK ?" || { echo_w "Aborted."; exit 1; }

  wipefs -a "$DISK" || true
  parted -s "$DISK" mklabel msdos
  parted -s "$DISK" mkpart primary fat32 1MiB 257MiB
  parted -s "$DISK" set 1 lba on
  parted -s "$DISK" mkpart primary btrfs 257MiB 100%
  mkfs.fat -F32 "${pfx}1"; mkfs.btrfs -f "${pfx}2"
  mount "${pfx}2" /mnt; mkdir -p /mnt/boot; mount "${pfx}1" /mnt/boot

  # Get rootfs tarball
  local src
  src=$(ui_choose "Select RPi tarball source" "Enter URL manually" "Enter local file path") || true
  local tarpath=""
  if [[ "$src" == "Enter URL manually" ]]; then
    url=$(ui_input "Paste Arch Linux ARM RPi (aarch64) tarball URL:")
    [[ -n "$url" ]] || { echo_e "No URL provided."; exit 1; }
    echo_b "Downloading..."; wget -O /tmp/archlinuxarm-rpi.tar.gz "$url"
    tarpath=/tmp/archlinuxarm-rpi.tar.gz
  else
    tarpath=$(ui_input "Enter local tarball path:")
    [[ -f "$tarpath" ]] || { echo_e "File not found: $tarpath"; exit 1; }
  fi
  echo_b "Extracting rootfs (this may take a while)"; tar -xpf "$tarpath" -C /mnt

  # Minimal config files (avoid chroot complexity if host != aarch64)
  echo "$TZ" > /mnt/etc/TZ 2>/dev/null || true
  echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
  echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
  echo "LnOS" > /mnt/etc/hostname
  printf "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 LnOS\n" > /mnt/etc/hosts
  mkdir -p /mnt/etc/systemd/system
  arch-chroot /mnt /bin/bash -c "locale-gen || true" || true
  arch-chroot /mnt /bin/bash -c "pacman -Syu --noconfirm networkmanager sudo btrfs-progs" || true
  arch-chroot /mnt /bin/bash -c "systemctl enable NetworkManager" || true

  copy_lnos_files
  write_chroot_script_common
  # Try chroot with qemu-user-static if available; otherwise leave for first boot
  if command -v qemu-aarch64-static >/dev/null 2>&1; then
    mkdir -p /mnt/usr/bin
    cp "$(command -v qemu-aarch64-static)" /mnt/usr/bin/
    arch-chroot /mnt /root/.lnos-post.sh || echo_w "Chroot user setup skipped. Complete on first boot."
  else
    echo_w "qemu-aarch64-static not found; will finish user setup on first boot."
  fi

  umount -R /mnt
  echo_ok "SD card prepared. Insert into Raspberry Pi and boot."
}

install_aarch64() {
  local mode
  mode="$(ui_choose 'Choose aarch64 target' 'Generic UEFI ARM board (GRUB)' 'Raspberry Pi (firmware, no GRUB)')" || { echo_w "Aborted."; exit 1; }
  case "$mode" in
    'Generic UEFI ARM board (GRUB)') install_aarch64_uefi ;;
    'Raspberry Pi (firmware, no GRUB)') prepare_rpi_rootfs ;;
  esac
}

# ---------------------- CLI & main ----------------------
usage() {
  cat <<USG
Usage: $0 --target=(x86_64|aarch64) [--flavor=sandbox|stable] [--tz=Region/City] [--kernel=hardened|vanilla] [--no-reboot]

Notes:
 • Run from an appropriate live environment. This WILL ERASE the selected disk.
 • aarch64 supports: (a) Generic UEFI ARM boards with GRUB; (b) Raspberry Pi via firmware tarball.
USG
}

main() {
  require_root; require_host_tools; bootstrap_host
  local target=""; while [[ $# -gt 0 ]]; do case "$1" in --target=*) target="${1#*=}"; shift;; --flavor=*) FLAVOR="${1#*=}"; shift;; --tz=*) TZ="${1#*=}"; shift;; --kernel=*) KERNEL_X64="${1#*=}"; shift;; --no-reboot) REBOOT_ON_FINISH=0; shift;; -h|--help) usage; exit 0;; *) echo_w "Ignoring unknown arg: $1"; shift;; esac; done
  case "$target" in
    x86_64) install_x86_64 ;;
    aarch64) install_aarch64 ;;
    *) usage; exit 1 ;;
  esac
  umount -R /mnt >/dev/null 2>&1 || true
  if (( REBOOT_ON_FINISH )) && [[ "$target" == x86_64 ]]; then for i in {10..1}; do echo_ok "Installation complete. Rebooting in $i..."; sleep 1; done; reboot; else echo_ok "Done. You may reboot when ready."; fi
}

main "$@"
