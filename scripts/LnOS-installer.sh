#!/usr/bin/env bash

# /*
# Copyright 2025 UTA-LugNuts Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */


#
# @file LnOS-installer.sh
# @brief Installs Arch linux and 
# @author Betim-Hodza, Ric3y, rcghpge
# @date 2025
#

# LnOS-installer.sh — Arch-based installer for LnOS (x86_64).
# - Partitions disk (UEFI/BIOS), formats ESP + btrfs, mounts target
# - Installs base + linux-hardened, generates initramfs (fixes VFS panics)
# - Installs GRUB correctly for the platform
# - Optionally installs a DE profile and extra packages
# - Copies the LnOS repo into the installed system for post-install docs/scripts

set -euo pipefail
cleanup(){ umount -R /mnt 2>/dev/null || true; }
trap cleanup EXIT

# ---------- Repo autodetect ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LNOS_REPO=""

for CAND in \
  "$SCRIPT_DIR" \
  "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)" \
  "/root/LnOS" "/root/lnos" "/lnos"
do
  [ -n "${CAND:-}" ] && [ -d "$CAND" ] && [ -f "$CAND/README.md" ] && LNOS_REPO="$CAND" && break
done

if [ -z "$LNOS_REPO" ]; then
  echo "ERROR: Could not locate LnOS repo root. Set LNOS_REPO env var and rerun." >&2
  exit 1
fi

repo_file() {
  # Prefer top-level paths, fallback to scripts/ layout
  local p1="$LNOS_REPO/$1" p2="$LNOS_REPO/scripts/$1"
  if   [ -e "$p1" ]; then printf '%s\n' "$p1"
  elif [ -e "$p2" ]; then printf '%s\n' "$p2"
  else return 1
  fi
}

# ---------- Pretty logging ----------
gum_echo()     { gum style --border normal --margin "1 2" --padding "2 4" --border-foreground 130 "$@"; }
gum_error()    { gum style --border double --margin "1 2" --padding "2 4" --border-foreground 1 "$@"; }
gum_complete() { gum style --border normal --margin "1 2" --padding "2 4" --border-foreground 158 "$@"; }

# ---------- Live env prerequisites ----------
pacman-key --init
pacman-key --populate archlinux

if ! command -v gum >/dev/null 2>&1; then
  pacman -Sy --noconfirm gum
fi
if ! command -v rsync >/dev/null 2>&1; then
  pacman -Sy --noconfirm rsync
fi
if ! command -v nmtui >/dev/null 2>&1; then
  pacman -Sy --noconfirm networkmanager
fi

gum_echo "Connect to the internet (installer requires it). Launch nmtui?"
gum confirm && nmtui || true

