#!/usr/bin/env bash
set -euo pipefail

# LnOS Boot Cleaner
# Frees space on small /boot partitions by removing fallback initramfs images
# and disabling future fallback builds.

BACKUP=true   # set to true to move files into /root/boot-backups instead of deleting

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo $0)"; exit 1
  fi
}

msg() { echo -e "\n==> $*"; }

remove_or_backup() {
  local f="$1"
  if [[ -e "$f" ]]; then
    if $BACKUP; then
      mkdir -p /root/boot-backups
      mv -v "$f" /root/boot-backups/
    else
      rm -v "$f"
    fi
  fi
}

patch_preset_default_only() {
  local preset="$1"
  [[ -f "$preset" ]] || return 0
  cp -n "$preset" "$preset.bak" || true
  # Force only 'default' preset to be built (no 'fallback')
  sed -Ei "s/^PRESETS=.*/PRESETS=('default')/" "$preset"
}

need_root

if ! mountpoint -q /boot; then
  echo "/boot is not a mountpoint. Aborting to be safe."; exit 1
fi

msg "Before:"
df -h /boot || true
ls -lh /boot || true

msg "Freeing space by removing fallback initramfs images..."
remove_or_backup /boot/initramfs-linux-fallback.img
remove_or_backup /boot/initramfs-linux-hardened-fallback.img
# Optional: add others if present
# remove_or_backup /boot/initramfs-linux-lts-fallback.img
# remove_or_backup /boot/initramfs-linux-zen-fallback.img

msg "Disabling future fallback builds in mkinitcpio presets..."
patch_preset_default_only /etc/mkinitcpio.d/linux.preset
patch_preset_default_only /etc/mkinitcpio.d/linux-hardened.preset

msg "Rebuilding initramfs (default only)..."
mkinitcpio -P

if command -v grub-mkconfig >/dev/null; then
  msg "Regenerating GRUB config..."
  grub-mkconfig -o /boot/grub/grub.cfg
fi

if command -v paccache >/dev/null; then
  msg "Trimming pacman cache (keeping 1 version)..."
  paccache -rk1 || true
fi

msg "After:"
df -h /boot || true
ls -lh /boot || true

echo -e "\nDone. If you kept BACKUP=true, files are in /root/boot-backups."
