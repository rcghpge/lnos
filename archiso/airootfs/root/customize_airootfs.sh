#!/usr/bin/env bash
# LnOS customize_airootfs.sh — chroot-safe, idempotent, no kernel work here
set -euo pipefail

log() { printf '[LnOS] %s\n' "$*" >&2; }

# --- Utilities ----------------------------------------------------------------
safe_install() {
  # safe_install <mode> <src> <dst>
  local mode="$1" src="$2" dst="$3"
  if [[ -e "$src" && -e "$dst" ]] && [[ "$(realpath -m "$src")" == "$(realpath -m "$dst")" ]]; then
    log "skip: '$src' == '$dst'"; return 0
  fi
  if [[ -f "$src" && -f "$dst" ]] && cmp -s "$src" "$dst"; then
    log "unchanged: $dst"; return 0
  fi
  install -Dm"$mode" "$src" "$dst"
  log "installed: $dst"
}

safe_write() {
  # safe_write <mode> <dst> <<<'content'
  local mode="$1" dst="$2" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$dst" ]] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"; log "unchanged: $dst"; return 0
  fi
  install -Dm"$mode" "$tmp" "$dst"
  rm -f "$tmp"
  log "wrote: $dst"
}

# Set root password to 'lnos' for the live environment
echo 'root:lnos' | chpasswd

# Set timezone to UTC to prevent prompts
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Configure pacman repositories and keyring
echo "Configuring pacman repositories..."
pacman-key --init
pacman-key --populate archlinux

# Make pacman faster & more tolerant
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf

# Force replace the mirrorlist with our reliable one
echo "Replacing mirrorlist with reliable mirrors..."
cat > /etc/pacman.d/mirrorlist << 'EOF'
## LnOS club-approved tier-1 mirrors (core + extra only)
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Server = https://mirrors.lug.mtu.edu/archlinux/$repo/os/$arch
EOF

# ======================================================
# Arch Linux mirrorlist for LnOS ISO
# Using mirrors that support core and extra repositories
# Remove all repos except core & extra from pacman.conf
# ======================================================

# --- Mirrorlist (optional minimal set) ----------------------------------------
safe_write 0644 /etc/pacman.d/mirrorlist <<'EOF'
## LnOS ISO mirrorlist (minimal, reliable set)
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.net/archlinux/$repo/os/$arch
EOF

echo "Locking pacman to core + extra only..."
sed -i '/^\[community\]/,/^Include/d' /etc/pacman.conf
sed -i '/^\[multilib\]/,/^Include/d' /etc/pacman.conf
sed -i '/^\[testing\]/,/^Include/d' /etc/pacman.conf
sed -i '/^\[community-testing\]/,/^Include/d' /etc/pacman.conf
sed -i '/^\[multilib-testing\]/,/^Include/d' /etc/pacman.conf

# Ensure core and extra remain in the config
grep -q '^\[core\]' /etc/pacman.conf || echo -e "\n[core]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
grep -q '^\[extra\]' /etc/pacman.conf || echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

# --- mkinitcpio.conf for LIVE environment (no mkinitcpio invocation) ----------
# Keep archiso hooks; mkarchiso will use this when it builds the image.
safe_write 0644 /etc/mkinitcpio.conf <<'EOF'
MODULES=(loop dm_snapshot overlay squashfs virtio virtio_blk virtio_pci virtio_scsi virtio_net)
BINARIES=()
FILES=()
HOOKS=(base udev archiso archiso_loop_mnt block filesystems keyboard fsck)
COMPRESSION="zstd"
EOF

# Ensure we don't ship any mkinitcpio pacman hook that would auto-run mkinitcpio
rm -f /etc/pacman.d/hooks/90-mkinitcpio.hook 2>/dev/null || true

# --- System services (enable without installing packages here) ----------------
mkdir -p /etc/systemd/system/multi-user.target.wants
for svc in NetworkManager.service dhcpcd.service systemd-resolved.service; do
  ln -sf "/usr/lib/systemd/system/$svc" "/etc/systemd/system/multi-user.target.wants/$svc"
done

# Symlink fallback
mkdir -p /etc/systemd/system/multi-user.target.wants
for svc in NetworkManager.service dhcpcd.service systemd-resolved.service; do
  ln -sf "/usr/lib/systemd/system/$svc" "/etc/systemd/system/multi-user.target.wants/$svc"
done

# Autologin on tty1
mkdir -p /etc/systemd/system/getty@tty1.service.d
safe_write 0644 /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \u' --noclear --autologin root %I $TERM
EOF

# Autostart service
safe_write 0644 /etc/systemd/system/lnos-autostart.service <<'EOF'
[Unit]
Description=LnOS Auto-start Installer
After=getty@tty1.service
ConditionPathExists=/usr/local/bin/lnos-autostart.sh

[Service]
Type=oneshot
TTYPath=/dev/tty1
ExecStart=/usr/local/bin/lnos-autostart.sh

[Install]
WantedBy=multi-user.target
EOF
ln -sf /usr/lib/systemd/system/lnos-autostart.service \
       /etc/systemd/system/multi-user.target.wants/lnos-autostart.service || true

# --- Shell helpers -----------------------------------------
for bin in /usr/local/bin/lnos-shell.sh /usr/local/bin/LnOS-installer.sh /usr/local/bin/lnos-autostart.sh; do
  [[ -f "$bin" ]] && chmod 0755 "$bin" && log "chmod +x $bin"
done
if [[ -x /usr/local/bin/lnos-shell.sh ]]; then
  grep -qxF '/usr/local/bin/lnos-shell.sh' /etc/shells || echo '/usr/local/bin/lnos-shell.sh' >> /etc/shells
fi

# Optional live root password and timezone
echo 'root:lnos' | chpasswd || true
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

log "Customize complete."