# ---------- Desktop + packages ----------
setup_desktop_and_packages() {
  local username="$1"

  gum_echo "Installing developer tools and basics…"
  pacman -S --noconfirm base-devel git wget curl openssh networkmanager dhcpcd vi vim iw xdg-user-dirs

gum_echo "Connect to the internet? (Installer won't work without it)"
gum confirm || exit

  local DE_CHOICE
  DE_CHOICE=$(gum choose --header "Choose your Desktop Environment (DE):" \
    "GNOME (beginner-friendly, mac-like)" \
    "KDE Plasma (beginner-friendly, Windows-like)" \
    "Hyprland (tiling WM)" \
    "DWM (tiling WM, not implemented)" \
    "TTY (no install required)")

  if [[ "$DE_CHOICE" != "TTY (no install required)" ]]; then
    gum confirm "You selected: $DE_CHOICE. Proceed?" || return
  fi

  case "$DE_CHOICE" in
    GNOME*)
      gum_echo "Installing GNOME…"
      pacman -S --noconfirm xorg xorg-server gnome gdm
      systemctl enable gdm.service
      ;;
    KDE*)
      gum_echo "Installing KDE Plasma…"
      pacman -S --noconfirm xorg xorg-server plasma kde-applications sddm
      systemctl enable sddm.service
      ;;
    Hyprland*)
      gum_echo "Installing Hyprland prerequisites…"
      pacman -S --noconfirm wayland hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra kitty networkmanager
      gum_echo "Optional: downloading JaKooLit Hyprland bootstrap to \$HOME"
      wget -O "/home/$username/auto-install.sh" \
        https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh || true
      chown "$username:$username" "/home/$username/auto-install.sh" || true
      ;;
    "DWM (tiling WM, not implemented)")
      gum_echo "[NOTE] DWM option is a placeholder for now."
      ;;
    *)
      gum_echo "Staying on TTY."
      ;;
  esac

  # Profile selection
  local THEME
  THEME=$(gum choose --header "Choose your installation profile:" "CSE" "Custom")
  gum confirm "Proceed with '$THEME' profile?" || return

  case "$THEME" in
    CSE)
      local PACMAN_PACKAGES PARU_PACKAGES
      if PACMAN_PACKAGES_PATH="$(repo_file pacman_packages/CSE_packages.txt)"; then
        PACMAN_PACKAGES="$(tr '\n' ' ' < "$PACMAN_PACKAGES_PATH")"
        [ -n "$PACMAN_PACKAGES" ] && gum_echo "Installing CSE pacman packages…" && \
          pacman -S --noconfirm $PACMAN_PACKAGES
      else
        gum_error "CSE_packages.txt not found in repo."
      fi

    # Desktop Environment Installation
    while true; do
		DE_CHOICE=$(gum choose --header "Choose your Desktop Environment (DE):" \
            "Gnome(Good for beginners, similar to Mac)" \
            "KDE(Good for beginners, similar to Windows)" \
            "Hyprland(Tiling WM, basic dotfiles but requires more DIY)" \
            "DWM(Similar to Hyprland)" \
            "TTY (No install required)")
            
		if [[ "$DE_CHOICE" == "TTY (No install required)" ]]; then
			echo "TTY is preinstalled !"
            break
        fi
        
        gum confirm "You selected: $DE_CHOICE. Proceed with installation?" && break
        gum_echo "Returning to selection menu..."
    done

    case "$DE_CHOICE" in
        "Gnome(Good for beginners, similar to Mac)")
            gum_echo "Installing Gnome..."
            pacman -S --noconfirm xorg xorg-server gnome gdm
            systemctl enable gdm.service
            ;;
				"KDE(Good for beginners, similar to Windows)")
            gum_echo "Installing KDE..."
            pacman -S --noconfirm xorg xorg-server plasma kde-applications sddm
            systemctl enable sddm.service
            ;;
        "Hyprland(Tiling WM, basic dotfiles but requires more DIY)")
            gum_echo "Installing Hyprland..."
            pacman -S --noconfirm wayland hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra kitty networkmanager

            # call and run JaKooLit's arch hyprland install
            gum_echo "Downloading JaKooLit's Hyprland, please run the script after installation!"
            sleep 2
            wget https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh
        
            ;;
		"DWM(Similar to Hyprland)")
            gum_echo "Installing DWM..."
			gum_echo "[WARNING] DWM requires more work in the future, for now this option doesn't do anything"
            #pacman -S --noconfirm uwsm
            #systemctl enable lightdm.service
            ;;
    esac

    # Package Installation
    while true; do
        THEME=$(gum choose --header "Choose your installation profile:" "CSE" "Custom")
        gum confirm "You selected: $THEME. Proceed with installation?" && break
    done

    case "$THEME" in
        "CSE")
            # ensure we have the right packages
            PACMAN_PACKAGES=$(cat /root/LnOS/pacman_packages/CSE_packages.txt)
            if [ ! -f "/root/LnOS/pacman_packages/CSE_packages.txt" ]; then
                gum_error  "Error: CSE_packages.txt not found in /root/LnOS/pacman_packages/. ."
            else
                # checking if cloned
                if $CLONED ; then
                    PACMAN_PACKAGES=$(cat /root/LnOS/scripts/pacman_packages/CSE_packages.txt)
                else
                    gum_error "Error: CSE_packages.txt not found in /root/LnOS/scripts/pacman_packages/."
                    exit 1
                fi
            fi
			# Choose packages from CSE list (PACMAN)
            PACMAN_PACKAGES=$(cat /root/LnOS/pacman_packages/CSE_packages.txt)
            gum spin --spinner dot --title "Installing pacman packages..." -- pacman -S --noconfirm "$PACMAN_PACKAGES" 

            # AUR will most likely be short with a few packages
            # webcord, brave are the big ones that come to mind
            # the reason is id like to teach users how to properly use aur
            gum style \
                --foreground 255 --border-foreground 130 --border double \
                --width 100 --margin "1 2" --padding "2 4" \
                'AUR (Arch User Repository) is less secure because its not maintained by Arch.' \
                'LnOS Maintainers picked these packages because their releases are signed with PGP keys' \
            gum confirm "Will you proceed to download AUR packages ? (i.e. brave, webcord)" || return
            
            # clone paru and build
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si
            # exit and clean up paru
            cd ..
            rm -rf paru


            gum_echo "Please review the packages you're about to download"
            # check if we have the right packages
            PARU_PACKAGES=$(cat /root/LnOS/paru_packages/paru_packages.txt)
            if [ ! -f "/root/LnOS/paru_packages/paru_packages.txt" ]; then
                gum_error  "Error: CSE_packages.txt not found in /root/LnOS/paru_packages/. ."
            else
                # checking if cloned
                if $CLONED ; then
                    PARU_PACKAGES=$(cat /root/LnOS/scripts/paru_packages/paru_packages.txt)
                else
                    gum_error "Error: CSE_packages.txt not found in /root/LnOS/scripts/paru_packages/."
                    exit 1
                fi
            fi
            paru -S "$PARU_PACKAGES"


            ;;
        "Custom")
            PACMAN_PACKAGES=$(gum input --header "Enter the pacman packages you want (space-separated):")
            if [ -n "$PACMAN_PACKAGES" ]; then
                gum spin --spinner dot --title "Installing pacman packages..." -- pacman -S --noconfirm "$PACMAN_PACKAGES"
            fi

            gum_echo "AUR (Arch User Repository) is less secure because it's not maintained by Arch. LnOS Maintainers picked these packages because their releases are signed with PGP keys"
            gum confirm "Will you proceed to download AUR packages ? (i.e. brave, webcord)" || return
            
            # clone paru and build
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si
            # exit and clean up paru
            cd ..
            rm -rf paru


            gum_echo "Please enter and review the packages you're about to download"
            PARU_PACKAGES=$(gum input --header "Enter the paru packages you want (space-seperated):")
            if [ -n "$PARU_PACKAGES" ]; then
                paru -S "$PARU_PACKAGES"
            fi
            
            ;;
    esac
}

