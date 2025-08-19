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
# Unless required by applicable law or agreed to in writing,
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */

#
# @file run-iso.sh
# @brief Launch the latest LnOS ISO (lnos*.iso) from repo-root/out in QEMU+KVM
#

set -euo pipefail

# --- Locate repo root and out/ ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer git root if available
if ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  REPO_ROOT="$ROOT"
else
  # Fallbacks
  if [[ -d "$HOME/Projects/lnos/out" ]]; then
    REPO_ROOT="$HOME/Projects/lnos"
  else
    echo "[ERR] Could not locate repo root or out/ directory."
    exit 1
  fi
fi

OUT_DIR="$REPO_ROOT/out"
ISO="$(ls -t "$OUT_DIR"/lnos*.iso 2>/dev/null | head -n 1 || true)"

MEMORY="${MEMORY:-4096}"        # 4 GB default
CPUS="${CPUS:-4}"               # 4 cores default
DISK="${DISK:-$REPO_ROOT/lnos-test.img}"
DISK_SIZE="${DISK_SIZE:-20G}"   # size for test disk

UEFI_CODE="${UEFI_CODE:-/usr/share/OVMF/OVMF_CODE.fd}"
UEFI_VARS="${UEFI_VARS:-/usr/share/OVMF/OVMF_VARS.fd}"

UEFI=0
for arg in "${@:-}"; do
  case "$arg" in
    --uefi) UEFI=1 ;;
    --help|-h)
      echo "Usage: $0 [--uefi]"
      exit 0
      ;;
  esac
done

main() {
  if [[ -z "$ISO" ]]; then
    echo "[ERR] No LnOS ISO found in $OUT_DIR (expected lnos*.iso)."
    exit 1
  fi

  echo "[LnOS] ISO: $ISO"

  if [[ ! -f "$DISK" ]]; then
    echo "[LnOS] Creating test disk: $DISK ($DISK_SIZE)"
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
  fi

  ARGS=(
    -enable-kvm
    -cpu host
    -smp "$CPUS"
    -m "$MEMORY"
    -cdrom "$ISO"
    -drive file="$DISK",format=qcow2
    -boot d
    -vga virtio
    -nic user,model=virtio-net-pci
    -display sdl,gl=on
    -name "LnOS VM"
    -machine type=q35,accel=kvm
    -serial mon:stdio
    -no-reboot
  )

  if (( UEFI )); then
    echo "[LnOS] Boot mode: UEFI (OVMF)"
    ARGS+=(
      -drive if=pflash,format=raw,readonly=on,file="$UEFI_CODE"
      -drive if=pflash,format=raw,file="$UEFI_VARS"
    )
  else
    echo "[LnOS] Boot mode: BIOS (SeaBIOS)"
    ARGS+=( -bios /usr/share/qemu/bios.bin )
  fi

  exec qemu-system-x86_64 "${ARGS[@]}"
}

main

# ---------------------------------------------------------------------------
# Example Usage:
#   ./run-iso.sh
#       → Boots the newest LnOS ISO in BIOS mode with 4GB RAM / 4 CPUs
#
#   ./run-iso.sh --uefi
#       → Boots with UEFI firmware (OVMF)
#
#   MEMORY=8192 CPUS=8 ./run-iso.sh --uefi
#       → Boots with 8GB RAM, 8 CPUs, UEFI mode
#
#   DISK=mytest.img DISK_SIZE=50G ./run-iso.sh
#       → Uses a custom 50GB qcow2 disk image
# ---------------------------------------------------------------------------
