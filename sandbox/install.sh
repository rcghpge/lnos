#!/bin/bash
# sandbox/install.sh
# LN OS Sandbox Install Script
# Goal is an isolated sandbox for builds, package testing, and CI validation

set -euo pipefail

# -------------------- Header --------------------
echo "🔧 [LN OS Sandbox] Starting sandbox/install.sh..."
echo "🧪 This environment is isolated from origin/main and origin/recovery"
echo "📦 Running on: $(uname -a)"

# -------------------- Profile Info --------------------
PROFILE_NAME="sandbox"
echo "👤 Active profile: $PROFILE_NAME"

# -------------------- Example usage --------------------
echo "🚧 [sandbox] Installing test packages (dry-run logic)..."

# Example: test installing a dummy package
if command -v pacman &>/dev/null; then
  echo "📦 Detected pacman (Arch)"
  echo "▶️ Would install: neofetch, bat, htop"
  # pacman -S --noconfirm neofetch bat htop
else
  echo "⚠️ Unknown package manager. Skipping installs."
fi

# -------------------- Sandbox Configs --------------------
echo "📁 Sandbox install root: $(pwd)"

# Example sandbox-only config
if [[ -f /etc/lnos-release ]]; then
  echo "📄 LN OS release detected:"
  cat /etc/lnos-release
else
  echo "⚠️ LN OS release file not found. Continuing anyway..."
fi

# -------------------- Footer --------------------
echo "✅ [LN OS Sandbox] install.sh completed successfully."