# Function to configure the system (common for both architectures)
configure_system()
{
    # install gum again for pretty format
    pacman -Sy --noconfirm gum

    # Set timezone
    ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
    hwclock --systohc

    # Set locale
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # Set hostname
    echo "LnOs" > /etc/hostname

    # Set hosts file
    echo "127.0.0.1 localhost" > /etc/hosts
    echo "::1 localhost" >> /etc/hosts

    # Add DNS servers
    echo "nameserver 1.1.1.1" > /etc/resolv.conf # Cloudflare

    # Set root password
    while true; do
        rtpass=$(gum input --password --placeholder="Enter root password: ")
        rtpass_verify=$(gum input --password --placeholder="Enter root password again: ")
        if [ "$rtpass" = "$rtpass_verify" ]; then
            echo "root:$rtpass" | chpasswd
            break
        else
          gum_error "paru_packages.txt not found in repo."
        fi
      fi
      ;;
    Custom)
      local PACMAN_PACKAGES
      PACMAN_PACKAGES="$(gum input --header "Enter extra pacman packages (space-separated):")"
      [ -n "$PACMAN_PACKAGES" ] && pacman -S --noconfirm $PACMAN_PACKAGES || true

      gum style --foreground 255 --border-foreground 130 --border double \
        --width 100 --margin "1 2" --padding "2 4" \
        "Install AUR packages via paru?"
      if gum confirm "Proceed with paru install?"; then
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        pushd /tmp/paru >/dev/null
        makepkg -si --noconfirm
        popd >/dev/null
        rm -rf /tmp/paru

        local PARU_PACKAGES
        PARU_PACKAGES="$(gum input --header "Enter AUR packages (space-separated):")"
        [ -n "$PARU_PACKAGES" ] && paru -S --noconfirm $PARU_PACKAGES || true
      fi
      ;;
  esac

		# Get users password
    while true; do
        uspass=$(gum input --password --placeholder="Enter password for $username: ")
        uspass_verify=$(gum input --password --placeholder="Enter password for $username again: ")
        if [ "$uspass" = "$uspass_verify" ]; then
            echo "$username:$uspass" | chpasswd
            break
        else
            gum confirm "Passwords do not match. Try again?" || exit 1
        fi
    done

    # Configure sudoers for wheel group
    pacman -S --noconfirm sudo
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
    chmod 440 /etc/sudoers.d/10-wheel

    # Update 
    pacman -Syu --noconfirm

    
    # setup the desktop environment
    setup_desktop_and_packages "$username"

	gum_echo "LnOS Basic DE/Package install completed!"

    exit 0
}

