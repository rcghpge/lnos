#!/bin/bash
# GRUB Theme Validation Script for LnOS
# Ensures all required files for UEFI GRUB theming are present

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHISO_DIR="$SCRIPT_DIR/../archiso"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Required files for GRUB theming
REQUIRED_FILES=(
    "grub/fonts/unicode.pf2"
    "grub/themes/lnos/theme.txt"
    "grub/themes/lnos/background.png"
)

echo "Validating GRUB theme files for LnOS..."
echo "======================================="

# Check if archiso directory exists
if [ ! -d "$ARCHISO_DIR" ]; then
    print_error "archiso directory not found at: $ARCHISO_DIR"
    exit 1
fi

cd "$ARCHISO_DIR"

# Validation flags
all_present=true

# Check each required file
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        if [ "$size" -gt 0 ]; then
            print_status "Found: $file (${size} bytes)"
        else
            print_error "Empty file: $file"
            all_present=false
        fi
    else
        print_error "Missing: $file"
        all_present=false
    fi
done

echo ""

# Additional validations
if [ -f "grub/themes/lnos/background.png" ]; then
    # Check PNG file properties
    if command -v file &> /dev/null; then
        file_info=$(file "grub/themes/lnos/background.png")
        if echo "$file_info" | grep -q "PNG image data, 1024 x 768"; then
            print_status "Background image has correct dimensions (1024x768)"
        else
            print_warning "Background image dimensions may not be optimal"
            echo "  File info: $file_info"
        fi
    fi
fi

if [ -f "grub/fonts/unicode.pf2" ]; then
    font_size=$(stat -c%s "grub/fonts/unicode.pf2")
    if [ "$font_size" -gt 1000000 ]; then
        print_status "Font file size is reasonable (${font_size} bytes)"
    else
        print_warning "Font file seems unusually small (${font_size} bytes)"
    fi
fi

# Check GRUB configuration
if [ -f "grub/grub.cfg" ]; then
    if grep -q "gfxterm" "grub/grub.cfg" && grep -q "unicode.pf2" "grub/grub.cfg"; then
        print_status "GRUB configuration includes graphics terminal setup"
    else
        print_warning "GRUB configuration may not have proper graphics setup"
    fi
    
    if grep -q "theme.*lnos" "grub/grub.cfg"; then
        print_status "GRUB configuration includes LnOS theme"
    else
        print_warning "GRUB configuration may not load LnOS theme"
    fi
fi

echo ""
echo "======================================="

if [ "$all_present" = true ]; then
    print_status "All required GRUB theme files are present!"
    echo ""
    echo "The ISO should now include:"
    echo "  - boot/grub/fonts/unicode.pf2"
    echo "  - boot/grub/themes/lnos/theme.txt"
    echo "  - boot/grub/themes/lnos/background.png"
    echo ""
    echo "UEFI GRUB theming should be reliable across different environments."
    exit 0
else
    print_error "Some required files are missing or invalid!"
    echo ""
    echo "Please ensure all files are present before building the ISO."
    exit 1
fi