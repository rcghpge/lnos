#!/bin/bash

# Build script for LnOS ARM SD card image
# Usage: ./build-arm-image.sh [rpi4|generic]

set -e

DEVICE=${1:-rpi4}
OUTPUT_DIR="$(pwd)/out"
IMAGE_NAME="lnos-arm64-${DEVICE}-$(date +%Y.%m.%d).img"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (required for image creation)
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root for image creation"
    exit 1
fi

print_status "Building LnOS ARM64 image for $DEVICE..."

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create a 4GB image file
print_status "Creating 4GB image file..."
dd if=/dev/zero of="$OUTPUT_DIR/$IMAGE_NAME" bs=1M count=4096

# Set up loop device
print_status "Setting up loop device..."
LOOP_DEV=$(losetup -f --show "$OUTPUT_DIR/$IMAGE_NAME")

# Partition the image
print_status "Partitioning image..."
parted "$LOOP_DEV" mklabel msdos
parted "$LOOP_DEV" mkpart primary fat32 1MiB 513MiB
parted "$LOOP_DEV" mkpart primary ext4 513MiB 100%
parted "$LOOP_DEV" set 1 boot on

# Refresh partition table and wait for device nodes
partprobe "$LOOP_DEV"
sleep 2

# Check if partition devices exist, create them if needed
if [ ! -e "${LOOP_DEV}p1" ]; then
    # Try alternative method using kpartx
    if command -v kpartx >/dev/null 2>&1; then
        print_status "Using kpartx to create partition devices..."
        kpartx -av "$LOOP_DEV"
        PART1="/dev/mapper/$(basename $LOOP_DEV)p1"
        PART2="/dev/mapper/$(basename $LOOP_DEV)p2"
    else
        print_error "Cannot create partition devices. Container limitations."
        print_status "Creating unpartitioned filesystem instead..."
        
        # Create a simple unpartitioned image with just ext4
        mkfs.ext4 "$LOOP_DEV"
        
        # Mount and set up
        MOUNT_DIR="/tmp/lnos-arm-mount"
        mkdir -p "$MOUNT_DIR"
        mount "$LOOP_DEV" "$MOUNT_DIR"
        mkdir -p "$MOUNT_DIR/boot"
        
        # Skip boot partition setup for now
        SKIP_BOOT=1
    fi
else
    PART1="${LOOP_DEV}p1"
    PART2="${LOOP_DEV}p2"
fi

if [ "$SKIP_BOOT" != "1" ]; then
    # Format partitions
    print_status "Formatting partitions..."
    mkfs.fat -F32 "$PART1"
    mkfs.ext4 "$PART2"
    
    # Mount partitions
    print_status "Mounting partitions..."
    MOUNT_DIR="/tmp/lnos-arm-mount"
    mkdir -p "$MOUNT_DIR"
    mount "$PART2" "$MOUNT_DIR"
    mkdir -p "$MOUNT_DIR/boot"
    mount "$PART1" "$MOUNT_DIR/boot"
fi

# Download and extract Arch Linux ARM
print_status "Downloading Arch Linux ARM..."
case "$DEVICE" in
    "rpi4")
        TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz"
        ;;
    "generic")
        TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
        ;;
    *)
        print_error "Unsupported device: $DEVICE"
        exit 1
        ;;
esac

wget -O "/tmp/archlinuxarm.tar.gz" "$TARBALL_URL"

print_status "Extracting root filesystem..."
tar -xzf "/tmp/archlinuxarm.tar.gz" -C "$MOUNT_DIR"

# Copy LnOS files
print_status "Installing LnOS components..."
mkdir -p "$MOUNT_DIR/root/LnOS/scripts"
cp -r scripts/pacman_packages "$MOUNT_DIR/root/LnOS/scripts/"
cp scripts/LnOS-installer.sh "$MOUNT_DIR/root/LnOS/scripts/"
chmod +x "$MOUNT_DIR/root/LnOS/scripts/LnOS-installer.sh"

# Create auto-start script
cat > "$MOUNT_DIR/root/.bashrc" << 'EOF'
#!/bin/bash

echo "=========================================="
echo "      Welcome to LnOS ARM64 Environment"
echo "=========================================="
echo ""
echo "To start the installation, run:"
echo "  cd /root/LnOS/scripts && ./LnOS-installer.sh --target=aarch64"
echo ""
echo "For help, run:"
echo "  ./LnOS-installer.sh --help"
echo ""
echo "Network configuration:"
echo "  systemctl enable systemd-networkd"
echo "  systemctl start systemd-networkd"
echo "  echo '[Match]\nName=*\n[Network]\nDHCP=yes' > /etc/systemd/network/20-wired.network"
echo "=========================================="
echo ""

# Source original bashrc if it exists
if [ -f /etc/bash.bashrc ]; then
    source /etc/bash.bashrc
fi
EOF

# Enable NetworkManager (if available)
print_status "Configuring services..."
if chroot "$MOUNT_DIR" systemctl --quiet is-enabled NetworkManager 2>/dev/null; then
    chroot "$MOUNT_DIR" systemctl enable NetworkManager
else
    print_warning "NetworkManager not found, skipping service enablement"
    print_status "User will need to configure networking manually after boot"
fi

# Clean up
print_status "Cleaning up..."
if [ "$SKIP_BOOT" != "1" ]; then
    umount "$MOUNT_DIR/boot" 2>/dev/null || true
fi
umount "$MOUNT_DIR" 2>/dev/null || true
rmdir "$MOUNT_DIR" 2>/dev/null || true

# Clean up device mappings
if command -v kpartx >/dev/null 2>&1; then
    kpartx -dv "$LOOP_DEV" 2>/dev/null || true
fi

losetup -d "$LOOP_DEV" 2>/dev/null || true
rm -f "/tmp/archlinuxarm.tar.gz"

print_status "ARM64 image created: $OUTPUT_DIR/$IMAGE_NAME"
print_status "To write to SD card: dd if=$OUTPUT_DIR/$IMAGE_NAME of=/dev/sdX bs=4M status=progress"