# ---------- System configuration (chroot) ----------
configure_system() {
  pacman -Sy --noconfirm gum || true

  ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
  hwclock --systohc

  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf

  echo "LnOS" > /etc/hostname
  {
    echo "127.0.0.1 localhost"
    echo "::1       localhost"
  } > /etc/hosts

  echo "nameserver 1.1.1.1" > /etc/resolv.conf

  # Root password
  while true; do
    rtpass=$(gum input --password --placeholder="Enter root password: ")
    rtpass_verify=$(gum input --password --placeholder="Enter root password again: ")
    if [ "$rtpass" = "$rtpass_verify" ]; then
      echo "root:$rtpass" | chpasswd
      break
    else
      gum confirm "Passwords do not match. Try again?" || exit 1
    fi
  done

  # Create user
  local username=""
  while true; do
    username=$(gum input --prompt "Enter username: ")
    [ -n "$username" ] && break
    gum_error "Username cannot be empty."
  done

  useradd -m -G audio,video,input,wheel,sys,log,rfkill,lp,adm -s /bin/bash "$username"
  while true; do
    uspass=$(gum input --password --placeholder="Enter password for $username: ")
    uspass_verify=$(gum input --password --placeholder="Enter password for $username again: ")
    if [ "$uspass" = "$uspass_verify" ]; then
      echo "$username:$uspass" | chpasswd
      break
    else
      gum confirm "Passwords do not match. Try again?" || exit 1
    fi
  done

  pacman -S --noconfirm sudo
  echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel

  pacman -Syu --noconfirm

  # Continue with DE/packages
  setup_desktop_and_packages "$username"

  gum_echo "Base system configuration completed."
  exit 0
}

