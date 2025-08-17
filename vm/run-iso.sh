#!/usr/bin/env bash
set -euo pipefail

# --- knobs (env-overridable) ---
: "${RAM:=4096}"                    # MiB
: "${CPUS:=$(nproc)}"
: "${DISK_SIZE:=30G}"               # default 30G
: "${SECUREBOOT:=0}"                # set 1 to use secboot OVMF if present

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

# --- OVMF paths on Arch/LnOS ---
CODE_SB="/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
CODE_STD="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
VARS_SRC="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

if [[ "$SECUREBOOT" == "1" && -f "$CODE_SB" ]]; then
  CODE="$CODE_SB"
elif [[ -f "$CODE_STD" ]]; then
  CODE="$CODE_STD"
else
  echo "❌ OVMF code image not found. Install edk2-ovmf." >&2
  exit 1
fi
[[ -f "$VARS_SRC" ]] || { echo "❌ OVMF_VARS.4m.fd not found. Install edk2-ovmf."; exit 1; }

# --- ensure mutable VARS copy & qcow2 disk ---
VARS="$VM_DIR/OVMF_VARS.fd"
[[ -f "$VARS" ]] || { cp "$VARS_SRC" "$VARS"; echo "→ created $VARS"; }

DISK="$VM_DIR/lnos-test.qcow2"
[[ -f "$DISK" ]] || { qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"; echo "→ created $DISK ($DISK_SIZE)"; }

# --- resolve ISO: arg > newest under out/ > error ---
ISO="${1:-}"
if [[ -z "$ISO" ]]; then
  if [[ -d "$REPO_DIR/out" ]]; then
    # shellcheck disable=SC2012
    ISO="$(ls -1t "$REPO_DIR"/out/*.iso 2>/dev/null | head -n1 || true)"
  fi
fi
[[ -n "${ISO:-}" ]] || { echo "❌ No ISO provided and none found under '$REPO_DIR/out/'."; echo "   Usage: $0 /path/to/lnos.iso"; exit 1; }
ISO="$(readlink -f "$ISO")"
[[ -f "$ISO" ]] || { echo "❌ ISO not found at: $ISO"; exit 1; }

echo "=== LnOS VM Launch ==="
echo "ISO:        $ISO"
echo "Disk:       $DISK"
echo "OVMF CODE:  $CODE"
echo "OVMF VARS:  $VARS"
echo "CPUs:       $CPUS"
echo "RAM (MiB):  $RAM"
echo

exec qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp "$CPUS" -m "$RAM" \
  -machine q35,accel=kvm \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -cdrom "$ISO" \
  -boot order=d,menu=on \
  -nic user,model=virtio-net-pci \
  -display gtk,gl=on \
  -device virtio-vga \
  -device ich9-intel-hda -device hda-output


# ---------------------------------------------------------------------------
# Example Usage:
#
# From inside vm/ directory:
#   ../run-iso.sh
#   ../run-iso.sh ../out/lnos-2025.08.16-x86_64.iso
#
# From repo root:
#   ./run-iso.sh
#   ./run-iso.sh out/lnos-2025.08.16-x86_64.iso
#
# Optional environment overrides:
#   RAM=8192 CPUS=8 ./run-iso.sh               # give VM 8 GB RAM and 8 vCPUs
#   DISK_SIZE=50G ./run-iso.sh                 # create/use a 50G qcow2 disk
#   SECUREBOOT=1 ./run-iso.sh                  # use OVMF Secure Boot firmware
#
# Notes:
# - Default disk size is 30G (qcow2, auto-created if missing).
# - Default RAM is 4096 MiB, CPUs = all host cores.
# - ISO is auto-detected as the newest in out/*.iso if not provided.
# ---------------------------------------------------------------------------
