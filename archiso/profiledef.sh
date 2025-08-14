#!/usr/bin/env bash

iso_name="lnos"
iso_label="LNOS_$(date +%Y%m)"
iso_publisher="UTA-LugNuts <https://github.com/uta-lug-nuts/LnOS>"
iso_application="LnOS Install CD"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
esp_size_mb="128"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito'
           'uefi-ia32.grub.esp' 'uefi-x64.grub.esp'
           'uefi-ia32.grub.eltorito' 'uefi-x64.grub.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
mkinitcpio_conf="mkinitcpio.conf"
_threads=$(nproc 2>/dev/null || echo 1)
(( _threads < 1 )) && _threads=1
airootfs_image_tool_options=(-comp zstd -Xcompression-level 12 -processors "$_threads" -no-xattrs)
file_permissions=(
  ["/root"]="0:0:750"
  ["/root/.bashrc"]="0:0:644"
  ["/root/.profile"]="0:0:644"
  ["/etc/bash.bashrc"]="0:0:644"
  ["/etc/fstab"]="0:0:0644"
  ["/usr/local/sbin/lnos-merge-pacnew"]="0:0:755"
  ["/usr/local/bin/LnOS-installer.sh"]="0:0:755"
  ["/usr/local/bin/lnos-autostart.sh"]="0:0:755"
  ["/usr/local/bin/lnos-shell.sh"]="0:0:755"
  ["/usr/local/bin/setup-lnos-autostart.sh"]="0:0:755"
  ["/usr/local/bin/lnos-boot-start.sh"]="0:0:755"
  ["/etc/systemd/system/lnos-autostart.service"]="0:0:644"
  ["/etc/systemd/system/lnos-boot.service"]="0:0:644"
  ["/.discinfo"]="0:0:644"
  ["/etc/os-release"]="0:0:644"
  ["/autorun.inf"]="0:0:644"
  ["/README.txt"]="0:0:644"
)

# --- Post-build checks ---
post_build() {
  # Check ISO staging for the final ISO tree
  local iso_root="${work_dir}/iso/${install_dir}"

  # BIOS: Syslinux menu
  if [[ -f "${iso_root}/boot/syslinux/syslinux.cfg" ]]; then
    sed -i \
      -e "s|%INSTALL_DIR%|${install_dir}|g" \
      -e "s|%ARCHISO_LABEL%|${iso_label}|g" \
      "${iso_root}/boot/syslinux/syslinux.cfg"
  fi

  # UEFI: GRUB 
  if [[ -f "${iso_root}/boot/grub/grub.cfg" ]]; then
    sed -i \
      -e "s|%INSTALL_DIR%|${install_dir}|g" \
      -e "s|%ARCHISO_LABEL%|${iso_label}|g" \
      "${iso_root}/boot/grub/grub.cfg"
  fi

  # Check boot entries (e.g., systemd‑boot loader entries)
  if [[ -d "${iso_root}/boot/loader/entries" ]]; then
    find "${iso_root}/boot/loader/entries" -type f -name '*.conf' -print0 \
      | xargs -0 -r sed -i \
        -e "s|%INSTALL_DIR%|${install_dir}|g" \
        -e "s|%ARCHISO_LABEL%|${iso_label}|g"
  fi
}