# ---------- Disk setup ----------
setup_drive() {
  # Select disk
  local DISK_SELECTION
  DISK_SELECTION=$(lsblk -d -o NAME,SIZE,MODEL,TYPE | awk '$4=="disk"{print $0}' | \
    gum choose --header "Select the disk to install on (or Ctrl-C to exit):")
  DISK="/dev/$(echo "$DISK_SELECTION" | awk '{print $1}')"

  if [ -z "$DISK" ]; then
    gum_error "No disk selected."; exit 1
  fi

  gum confirm "WARNING: This will erase all data on $DISK. Continue?" || exit 1

  if grep -q "nvme" <<< "$DISK"; then NVME=1; else NVME=0; fi
  if [ -d /sys/firmware/efi ]; then UEFI=1; else UEFI=0; fi

  # Swap heuristic
  RAM_GB=$(awk '/MemTotal/ {print int($2 / 1024 / 1024)}' /proc/meminfo)
  if [ "$RAM_GB" -lt 15 ]; then
    SWAP_SIZE=4096
    gum_echo "System has ${RAM_GB}GB RAM → creating 4 GiB swap."
  else
    SWAP_SIZE=0
    gum_echo "System has ${RAM_GB}GB RAM → skipping swap."
  fi

  # Partition
  if [ $UEFI -eq 1 ]; then
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    if [ $SWAP_SIZE -gt 0 ]; then
      parted -s "$DISK" mkpart swap linux-swap 513MiB $((513 + SWAP_SIZE))MiB
      parted -s "$DISK" mkpart root btrfs $((513 + SWAP_SIZE))MiB 100%
      SWAP_PART=2; ROOT_PART=3
    else
      parted -s "$DISK" mkpart root btrfs 513MiB 100%
      ROOT_PART=2
    fi
    BOOT_PART=1
  else
    parted -s "$DISK" mklabel msdos
    if [ $SWAP_SIZE -gt 0 ]; then
      parted -s "$DISK" mkpart primary linux-swap 1MiB ${SWAP_SIZE}MiB
      parted -s "$DISK" mkpart primary btrfs ${SWAP_SIZE}MiB 100%
      parted -s "$DISK" set 2 boot on
      SWAP_PART=1; ROOT_PART=2
    else
      parted -s "$DISK" mkpart primary btrfs 1MiB 100%
      parted -s "$DISK" set 1 boot on
      ROOT_PART=1
    fi
  fi

  # Format
  if [ $UEFI -eq 1 ]; then
    if [ $NVME -eq 1 ]; then mkfs.fat -F32 "${DISK}p${BOOT_PART}"; else mkfs.fat -F32 "${DISK}${BOOT_PART}"; fi
  fi
  if [ $SWAP_SIZE -gt 0 ]; then
    if [ $NVME -eq 1 ]; then mkswap "${DISK}p${SWAP_PART}"; else mkswap "${DISK}${SWAP_PART}"; fi
    if [ $NVME -eq 1 ]; then swapon "${DISK}p${SWAP_PART}"; else swapon "${DISK}${SWAP_PART}"; fi
  fi
  if [ $NVME -eq 1 ]; then mkfs.btrfs -f "${DISK}p${ROOT_PART}"; else mkfs.btrfs -f "${DISK}${ROOT_PART}"; fi

  # Mount
  if [ $NVME -eq 1 ]; then mount "${DISK}p${ROOT_PART}" /mnt; else mount "${DISK}${ROOT_PART}" /mnt; fi

  if [ $UEFI -eq 1 ]; then
    mkdir -p /mnt/boot/efi
    if [ $NVME -eq 1 ]; then mount "${DISK}p${BOOT_PART}" /mnt/boot/efi; else mount "${DISK}${BOOT_PART}" /mnt/boot/efi; fi
  else
    mkdir -p /mnt/boot
  fi
}

# ---------- Copy LnOS repo to target ----------
copy_lnos_files() {
  mkdir -p /mnt/root/LnOS
  rsync -a --delete \
    --include 'pacman_packages/**' \
    --include 'paru_packages/**' \
    --include 'scripts/**' \
    --include 'docs/**' \
    --include 'README.md' --include 'LICENSE' --include 'AUTHORS' \
    --include 'SUMMARY.md' --include 'TODO.md' \
    --exclude '*' \
    "$LNOS_REPO"/ /mnt/root/LnOS/
}

