#!/usr/bin/env bash
# LnOS customize_airootfs.sh — chroot-safe, idempotent, live-ISO builds - building for robustness.
set -euo pipefail

log() { printf '[LnOS] %s\n' "$*" >&2; }

# --- helpers ------------------------------------------------------------------
safe_write() { # safe_write <mode> <dst> <<<'content'
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

symlink_enable() { # symlink_enable <unit>
  local unit="${1:-}"
  [[ -n "$unit" ]] || { log "enabled: (no unit given; skipped)"; return 0; }
  mkdir -p /etc/systemd/system/multi-user.target.wants
  ln -sf "/usr/lib/systemd/system/$unit" \
         "/etc/systemd/system/multi-user.target.wants/$unit"
  log "enabled: $unit"
}

symlink_disable() { # symlink_disable <unit>
  local unit="${1:-}"
  [[ -n "$unit" ]] || { log "disabled: (no unit given; skipped)"; return 0; }
  rm -f "/etc/systemd/system/multi-user.target.wants/$unit" 2>/dev/null || true
  log "disabled: $unit"
}

# --- minimal logging ----------------------------------------------------------
echo "LnOS customize script starting at $(date)" > /tmp/customize-debug.log

# --- root pw & timezone (live only) ------------------------------------------
echo 'root:lnos' | chpasswd || true
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# --- pacman keyring & speed ---------------------------------------------------
log "Configuring pacman keyring…"
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux >/dev/null 2>&1 || true

log "Tuning pacman ParallelDownloads…"
if grep -q '^\s*#\s*ParallelDownloads' /etc/pacman.conf; then
  sed -i 's/^\s*#\s*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
elif ! grep -q '^\s*ParallelDownloads' /etc/pacman.conf; then
  printf '\nParallelDownloads = 10\n' >> /etc/pacman.conf
fi

# --- LnOS os-release (branding + pacman protection) ---------------------------
safe_write 0644 /usr/lib/os-release <<'EOF'
NAME="LnOS"
PRETTY_NAME="LnOS (Arch Linux)"
ID=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/uta-lug-nuts/LnOS"
DOCUMENTATION_URL="https://github.com/uta-lug-nuts/LnOS"
SUPPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
BUG_REPORT_URL="https://github.com/uta-lug-nuts/LnOS/issues"
LOGO=archlinux-logo
EOF

rm -f /etc/os-release 2>/dev/null || true
ln -s /usr/lib/os-release /etc/os-release

# Block Arch’s filesystem package from overwriting it
if ! grep -Eq '^\s*NoExtract\s*=.*\busr/lib/os-release\b' /etc/pacman.conf; then
  printf '\nNoExtract = usr/lib/os-release\n' >> /etc/pacman.conf
  log "pacman: added NoExtract for usr/lib/os-release"
fi

# Safety net: restore our branding if filesystem ever overwrites it
mkdir -p /etc/pacman.d/hooks
safe_write 0644 /etc/pacman.d/hooks/99-lnos-os-release.hook <<'EOF'
[Trigger]
Operation = Upgrade
Operation = Install
Type = Package
Target = filesystem

[Action]
Description=Reassert LnOS os-release branding
When=PostTransaction
Exec=/usr/bin/bash -c 'if [[ -f /usr/lib/os-release.lnos ]]; then cp -f /usr/lib/os-release.lnos /usr/lib/os-release; fi'
EOF
cp -f /usr/lib/os-release /usr/lib/os-release.lnos || true

# --- mirrorlist (favor low-latency; override with LN_MIRRORS) ----------------
# If you export LN_MIRRORS=$'https://a/$repo/os/$arch\nhttps://b/$repo/os/$arch'
# it will replace the default list.
if [[ -n "${LN_MIRRORS:-}" ]]; then
  MIRRORS="$LN_MIRRORS"
else
  # Kernel.org first; others generally reliable (avoid geo endpoints).
  read -r -d '' MIRRORS <<'EOF' || true
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://arch.mirror.constant.com/$repo/os/$arch
Server = https://mirrors.lug.mtu.edu/archlinux/$repo/os/$arch
Server = https://mirror.umd.edu/archlinux/$repo/os/$arch
EOF
fi
safe_write 0644 /etc/pacman.d/mirrorlist <<<"## LnOS ISO mirrorlist
$MIRRORS
"

# --- lock repos to core+extra (safer than sed ranges) -------------------------
log "Locking pacman to [core] + [extra] only…"
awk '
  BEGIN{skip=0}
  /^\[community(-testing)?\]$|^\[multilib(-testing)?\]$|^\[testing\]$/ {skip=1}
  skip==1 && /^Include[[:space:]]*=/{skip=0; next}
  skip==1 {next}
  {print}
' /etc/pacman.conf > /etc/pacman.conf.lnos && mv /etc/pacman.conf.lnos /etc/pacman.conf

grep -q '^\[core\]'  /etc/pacman.conf || printf '\n[core]\nInclude = /etc/pacman.d/mirrorlist\n'  >> /etc/pacman.conf
grep -q '^\[extra\]' /etc/pacman.conf || printf '\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf

# Optional network touch during build is flaky; keep off by default.
if [[ "${LN_NETCHECK:-0}" == "1" ]]; then
  log "Refreshing sync DBs (test mode)…"
  pacman -Syy --noconfirm || log "WARN: pacman -Syy failed (will retry at runtime)"
fi

# --- mkinitcpio (live only) ---------------------------------------------------
safe_write 0644 /etc/mkinitcpio.conf <<'EOF'
MODULES=(loop dm_snapshot overlay squashfs virtio virtio_blk virtio_pci virtio_scsi virtio_net)
BINARIES=()
FILES=()
HOOKS=(base udev archiso archiso_loop_mnt block filesystems keyboard fsck)
COMPRESSION="zstd"
EOF

# Avoid accidental rebuilds in the live env
rm -f /etc/pacman.d/hooks/90-mkinitcpio.hook 2>/dev/null || true
rm -f /etc/pacman.d/hooks/90-mkinitcpio-install.hook 2>/dev/null || true

# --- networking: NetworkManager only + resolv.conf under NM -------------------
symlink_enable "NetworkManager.service"
symlink_disable "dhcpcd.service"
symlink_disable "systemd-resolved.service"

# Prefer /run/NetworkManager/resolv.conf, but archiso may bind-mount /etc/resolv.conf
# If it's busy, defer to a tmpfiles.d rule that fixes it at boot.
if rm -f /etc/resolv.conf 2>/dev/null && ln -s /run/NetworkManager/resolv.conf /etc/resolv.conf 2>/dev/null; then
  log "resolv.conf -> /run/NetworkManager/resolv.conf"
else
  log "INFO: /etc/resolv.conf busy; deferring relink via tmpfiles.d"
  mkdir -p /usr/lib/tmpfiles.d
  # L+ means "create symlink at boot if missing/wrong"
  safe_write 0644 /usr/lib/tmpfiles.d/lnos-resolv.conf.conf <<'EOF'
L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf
EOF
fi

# --- tty1 autologin → lnos-autostart.sh --------------------------------------
mkdir -p /etc/systemd/system/getty@tty1.service.d
safe_write 0644 /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

# Autostart unit (we enable it below via symlink)
safe_write 0644 /etc/systemd/system/lnos-autostart.service <<'EOF'
[Unit]
Description=LnOS Auto-start Installer
After=getty@tty1.service
ConditionPathExists=/usr/local/bin/lnos-autostart.sh

[Service]
Type=oneshot
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=tty
StandardError=tty
ExecStart=/usr/local/bin/lnos-autostart.sh

[Install]
WantedBy=multi-user.target
EOF
ln -sf /etc/systemd/system/lnos-autostart.service \
       /etc/systemd/system/multi-user.target.wants/lnos-autostart.service

# --- LnOS shell & installer (guarded) -----------------------------------------
if [[ -x /usr/local/bin/lnos-shell.sh ]]; then
  grep -qxF '/usr/local/bin/lnos-shell.sh' /etc/shells || echo '/usr/local/bin/lnos-shell.sh' >> /etc/shells
  chsh -s /usr/local/bin/lnos-shell.sh root || true
else
  log "WARN: /usr/local/bin/lnos-shell.sh not found; skipping chsh"
fi

mkdir -p /root/LnOS/scripts
if [[ -f /usr/local/bin/LnOS-installer.sh ]]; then
  install -Dm755 /usr/local/bin/LnOS-installer.sh /root/LnOS/scripts/LnOS-installer.sh
else
  log "WARN: LnOS-installer.sh not found under /usr/local/bin"
fi

if [[ -d /usr/share/lnos/pacman_packages ]]; then
  cp -r /usr/share/lnos/pacman_packages /root/LnOS/scripts/
else
  mkdir -p /root/LnOS/scripts/pacman_packages
  log "NOTE: created empty pacman_packages"
fi

# --- done ---------------------------------------------------------------------
echo "Customize script completed at $(date)" > /tmp/customize-completed
echo "Customize script completed successfully" >> /tmp/customize-debug.log
log "Customize complete."

# Example: override mirrors during build if needed:
# export LN_MIRRORS=$'Server = https://mirror.math.princeton.edu/pub/archlinux/$repo/os/$arch\nServer = https://archlinux.mirrors.linux.ro/$repo/os/$arch'
