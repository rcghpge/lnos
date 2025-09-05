#!/usr/bin/env bash
# LnOS-installer.sh — end-to-end installer for LnOS (Arch-based)
# - Manual (interactive) and Auto (non-interactive) modes
# - TTY-aware, robust gum UX (safe spinners/inputs/choosers)
# - Works from live ISO (/root/LnOS) or a cloned repo
# - Clean logging, strict mode, clear errors with line numbers
# - Long commands are wrapped to avoid quoting/pipefail issues

set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "[ERR] line $LINENO: ${BASH_COMMAND:-?}" >&2' ERR

# ---------------------------
# Path resolution (ISO or cloned repo)
# ---------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PAC_DIR_ISO="$REPO_DIR/pacman_packages"
PAC_DIR_SCRIPTS="$SCRIPT_DIR/pacman_packages"
PARU_DIR_ISO="$REPO_DIR/paru_packages"
PARU_DIR_SCRIPTS="$SCRIPT_DIR/paru_packages"

# ---------------------------
# Mode & CLI parsing
# ---------------------------
LNOS_MODE="${LNOS_MODE:-manual}"   # manual | auto
LNOS_CONFIRM="${LNOS_CONFIRM:-1}"  # 1=ask, 0=skip confirms
LNOS_DISK="${LNOS_DISK:-}"         # preselect disk, e.g. /dev/vda

_usage_modes() {
  cat <<'EOF'
LnOS Installer (modes)

Flags:
  --auto            Non-interactive mode (no prompts). Disables gum on noisy steps.
  --manual          Interactive mode with gum prompts (default).
  --yes             Skip confirmation prompts for destructive actions.
  --disk /dev/XYZ   Preselect install disk.

Env (optional):
  LNOS_MODE=auto|manual
  LNOS_CONFIRM=0|1
  LNOS_DISK=/dev/XYZ
  LNOS_AUTO_DISK=1          # if one candidate, allow auto-pick in manual mode
  LNOS_GUM=0                # force-disable gum for any run_step
  LNOS_INSTALL_LOG=/path    # default: /var/log/lnos-install.log
EOF
}

_parse_mode_flags() {
  local keep=()
  while (( $# )); do
    case "$1" in
      --auto)   LNOS_MODE=auto ;;
      --manual) LNOS_MODE=manual ;;
      --yes)    LNOS_CONFIRM=0 ;;
      --disk)   shift; LNOS_DISK="${1:-}"; [[ -n "$LNOS_DISK" ]] || { echo "[ERR] --disk needs a device" >&2; exit 2; } ;;
      -h|--help) _usage_modes; exit 0 ;;
      *) keep+=("$1") ;;
    esac
    shift || true
  done
  printf '%s\0' "${keep[@]}"
}

# ---------------------------
# Small helpers
# ---------------------------
need(){ command -v "$1" >/dev/null 2>&1; }
log(){ printf '[..] %s\n' "$*"; }
ok(){  printf '[OK] %s\n' "$*"; }
die(){ echo "[ERR] $*" >&2; exit 1; }

# Detect TTY for nicer UX; many gum widgets need a real TTY
HAS_TTY=0
if [[ -t 0 && -t 1 && -t 2 ]]; then HAS_TTY=1; fi

# ---------------------------
# Gum wrappers (TTY-aware)
# ---------------------------
_gum_ok(){ need gum && [[ $HAS_TTY -eq 1 ]]; }
_gum_spin_show_output_ok(){ _gum_ok && gum spin --help 2>&1 | grep -q -- '--show-output'; }

gecho(){ if _gum_ok; then gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 212 "$@"; else echo "$*"; fi; }

gerror(){ if _gum_ok; then gum style --border double --margin "1 2" --padding "1 3" --border-foreground 1 "$@"; else echo "[ERROR] $*"; fi; }

gok(){ if _gum_ok; then gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 82 "$@"; else echo "[OK] $*"; fi; }

