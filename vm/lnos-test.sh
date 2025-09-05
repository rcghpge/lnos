# This is for preliminary tests on native-Arch Linux
#!/usr/bin/env bash
# LnOS VM runner — KVM/UEFI/virtio with auto-setup for Arch/LnOS
# - Installs qemu + OVMF + gum if missing (needs sudo)
# - Creates vm/ with qcow2 disk + OVMF_VARS copy
# - Works from repo root OR vm/
# Env knobs: RAM, CPUS, DISK_SIZE, SECUREBOOT

set -euo pipefail

# --- knobs (env-overridable) ---
: "${RAM:=4096}"                    # MiB
: "${CPUS:=$(nproc)}"
: "${DISK_SIZE:=30G}"               # default 30G qcow2
: "${SECUREBOOT:=0}"                # 1 to prefer Secure Boot OVMF if present

# --- helpers ---
need() { command -v "$1" >/dev/null 2>&1; }
sudo_wrap() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

install_packages_if_needed() {
  local to_install=()

  need qemu-system-x86_64 || to_install+=(qemu-full)
  need qemu-img            || to_install+=(qemu-full)
  need gum                 || to_install+=(gum)

  # OVMF presence check (edk2 or edk2-ovmf layouts)
  local have_ovmf=0
  local ovmf_candidates=(
    /usr/share/edk2/x64/OVMF_CODE.4m.fd
    /usr/share/edk2/x64/OVMF_VARS.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd
  )
  for p in "${ovmf_candidates[@]}"; do
    [[ -f "$p" ]] && have_ovmf=1 && break
  done
  if (( have_ovmf == 0 )); then
    # Try edk2-ovmf first; fall back to edk2
    if ! pacman -Qi edk2-ovmf >/dev/null 2>&1; then
      to_install+=(edk2-ovmf)
    fi
  fi

  if ((${#to_install[@]})); then
    echo "Installing: ${to_install[*]}" >&2
    sudo_wrap pacman -S --needed --noconfirm "${to_install[@]}" || {
      # If edk2-ovmf failed (tier split), try edk2
      if printf '%s\n' "${to_install[@]}" | grep -q '^edk2-ovmf$'; then
        sudo_wrap pacman -S --needed --noconfirm edk2
      else
        exit 1
      fi
    }
  fi
}

# --- ensure deps ---
install_packages_if_needed

# --- resolve repo/vm dirs whether run from repo root or vm/ ---
CWD="$(pwd)"
if [[ "$(basename "$CWD")" == "vm" ]]; then
  VM_DIR="$CWD"
  REPO_DIR="$(dirname "$CWD")"
else
  REPO_DIR="$CWD"
  VM_DIR="$REPO_DIR/vm"
fi
mkdir -p "$VM_DIR"

# --- pick ISO (arg > out/* with gum if many) ---
ISO="${1:-}"
if [[ -z "$ISO" ]]; then
  iso_candidates=("$REPO_DIR"/out/*.iso)
  if [[ ! -e "${iso_candidates[0]}" ]]; then
    echo "No ISO found under $REPO_DIR/out/. Provide one manually."
    echo "Usage: $0 /path/to/lnos.iso"
    exit 1
  elif [[ ${#iso_candidates[@]} -eq 1 ]]; then
    ISO="${iso_candidates[0]}"
  else
    if need gum; then
      ISO="$(gum choose "${iso_candidates[@]}")"
    else
      ISO="$(ls -1t "$REPO_DIR"/out/*.iso | head -n1)"
      echo "Multiple ISOs found; gum not installed. Using newest: $ISO"
    fi
  fi
fi
ISO="$(readlink -f "$ISO")"
[[ -f "$ISO" ]] || { echo "ISO not found at: $ISO"; exit 1; }

# --- OVMF paths (prefer modern 4m images). Try edk2 then edk2-ovmf fallbacks ---
CODE_SB=""
CODE_STD=""
VARS_SRC=""

# edk2 layout
[[ -f /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd ]] && CODE_SB="/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
[[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd       ]] && CODE_STD="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
[[ -f /usr/share/edk2/x64/OVMF_VARS.4m.fd       ]] && VARS_SRC="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# edk2-ovmf (legacy) layout fallbacks
[[ -z "$CODE_SB"  && -f /usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.4m.fd ]] && CODE_SB="/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.4m.fd"
[[ -z "$CODE_STD" && -f /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd       ]] && CODE_STD="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
[[ -z "$CODE_STD" && -f /usr/share/edk2-ovmf/x64/OVMF_CODE.fd          ]] && CODE_STD="/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
[[ -z "$VARS_SRC" && -f /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd       ]] && VARS_SRC="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
[[ -z "$VARS_SRC" && -f /usr/share/edk2-ovmf/x64/OVMF_VARS.fd          ]] && VARS_SRC="/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"

if [[ "$SECUREBOOT" == "1" && -n "$CODE_SB" ]]; then
  CODE="$CODE_SB"
elif [[ -n "$CODE_STD" ]]; then
  CODE="$CODE_STD"
else
  echo "OVMF code image not found. Install edk2-ovmf/edk2." >&2
  exit 1
fi
[[ -f "$VARS_SRC" ]] || { echo "OVMF VARS image not found."; exit 1; }

# --- ensure mutable VARS copy & qcow2 disk in vm/ ---
VARS="$VM_DIR/OVMF_VARS.fd"
[[ -f "$VARS" ]] || { cp "$VARS_SRC" "$VARS"; echo "Created $VARS"; }

DISK="$VM_DIR/lnos-test.qcow2"
if [[ ! -f "$DISK" ]]; then
  echo "Creating qcow2 disk: $DISK ($DISK_SIZE)"
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

# --- accel choice (auto-fallback if no /dev/kvm) ---
ACCEL_OPTS=()
CPU_OPTS=()
if [[ -e /dev/kvm ]]; then
  ACCEL_OPTS=(-enable-kvm -machine q35,accel=kvm)
  CPU_OPTS=(-cpu host)
else
  echo "/dev/kvm not present — using TCG (software accel)" >&2
  ACCEL_OPTS=(-machine q35,accel=tcg)
  CPU_OPTS=(-cpu max)
fi

echo "=== LnOS VM Launch ==="
echo "ISO:        $ISO"
echo "Disk:       $DISK"
echo "OVMF CODE:  $CODE"
echo "OVMF VARS:  $VARS"
echo "CPUs:       $CPUS"
echo "RAM (MiB):  $RAM"
echo "SecureBoot: $SECUREBOOT"
echo

exec qemu-system-x86_64 \
  "${ACCEL_OPTS[@]}" \
  "${CPU_OPTS[@]}" \
  -smp "$CPUS" -m "$RAM" \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=qcow2,cache=none,discard=unmap \
  -cdrom "$ISO" \
  -boot order=d,menu=on \
  -nic user,model=virtio-net-pci \
  -display gtk,gl=on \
  -device virtio-vga \
  -usb -device usb-tablet \
  -device ich9-intel-hda -device hda-output \
  -serial mon:stdio
