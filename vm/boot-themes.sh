# LnOS Frontend for boot menu themes

#!/bin/bash

# UEFI ESP theme
mkdir -p ../archiso/efiboot/grub/themes/lnos
cp ../archiso/syslinux/splash.png ../efiboot/grub/themes/lnos/background.png
cat > ../archiso/efiboot/grub/themes/lnos/theme.txt <<'EOF'
# Minimal LnOS GRUB theme (ESP)
desktop-image: "background.png"
EOF

# UEFI El Torito theme
mkdir -p ../archiso/grub/themes/lnos
cp ../archiso/syslinux/splash.png ../grub/themes/lnos/background.png
cat > ../archiso/grub/themes/lnos/theme.txt <<'EOF'
# Minimal LnOS GRUB theme (El Torito)
desktop-image: "background.png"
EOF