choose_one(){
  local label="$1"; shift
  local -a items=("$@")
  (( ${#items[@]} )) || die "[$label] nothing to choose from"
  if (( ${#items[@]} == 1 )); then printf '%s\n' "${items[0]}"; return 0; fi
  if _gum_ok; then
    printf '%s\n' "${items[@]}" | gum choose
  else
    printf '%s\n' "${items[0]}"
  fi
}

# confirm/input wrappers
confirm(){
  local msg="${1:-Continue?}"
  if (( LNOS_CONFIRM == 0 )) || [[ "$LNOS_MODE" = auto ]]; then return 0; fi
  if _gum_ok; then gum confirm "$msg"; else read -rp "$msg [y/N] " yn; [[ "$yn" =~ ^[Yy]$ ]]; fi
}

ginput(){ if _gum_ok; then gum input "$@"; else printf '\n'; fi; }

# ---------------------------------------
# Spinner/run wrapper — robust + fast path
# ---------------------------------------
_wrap_cmd_to_script() {
  local _tmp="${TMPDIR:-/tmp}/lnos-step.$$.XXXXXX"
  _tmp="$(mktemp "$_tmp")"
  {
    printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n'
    printf 'exec'
    local a; for a in "$@"; do printf ' %q' "$a"; done
    printf '\n'
  } >"$_tmp"
  chmod +x "$_tmp"; printf '%s' "$_tmp"
}

run_step() {
  local title="$1"; shift
  local _script _log rc
  _script="$(_wrap_cmd_to_script "$@")"
  _log="${LNOS_INSTALL_LOG:-/var/log/lnos-install.log}"

  mkdir -p "$(dirname "$_log")" 2>/dev/null || true
  printf '\n==> [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$title" | tee -a "$_log"

  # Auto mode defaults to disabling gum for heavy output unless user overrode
  local _gum_env="${LNOS_GUM:-}"
  if [[ "$LNOS_MODE" = auto && -z "${_gum_env}" ]]; then
    LNOS_GUM=0
  fi

  if [[ "${LNOS_GUM:-1}" = "0" ]]; then
    set -o pipefail
    "$_script" 2>&1 | tee -a "$_log"; rc=${PIPESTATUS[0]}
    rm -f "$_script" || true
    return "$rc"
  fi

  if _gum_spin_show_output_ok; then
    gum spin --spinner line --title "$title" --show-output -- \
      bash -c '
        set -o pipefail
        if command -v stdbuf >/dev/null 2>&1; then
          stdbuf -oL -eL "$1" 2>&1 | tee -a "$2"
        else
          "$1" 2>&1 | tee -a "$2"
        fi
        exit ${PIPESTATUS[0]}
      ' _ "$_script" "$_log"
    rc=$?
  elif _gum_ok; then
    gum spin --spinner line --title "$title" -- sleep 0.1
    set -o pipefail
    "$_script" 2>&1 | tee -a "$_log"; rc=${PIPESTATUS[0]}
  else
    echo "==> $title" | tee -a "$_log"
    set -o pipefail
    "$_script" 2>&1 | tee -a "$_log"; rc=${PIPESTATUS[0]}
  fi

  rm -f "$_script" || true
  return "$rc"
}

# ---------------------------
# Network helpers
# ---------------------------
have_net(){ ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 archlinux.org >/dev/null 2>&1; }
ensure_net(){
  if have_net; then return 0; fi
  gerror "No network connectivity detected."
  gecho  "Open NetworkManager TUI to connect?"
  if [[ "$LNOS_MODE" = manual ]] && confirm "Open nmtui now?"; then command -v nmtui >/dev/null 2>&1 && nmtui || true; fi
  have_net || die "Still offline. Aborting."
}

# ---------------------------
# Package list resolver (ISO vs scripts/)
# ---------------------------
resolve_pkg_list(){
  local f="$1"
  if   [[ -f "$PAC_DIR_ISO/$f" ]];      then REPLY="$PAC_DIR_ISO/$f"; return 0
  elif [[ -f "$PAC_DIR_SCRIPTS/$f" ]];  then REPLY="$PAC_DIR_SCRIPTS/$f"; return 0
  elif [[ -f "$PARU_DIR_ISO/$f" ]];     then REPLY="$PARU_DIR_ISO/$f"; return 0
  elif [[ -f "$PARU_DIR_SCRIPTS/$f" ]]; then REPLY="$PARU_DIR_SCRIPTS/$f"; return 0
  fi
  return 1
}

# ---------------------------
# Live-env sanity & tools
# ---------------------------
if ! need pacman-key; then die "This must be run from an Arch live environment."; fi
sudo pacman-key --init

if ! need gum; then
  echo "Installing gum..."
  pacman -Sy --needed --noconfirm gum || true
fi

if ! need nmtui; then
  echo "Installing NetworkManager (live env)..."
  pacman -Sy --needed --noconfirm networkmanager || true
  systemctl enable --now NetworkManager.service || true
fi

if [[ "$LNOS_MODE" = manual ]]; then
  gecho "Open NetworkManager TUI to connect to the internet?"
  if confirm "Open nmtui now?"; then command -v nmtui >/dev/null 2>&1 && nmtui || true; fi
fi

# ---------------------------
# Disk discovery & selection (manual/auto aware)
# ---------------------------
_live_boot_device() {
  local src dev
  src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  [[ -z "$src" ]] && src="$(findmnt -n -o SOURCE /run/archiso 2>/dev/null || true)"
  [[ -n "$src" ]] && dev="$(lsblk -no PKNAME "$src" 2>/dev/null || true)"
  [[ -n "$dev" ]] && printf '/dev/%s\n' "$dev"
}

_list_installable_disks() {
  lsblk -ndo NAME,TYPE,RO | awk '$2=="disk" && $3=="0"{print "/dev/"$1}' | \
    grep -Ev '^/dev/(loop|ram|zram|sr|md|fd)' || true
}

choose_disk() {
  local live dev choices=() pick
  live="$(_live_boot_device || true)"

  while IFS= read -r dev; do
    [[ -n "$live" && "$dev" = "$live" ]] && continue
    choices+=("$dev")
  done < <(_list_installable_disks)

  (( ${#choices[@]} )) || { echo "[ERR] no installable disks found" >&2; return 1; }

  # Preselect override
  if [[ -n "$LNOS_DISK" ]]; then
    if printf '%s\n' "${choices[@]}" | grep -qx -- "$LNOS_DISK"; then
      printf '%s\n' "$LNOS_DISK"; return 0
    else
      echo "[ERR] $LNOS_DISK is not an installable disk" >&2; return 1
    fi
  fi

  # Auto mode: deterministic pick (first), or single candidate
  if [[ "$LNOS_MODE" = auto ]]; then
    printf '%s\n' "${choices[0]}"; return 0
  fi

  # Manual: prompt (gum if available)
  if _gum_ok; then
    local lines=()
    while IFS= read -r line; do lines+=("$line"); done < <(
      lsblk -ndo NAME,SIZE,MODEL | awk '$0!~/^(loop|ram|zram|sr)/{printf "/dev/%s  (%s)  %s\n",$1,$2,substr($0,index($0,$3))}'
    )
    pick="$(printf '%s\n' "${lines[@]}" | gum choose --header "Select target disk (WILL ERASE)")" || return 1
    printf '%s\n' "${pick%% *}"
  else
    printf 'Available disks:\n'; printf '  %s\n' "${choices[@]}"
    read -rp "Disk to install to: " pick; printf '%s\n' "$pick"
  fi
}

# ---------------------------
# Desktop + package selection (runs in chroot)
# ---------------------------
setup_desktop_and_packages(){
  local username="$1"
  gecho "Welcome to LnOS desktop and package setup."

  run_step "Installing tools (env)" \
    pacman -S --needed --noconfirm base-devel git wget networkmanager btrfs-progs openssh dhcpcd vi vim iw curl xdg-user-dirs || true

  local -a DESKTOPS=(
    "Gnome(Good for beginners, similar to Mac)"
    "KDE(Good for beginners, similar to Windows)"
    "Hyprland(Tiling WM, basic dotfiles but requires more DIY)"
    "DWM(Similar to Hyprland)"
    "TTY (No install required)"
  )
  local DE_CHOICE
  if [[ "$LNOS_MODE" = manual ]]; then
    DE_CHOICE="$(choose_one "desktop environments" "${DESKTOPS[@]}")"
  else
    DE_CHOICE="TTY (No install required)"  # Auto mode: skip DE by default
  fi

  case "$DE_CHOICE" in
    "TTY (No install required)") gecho "TTY selected — skipping desktop packages." ;;
    "Gnome(Good for beginners, similar to Mac)")
      run_step "Installing GNOME base" \
        pacman -S --needed --noconfirm gnome gnome-tweaks gnome-shell-extensions xdg-user-dirs-gtk
      systemctl enable gdm || true ;;
    "KDE(Good for beginners, similar to Windows)")
      run_step "Installing KDE Plasma base" \
        pacman -S --needed --noconfirm plasma kde-applications sddm
      systemctl enable sddm || true ;;
    "Hyprland(Tiling WM, basic dotfiles but requires more DIY)")
      run_step "Installing Hyprland base" \
        pacman -S --needed --noconfirm wayland hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra kitty networkmanager
      gecho "(Optional) Downloading JaKooLit's Hyprland auto-install"
      run_step "Fetching Hyprland helper" \
        bash -c "wget -q https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh -O /home/$username/auto-install.sh && chown $username:$username /home/$username/auto-install.sh" ;;
    "DWM(Similar to Hyprland)") gecho "DWM flow is WIP. Skipping." ;;
  esac

  local THEME="CSE"
  if [[ "$LNOS_MODE" = manual ]]; then
    THEME="$(choose_one "installation profile" CSE Custom)"
  fi

  case "$THEME" in
    CSE)
      if resolve_pkg_list "CSE_packages.txt"; then
        mapfile -t PACMAN_PKGS < <(grep -vE '^\s*#' "$REPLY" | xargs -n1 echo)
        if (( ${#PACMAN_PKGS[@]} )); then
          run_step "Installing pacman packages (CSE)" \
            pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
        fi
      fi
      if [[ "$LNOS_MODE" = manual ]]; then
        gecho "AUR packages are community-maintained. Continue?"
        if confirm "Install AUR packages?"; then
          if ! need paru; then
            run_step "Installing paru (AUR helper)" bash -c '
              set -e
              git clone https://aur.archlinux.org/paru.git /tmp/paru
              cd /tmp/paru
              makepkg -si --noconfirm
            '
            rm -rf /tmp/paru || true
          fi
          if resolve_pkg_list "paru_packages.txt"; then
            mapfile -t PARU_PKGS < <(grep -vE '^\s*#' "$REPLY" | xargs -n1 echo)
            if (( ${#PARU_PKGS[@]} )); then
              run_step "Installing AUR packages (CSE)" paru -S --noconfirm "${PARU_PKGS[@]}"
            fi
          fi
        fi
      fi
      ;;
    Custom)
      if [[ "$LNOS_MODE" = manual ]]; then
        local line
        read -r line <<<"$(ginput --header "Enter pacman packages (space-separated):")"
        local -a PACMAN_PKGS=()
        read -r -a PACMAN_PKGS <<<"$line"
        if (( ${#PACMAN_PKGS[@]} )); then
          run_step "Installing pacman packages (custom)" \
            pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
        fi

        gecho "Install AUR packages too?"
        if confirm "Install AUR packages?"; then
          if ! need paru; then
            run_step "Installing paru (AUR helper)" bash -c '
              set -e
              git clone https://aur.archlinux.org/paru.git /tmp/paru
              cd /tmp/paru
              makepkg -si --noconfirm
            '
            rm -rf /tmp/paru || true
          fi
          read -r line <<<"$(ginput --header "Enter AUR packages (space-separated):")"
          local -a PARU_PKGS=()
          read -r -a PARU_PKGS <<<"$line"
          if (( ${#PARU_PKGS[@]} )); then
            run_step "Installing AUR packages (custom)" paru -S --noconfirm "${PARU_PKGS[@]}"
          fi
        fi
      fi
      ;;
  esac

  gok "LnOS desktop/package setup completed."
}

# ---------------------------
# Copy LnOS repo into target
# ---------------------------
copy_lnos_files(){
  local SRC="$REPO_DIR"
  [[ -d "$SRC" ]] || die "LnOS repo not found at $SRC"
  mkdir -p /mnt/root/LnOS
  cp -r "$SRC/scripts/pacman_packages" /mnt/root/LnOS/ 2>/dev/null || true
  cp -r "$SRC/paru_packages"        /mnt/root/LnOS/ 2>/dev/null || true
  cp    "$SRC/scripts/LnOS-auto-setup.sh" /mnt/root/LnOS/ 2>/dev/null || true
  cp -r "$SRC/docs" /mnt/root/LnOS/ 2>/dev/null || true
  cp "$SRC/README.md" "$SRC/LICENSE" "$SRC/AUTHORS" "$SRC/SUMMARY.md" "$SRC/TODO.md" /mnt/root/LnOS/ 2>/dev/null || true
}

# ---------------------------
# System configuration (runs *inside* chroot)
# ---------------------------
configure_system(){
  pacman -Sy --needed --noconfirm gum || true

  # Time/locale
  ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
  hwclock --systohc
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf

  # Hostname/hosts
  echo "LnOS" > /etc/hostname
  printf "127.0.0.1\tlocalhost\n::1\tlocalhost\n" > /etc/hosts

  # DNS
  echo "nameserver 1.1.1.1" > /etc/resolv.conf

  # Root password (auto: set temporary; manual: prompt)
  if [[ "$LNOS_MODE" = manual ]]; then
    local rtpass rtpass_verify
    while true; do
      rtpass="$(ginput --password --placeholder="Enter root password:")"
      rtpass_verify="$(ginput --password --placeholder="Enter root password again:")"
      if [[ "$rtpass" == "$rtpass_verify" && -n "$rtpass" ]]; then echo "root:$rtpass" | chpasswd; break; fi
      confirm "Passwords do not match. Try again?" || exit 1
    done
  else
    echo "root:lnos" | chpasswd
  fi

  # Create user
  local username
  if [[ "$LNOS_MODE" = manual ]]; then
    while true; do
      username="$(ginput --header "Enter username:")"
      [[ -n "$username" ]] && break
      gerror "Username cannot be empty."
    done
  else
    username="lnos"
  fi
  useradd -m -G audio,video,input,wheel,sys,log,rfkill,lp,adm -s /bin/bash "$username" || true

  local uspass uspass_verify
  if [[ "$LNOS_MODE" = manual ]]; then
    while true; do
      uspass="$(ginput --password --placeholder="Enter password for $username:")"
      uspass_verify="$(ginput --password --placeholder="Enter password for $username again:")"
      if [[ "$uspass" == "$uspass_verify" && -n "$uspass" ]]; then echo "$username:$uspass" | chpasswd; break; fi
      confirm "Passwords do not match. Try again?" || exit 1
    done
  else
    echo "$username:lnos" | chpasswd
  fi

  # sudoers
  pacman -S --needed --noconfirm sudo
  echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel

  # Enable basic services
  systemctl enable NetworkManager || true
  systemctl enable dhcpcd || true

  # Update
  pacman -Syu --noconfirm || true

  # Desktop + packages
  setup_desktop_and_packages "$username"

  gok "Base system configured."
}

# ---------------------------
# x86_64 install (from Arch live ISO)
# ---------------------------
install_x86_64(){
  ensure_net

  # Disk selection (manual or auto)
  local DISK
  DISK="$(choose_disk)" || { echo "[ERR] disk selection failed"; exit 1; }
  gecho "Selected disk: $DISK"

  confirm "WARNING: This will erase all data on $DISK. Continue?" || exit 1

  # Detect UEFI & NVMe
  local UEFI=0 NVME=0
  [[ -d /sys/firmware/efi ]] && UEFI=1 || UEFI=0
  [[ "$DISK" =~ nvme ]] && NVME=1 || NVME=0

  # Swap heuristic
  local RAM_GB SWAP_SIZE=0
  RAM_GB="$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)"
  if (( RAM_GB < 15 )); then SWAP_SIZE=4096; gecho "RAM ${RAM_GB}GiB -> creating 4GiB swap."; else gecho "RAM ${RAM_GB}GiB -> no swap."; fi

  # Partitioning
  run_step "Partition disk" bash -c '
    set -Eeuo pipefail
    DISK="$1"; UEFI="$2"; SWAP_SIZE="$3"
    if (( UEFI )); then
      parted -s "$DISK" mklabel gpt
      parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
      parted -s "$DISK" set 1 esp on
      if (( SWAP_SIZE > 0 )); then
        parted -s "$DISK" mkpart swap linux-swap 513MiB $((513 + SWAP_SIZE))MiB
        parted -s "$DISK" mkpart root btrfs $((513 + SWAP_SIZE))MiB 100%%
      else
        parted -s "$DISK" mkpart root btrfs 513MiB 100%%
      fi
    else
      parted -s "$DISK" mklabel msdos
      if (( SWAP_SIZE > 0 )); then
        parted -s "$DISK" mkpart primary linux-swap 1MiB ${SWAP_SIZE}MiB
        parted -s "$DISK" mkpart primary btrfs ${SWAP_SIZE}MiB 100%%
        parted -s "$DISK" set 2 boot on
      else
        parted -s "$DISK" mkpart primary btrfs 1MiB 100%%
        parted -s "$DISK" set 1 boot on
      fi
    fi
  ' _ "$DISK" "$UEFI" "$SWAP_SIZE"

  # Figure partitions
  local BOOT PART_ROOT PART_SWAP
  if (( NVME )); then
    BOOT="${DISK}p1"; PART_SWAP="${DISK}p2"; PART_ROOT="${DISK}p3"
  else
    BOOT="${DISK}1"; PART_SWAP="${DISK}2"; PART_ROOT="${DISK}3"
  fi
  if (( SWAP_SIZE == 0 )); then
    PART_SWAP=""
    if (( NVME )); then PART_ROOT="${DISK}p2"; else PART_ROOT="${DISK}2"; fi
  fi

  # Make filesystems
  if (( UEFI )); then
    run_step "Make ESP" mkfs.fat -F32 "$BOOT"
  fi
  if [[ -n "$PART_SWAP" ]]; then
    run_step "Make swap" mkswap "$PART_SWAP"
    run_step "Enable swap" swapon "$PART_SWAP"
  fi
  run_step "Make root FS (btrfs)" mkfs.btrfs -f "$PART_ROOT"

  # Mount target
  run_step "Mount root" mount "$PART_ROOT" /mnt
  if (( UEFI )); then
    run_step "Mount ESP" bash -c 'mkdir -p /mnt/boot/efi && mount "$0" /mnt/boot/efi' "$BOOT"
  else
    run_step "Prepare /boot" mkdir -p /mnt/boot
  fi

  ensure_net

  # Keyring (fast)
  run_step "Sync archlinux-keyring" pacman -Sy --needed --noconfirm archlinux-keyring

  # Base system (noisy → no gum)
  LNOS_GUM=0 run_step "Pacstrap base system" \
    pacstrap -K /mnt base linux linux-firmware btrfs-progs \
      base-devel git wget networkmanager openssh dhcpcd vi vim iw curl xdg-user-dirs

  # Preserve console font if present
  [[ -f /etc/vconsole.conf ]] && install -Dm644 /etc/vconsole.conf /mnt/etc/vconsole.conf

  # Generate fstab
  run_step "Generate fstab" bash -c 'genfstab -U /mnt >> /mnt/etc/fstab'

  # Copy LnOS support files
  run_step "Copy LnOS files" bash -c 'copy_lnos_files'

  # Prepare chroot payload
  local _payload
  _payload="$(mktemp -t lnos-chroot-XXXXXX.sh)"
  {
    # Export mode flags into chroot env
    printf 'export LNOS_MODE=%q LNOS_CONFIRM=%q\n' "$LNOS_MODE" "$LNOS_CONFIRM"
    # Functions used in chroot
    declare -f need log ok die gecho gerror gok confirm ginput choose_one _gum_ok _gum_spin_show_output_ok run_step resolve_pkg_list setup_desktop_and_packages configure_system
    printf 'configure_system\n'
  } >"$_payload"
  chmod +x "$_payload"
  install -Dm755 "$_payload" "/mnt/$(basename "$_payload")"

  # Configure inside chroot (noisy)
  LNOS_GUM=0 run_step "Configure system in chroot" \
    arch-chroot /mnt /bin/bash "/$(basename "$_payload")"
  rm -f "$_payload" || true

  # Bootloader
  if (( UEFI )); then
    run_step "Install GRUB (UEFI pkgs)" arch-chroot /mnt pacman -S --needed --noconfirm grub efibootmgr
    # Note: we mounted ESP at /boot/efi above
    LNOS_GUM=0 run_step "grub-install (UEFI)" \
      arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
  else
    run_step "Install GRUB (BIOS pkgs)" arch-chroot /mnt pacman -S --needed --noconfirm grub
    LNOS_GUM=0 run_step "grub-install (BIOS)" \
      arch-chroot /mnt grub-install --target=i386-pc "$DISK"
  fi

  LNOS_GUM=0 run_step "Generate grub.cfg" \
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

  # Done
  run_step "Sync to disk" sync
  if [[ "$LNOS_MODE" = manual ]]; then
    gecho "Installation complete."
    confirm "Reboot now?" && { umount -R /mnt || true; reboot; }
  else
    umount -R /mnt || true
    reboot
  fi
}