# ---------- Install (x86_64) ----------
install_x86_64() {
  setup_drive

    # Install base system (zen kernel may be cool, but after some research about hardening, the linux hardened kernel makes 10x more sense for students and will be the default)
    gum_echo "Installing base system, will take some time (Grab a coffee)"
    pacstrap /mnt base linux-hardened linux-firmware btrfs-progs base-devel git wget networkmanager btrfs-progs openssh git dhcpcd networkmanager vi vim iw wget curl xdg-user-dirs

    gum_echo "Base system install done!"

  gum_echo "Generating fstab (UUID)…"
  genfstab -U /mnt >> /mnt/etc/fstab
  cat /mnt/etc/fstab

  if [ ! -s /mnt/etc/fstab ]; then
    echo "ERROR: fstab not generated!" >&2
    exit 1
  fi

  gum_echo "Applying mkinitcpio.conf and building initramfs…"
  arch-chroot /mnt bash -c 'cat > /etc/mkinitcpio.conf <<EOF
MODULES=(btrfs nvme virtio virtio_pci virtio_blk virtio_scsi virtio_net loop dm_snapshot overlay)
BINARIES=()
FILES=()
HOOKS=(base udev autodetect consolefont modconf block filesystems keyboard fsck)
EOF
'
  arch-chroot /mnt bash -c '
    ls -l /boot/vmlinuz-linux-hardened /boot/initramfs-linux-hardened.img || {
      echo "ERROR: linux-hardened kernel or initramfs missing"; exit 1; }'

  # No archiso hooks installed in the target:
  pacman -Qqs archiso || true

  # Correct kernel preset exists:
  ls /etc/mkinitcpio.d | grep linux-hardened || echo "preset missing (install linux-hardened)"

  # Copy the INSTALLED mkinitcpio config into the target
  # install -Dm644 /usr/share/lnos/mkinitcpio.installed.conf /mnt/etc/mkinitcpio.conf

  # Ensure essentials present
  arch-chroot /mnt pacman -S --noconfirm mkinitcpio linux-firmware btrfs-progs e2fsprogs

  # Build all initramfs images (covers linux-hardened preset)
  if arch-chroot /mnt test -f /boot/vmlinuz-linux-hardened; then
    arch-chroot /mnt mkinitcpio -P
  else
    echo "[LnOS] Skipping mkinitcpio: kernel image not found."
  fi

  # Checks: hardened kernel+initramfs exist in /boot (the real, mounted one)
  arch-chroot /mnt bash -lc 'ls -lh /boot/vmlinuz-linux-hardened /boot/initramfs-linux-hardened.img'

  arch-chroot /mnt bash -lc '
    if lscpu | grep -qi intel; then pacman -S --noconfirm intel-ucode; fi
    if lscpu | grep -qi amd;   then pacman -S --noconfirm amd-ucode;   fi
  '

  gum_echo "Installing and configuring GRUB…"
  if [ $UEFI -eq 1 ]; then
    arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LnOS --recheck
  else
    arch-chroot /mnt pacman -S --noconfirm grub
    arch-chroot /mnt grub-install --target=i386-pc "$DISK"
  fi
  arch-chroot /mnt bash -lc '
    if lscpu | grep -qi intel; then pacman -S --noconfirm intel-ucode; fi
    if lscpu | grep -qi amd;   then pacman -S --noconfirm amd-ucode;   fi
  '
  if [ $UEFI -eq 1 ]; then

  # Ensure GRUB passes a concrete root=UUID
  arch-chroot /mnt bash -lc '
    ROOT_UUID=$(blkid -s UUID -o value "$(findmnt -no SOURCE /)")
    if grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
      sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=UUID=${ROOT_UUID} rw\"|" /etc/default/grub
    else
      echo "GRUB_CMDLINE_LINUX=\"root=UUID=${ROOT_UUID} rw\"" >> /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
  '
  gum_echo "Copying LnOS repo into target system…"
  copy_lnos_files

    # Unmount and reboot
    umount -R /mnt
    for i in {10..1}; do
        gum style --foreground 212 "Installation complete. Rebooting in $i seconds..."
        sleep 1
    done
    reboot
}

# ---------- (Optional) ARM prep — placeholder ----------
prepare_arm() {
  gum_error "ARM/aarch64 flow is WIP. Use the dedicated image builder for now."
  exit 1
}

# ---------- Main ----------
usage() {
  gum style --foreground 255 --border-foreground 130 --border double \
    --width 100 --margin "1 2" --padding "2 4" \
    'Usage: LnOS-installer.sh --target=[x86_64|aarch64] | -h' \
    '[--target]: sets the installer target architecture' \
    '[-h|--help]: show this help'
}

case "${1:-}" in
  --target=x86_64) install_x86_64 ;;
  --target=aarch64) prepare_arm ;;
  -h|--help|"") usage ;;
  *) usage; exit 1 ;;
esac

