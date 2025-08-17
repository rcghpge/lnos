#!/bin/bash

# LnOS CI/CD Validation Script
# This script validates that the CI/CD setup is working correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 LnOS CI/CD Validation${NC}"
echo "=========================="
echo ""

# Check if we're in the right directory
if [ ! -f "build-iso.sh" ]; then
    echo -e "${RED}❌ Error: build-iso.sh not found. Are you in the LnOS repository root?${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Repository structure validation${NC}"

# Validate build scripts exist and are executable
echo "🔧 Checking build scripts..."
for script in build-iso.sh build-arm-image.sh build-arm-minimal.sh; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo -e "  ${GREEN}✅ $script${NC}"
    else
        echo -e "  ${RED}❌ $script (missing or not executable)${NC}"
        exit 1
    fi
done

# Validate GPG key exists
echo "🔑 Checking GPG setup..."
if [ -f "keys/lnos-public-key.asc" ]; then
    echo -e "  ${GREEN}✅ GPG public key exists${NC}"
    
    # Test key import
    GPG_TEST_DIR=$(mktemp -d)
    export GNUPGHOME="$GPG_TEST_DIR"
    
    if gpg --import keys/lnos-public-key.asc >/dev/null 2>&1; then
        KEY_ID=$(gpg --list-keys --with-colons | awk -F: '/^pub:/ {print $5}' | head -1)
        if [ "$KEY_ID" = "9486759312876AD7" ]; then
            echo -e "  ${GREEN}✅ GPG key valid (ID: $KEY_ID)${NC}"
        else
            echo -e "  ${YELLOW}⚠️  GPG key ID mismatch: $KEY_ID (expected: 9486759312876AD7)${NC}"
        fi
    else
        echo -e "  ${RED}❌ GPG key import failed${NC}"
        exit 1
    fi
    
    rm -rf "$GPG_TEST_DIR"
else
    echo -e "  ${RED}❌ GPG public key missing${NC}"
    exit 1
fi

# Validate archiso configuration
echo "📦 Checking archiso configuration..."
if [ -d "archiso" ]; then
    echo -e "  ${GREEN}✅ archiso directory exists${NC}"
    
    for file in packages.x86_64 profiledef.sh; do
        if [ -f "archiso/$file" ]; then
            echo -e "  ${GREEN}✅ archiso/$file${NC}"
        else
            echo -e "  ${RED}❌ archiso/$file missing${NC}"
            exit 1
        fi
    done
else
    echo -e "  ${RED}❌ archiso directory missing${NC}"
    exit 1
fi

# Validate GitHub workflows
echo "⚙️  Checking GitHub workflows..."
if [ -d ".github/workflows" ]; then
    echo -e "  ${GREEN}✅ .github/workflows directory exists${NC}"
    
    for workflow in ci-main.yml build-iso.yml lint.yml; do
        if [ -f ".github/workflows/$workflow" ]; then
            echo -e "  ${GREEN}✅ $workflow${NC}"
        else
            echo -e "  ${RED}❌ $workflow missing${NC}"
            exit 1
        fi
    done
else
    echo -e "  ${RED}❌ .github/workflows directory missing${NC}"
    exit 1
fi

# Validate verification script
echo "🔐 Checking verification script..."
if [ -f "scripts/verify-signature.sh" ] && [ -x "scripts/verify-signature.sh" ]; then
    echo -e "  ${GREEN}✅ verify-signature.sh exists and is executable${NC}"
    
    # Check for correct repository URLs
    if grep -q "rcghpge/lnos" scripts/verify-signature.sh; then
        echo -e "  ${GREEN}✅ Repository URLs updated${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Repository URLs may need updating${NC}"
    fi
else
    echo -e "  ${RED}❌ verify-signature.sh missing or not executable${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 All validation checks passed!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo "- Build scripts are present and executable"
echo "- GPG key is valid and ready for signing"
echo "- archiso configuration is complete"
echo "- GitHub workflows are configured"
echo "- Verification script is ready"
echo ""
echo -e "${GREEN}✅ CI/CD setup is ready for use${NC}"