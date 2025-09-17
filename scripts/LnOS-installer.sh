#!/bin/bash

# /*
# Copyright 2025 UTA-LugNuts Authors.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */

#
# @file LnOS-installer.sh
# @brief Installs Arch linux with LnOS customizations
# @author Betim-Hodza, Ric3y
# @date 2025
#

set -e

# GLOBALS
VERSION='1.0.0'
SCRIPT_LOG="./installer.log"
SCRIPT_CONFIG="./installer.conf"
SCRIPT_TMP_DIR="$(mktemp -d "./.tmp.XXXXX")"
ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"

[ "$*" = "--version" ] && echo "$VERSION" && exit 0

# COLORS
COLOR_BLACK=0   #  #000000
COLOR_RED=9     #  #ff0000
COLOR_GREEN=10  #  #00ff00
COLOR_YELLOW=11 #  #ffff00
COLOR_BLUE=12   #  #0000ff
COLOR_PURPLE=13 #  #ff00ff
COLOR_CYAN=14   #  #00ffff
COLOR_WHITE=15  #  #ffffff

COLOR_FOREGROUND="${COLOR_BLUE}"
COLOR_BACKGROUND="${COLOR_WHITE}"

# Configuration variables
LNOS_USERNAME=""
LNOS_PASSWORD=""
LNOS_TIMEZONE=""
LNOS_LOCALE_LANG=""
LNOS_LOCALE_GEN_LIST=()
LNOS_VCONSOLE_KEYMAP=""
LNOS_DISK=""
LNOS_BOOT_PARTITION=""
LNOS_ROOT_PARTITION=""
LNOS_FILESYSTEM=""
LNOS_BOOTLOADER=""
LNOS_ENCRYPTION_ENABLED=""
LNOS_DESKTOP_ENABLED=""
LNOS_DESKTOP_ENVIRONMENT=""
LNOS_DESKTOP_GRAPHICS_DRIVER=""
LNOS_MULTILIB_ENABLED=""
LNOS_AUR_HELPER=""
LNOS_PACKAGE_PROFILE=""

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# TRAP FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

trap_error() {
    echo "Command '${BASH_COMMAND}' failed with exit code $? in function '${1}' (line ${2})" >"$ERROR_MSG"
}

trap_exit() {
    local result_code="$?"
    local error && [ -f "$ERROR_MSG" ] && error="$(<"$ERROR_MSG")" && rm -f "$ERROR_MSG"
    
    # Cleanup
    unset LNOS_PASSWORD
    rm -rf "$SCRIPT_TMP_DIR"
    
    [ "$result_code" = "130" ] && gum_warn "Exit..." && exit 1
    
    if [ "$result_code" -gt "0" ]; then
        [ -n "$error" ] && gum_fail "$error"
        [ -z "$error" ] && gum_fail "An Error occurred"
        gum_warn "See ${SCRIPT_LOG} for more information..."
    fi
    
    exit "$result_code"
}

# Set traps
trap 'trap_exit' EXIT
trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GUM WRAPPER FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_FOREGROUND" --selected.background "$COLOR_FOREGROUND" --selected.foreground "$COLOR_BACKGROUND" --unselected.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --cursor.foreground "$COLOR_FOREGROUND" --prompt.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_FOREGROUND" --cursor.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_FOREGROUND" --indicator.foreground "$COLOR_FOREGROUND" --match.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_write() { gum write --prompt "> " --show-cursor-line --char-limit 0 --cursor.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_FOREGROUND" --spinner.foreground "$COLOR_FOREGROUND" "${@}"; }

# Gum colors
gum_foreground() { gum_style --foreground "$COLOR_FOREGROUND" "${@}"; }
gum_background() { gum_style --foreground "$COLOR_BACKGROUND" "${@}"; }
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_black() { gum_style --foreground "$COLOR_BLACK" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_blue() { gum_style --foreground "$COLOR_BLUE" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_cyan() { gum_style --foreground "$COLOR_CYAN" "${@}"; }
gum_purple() { gum_style --foreground "$COLOR_PURPLE" "${@}"; }

# Gum prints
gum_title() { log_head "${*}" && gum join "$(gum_foreground --bold "+ ")" "$(gum_foreground --bold "${*}")"; }
gum_info() { log_info "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "${*}")"; }
gum_warn() { log_warn "$*" && gum join "$(gum_yellow --bold "• ")" "$(gum_white "${*}")"; }
gum_fail() { log_fail "$*" && gum join "$(gum_red --bold "• ")" "$(gum_white "${*}")"; }

# Gum key & value
gum_proc() { log_proc "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white --bold "$(print_filled_space 24 "${1}")")" "$(gum_white "  >  ")" "$(gum_green "${2}")"; }
gum_property() { log_prop "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "$(print_filled_space 24 "${1}")")" "$(gum_green --bold "  >  ")" "$(gum_white --bold "${2}")"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGGING WRAPPER
# ////////////////////////////////////////////////////////////////////////////////////////////////////

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | lnos | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_head() { write_log "HEAD | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }
log_prop() { write_log "PROP | ${*}"; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# HELPER FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

print_header() {
    local title="$1"
    clear && gum_foreground '
 █████                     ███████     █████████ 
░░███                    ███░░░░░███  ███░░░░░███
 ░███        ████████   ███     ░░███░███    ░░░ 
 ░███       ░░███░░███ ░███      ░███░░█████████ 
 ░███        ░███ ░███ ░███      ░███ ░░░░░░░░███
 ░███      █ ░███ ░███ ░░███     ███  ███    ░███
 ███████████ ████ █████ ░░░███████░  ░░█████████ 
░░░░░░░░░░░ ░░░░ ░░░░░    ░░░░░░░     ░░░░░░░░░  '
    local header_version="               v. ${VERSION}"
    gum_white --margin "1 0" --align left --bold "Welcome to ${title} ${header_version}"
    return 0
}

print_filled_space() {
    local total="$1" && local text="$2" && local length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    local padding=$((total - length)) && printf '%s%*s\n' "$text" "$padding" ""
}

trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PROPERTIES FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

properties_source() {
    [ ! -f "$SCRIPT_CONFIG" ] && return 1
    set -a
    source "$SCRIPT_CONFIG"
    set +a
    return 0
}

properties_generate() {
    {
        echo "LNOS_USERNAME='${LNOS_USERNAME}'"
        echo "LNOS_DISK='${LNOS_DISK}'"
        echo "LNOS_BOOT_PARTITION='${LNOS_BOOT_PARTITION}'"
        echo "LNOS_ROOT_PARTITION='${LNOS_ROOT_PARTITION}'"
        echo "LNOS_FILESYSTEM='${LNOS_FILESYSTEM}'"
        echo "LNOS_BOOTLOADER='${LNOS_BOOTLOADER}'"
        echo "LNOS_ENCRYPTION_ENABLED='${LNOS_ENCRYPTION_ENABLED}'"
        echo "LNOS_TIMEZONE='${LNOS_TIMEZONE}'"
        echo "LNOS_LOCALE_LANG='${LNOS_LOCALE_LANG}'"
        echo "LNOS_LOCALE_GEN_LIST=(${LNOS_LOCALE_GEN_LIST[*]@Q})"
        echo "LNOS_VCONSOLE_KEYMAP='${LNOS_VCONSOLE_KEYMAP}'"
        echo "LNOS_DESKTOP_ENABLED='${LNOS_DESKTOP_ENABLED}'"
        echo "LNOS_DESKTOP_ENVIRONMENT='${LNOS_DESKTOP_ENVIRONMENT}'"
        echo "LNOS_DESKTOP_GRAPHICS_DRIVER='${LNOS_DESKTOP_GRAPHICS_DRIVER}'"
        echo "LNOS_MULTILIB_ENABLED='${LNOS_MULTILIB_ENABLED}'"
        echo "LNOS_AUR_HELPER='${LNOS_AUR_HELPER}'"
        echo "LNOS_PACKAGE_PROFILE='${LNOS_PACKAGE_PROFILE}'"
    } >"$SCRIPT_CONFIG"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SELECTION FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

select_username() {
    if [ -z "$LNOS_USERNAME" ]; then
        local user_input
        user_input=$(gum_input --header "+ Enter Username") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_USERNAME="$user_input" && properties_generate
    fi
    gum_property "Username" "$LNOS_USERNAME"
    return 0
}

select_password() {
    if [ "$1" = "--change" ] || [ -z "$LNOS_PASSWORD" ]; then
        local user_password user_password_check
        user_password=$(gum_input --password --header "+ Enter Password") || trap_gum_exit_confirm
        [ -z "$user_password" ] && return 1
        user_password_check=$(gum_input --password --header "+ Enter Password again") || trap_gum_exit_confirm
        [ -z "$user_password_check" ] && return 1
        if [ "$user_password" != "$user_password_check" ]; then
            gum_confirm --affirmative="Ok" --negative="" "The passwords are not identical"
            return 1
        fi
        LNOS_PASSWORD="$user_password" && properties_generate
    fi
    [ "$1" = "--change" ] && gum_info "Password successfully changed"
    [ "$1" != "--change" ] && gum_property "Password" "*******"
    return 0
}

select_timezone() {
    if [ -z "$LNOS_TIMEZONE" ]; then
        local tz_auto user_input
        tz_auto="$(curl -s http://ip-api.com/line?fields=timezone 2>/dev/null || echo "America/Chicago")"
        user_input=$(gum_input --header "+ Enter Timezone (auto-detected)" --value "$tz_auto") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
            gum_confirm --affirmative="Ok" --negative="" "Timezone '${user_input}' is not supported"
            return 1
        fi
        LNOS_TIMEZONE="$user_input" && properties_generate
    fi
    gum_property "Timezone" "$LNOS_TIMEZONE"
    return 0
}

select_language() {
    if [ -z "$LNOS_LOCALE_LANG" ] || [ -z "${LNOS_LOCALE_GEN_LIST[*]}" ]; then
        local user_input items options
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@")
        options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
        user_input=$(gum_filter --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_LOCALE_LANG="$user_input"
        LNOS_LOCALE_GEN_LIST=() && while read -r locale_entry; do
            LNOS_LOCALE_GEN_LIST+=("$locale_entry")
        done < <(sed "/^#${LNOS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$LNOS_LOCALE_LANG")
        [[ "${LNOS_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && LNOS_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
        properties_generate
    fi
    gum_property "Language" "$LNOS_LOCALE_LANG"
    return 0
}

select_keyboard() {
    if [ -z "$LNOS_VCONSOLE_KEYMAP" ]; then
        local user_input items options
        mapfile -t items < <(command localectl list-keymaps)
        options=() && for item in "${items[@]}"; do options+=("$item"); done
        user_input=$(gum_filter --header "+ Choose Keyboard" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_VCONSOLE_KEYMAP="$user_input" && properties_generate
    fi
    gum_property "Keyboard" "$LNOS_VCONSOLE_KEYMAP"
    return 0
}

select_disk() {
    if [ -z "$LNOS_DISK" ] || [ -z "$LNOS_BOOT_PARTITION" ] || [ -z "$LNOS_ROOT_PARTITION" ]; then
        local user_input items options
        mapfile -t items < <(lsblk -I 8,259,254 -d -o KNAME,SIZE -n)
        options=() && for item in "${items[@]}"; do options+=("/dev/${item}"); done
        user_input=$(gum_choose --header "+ Choose Disk" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        user_input=$(echo "$user_input" | awk -F' ' '{print $1}')
        [ ! -e "$user_input" ] && log_fail "Disk does not exists" && return 1
        LNOS_DISK="$user_input"
        [[ "$LNOS_DISK" = "/dev/nvm"* ]] && LNOS_BOOT_PARTITION="${LNOS_DISK}p1" || LNOS_BOOT_PARTITION="${LNOS_DISK}1"
        [[ "$LNOS_DISK" = "/dev/nvm"* ]] && LNOS_ROOT_PARTITION="${LNOS_DISK}p2" || LNOS_ROOT_PARTITION="${LNOS_DISK}2"
        properties_generate
    fi
    gum_property "Disk" "$LNOS_DISK"
    return 0
}

select_filesystem() {
    if [ -z "$LNOS_FILESYSTEM" ]; then
        local user_input options
        options=("btrfs" "ext4")
        user_input=$(gum_choose --header "+ Choose Filesystem (snapshot support: btrfs)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_FILESYSTEM="$user_input" && properties_generate
    fi
    gum_property "Filesystem" "${LNOS_FILESYSTEM}"
    return 0
}

select_bootloader() {
    if [ -z "$LNOS_BOOTLOADER" ]; then
        local user_input options
        options=("grub" "systemd")
        user_input=$(gum_choose --header "+ Choose Bootloader (snapshot menu: grub)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_BOOTLOADER="$user_input" && properties_generate
    fi
    gum_property "Bootloader" "${LNOS_BOOTLOADER}"
    return 0
}

select_enable_encryption() {
    if [ -z "$LNOS_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable Disk Encryption?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && { trap_gum_exit_confirm; return 1; }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        LNOS_ENCRYPTION_ENABLED="$user_input" && properties_generate
    fi
    gum_property "Disk Encryption" "$LNOS_ENCRYPTION_ENABLED"
    return 0
}

select_enable_desktop_environment() {
    if [ -z "$LNOS_DESKTOP_ENABLED" ] || [ -z "$LNOS_DESKTOP_ENVIRONMENT" ]; then
        local user_input options
        options=("Gnome" "KDE" "Hyprland" "DWM" "TTY")
        user_input=$(gum_choose --header "+ Choose Desktop Environment" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_DESKTOP_ENVIRONMENT="$user_input"
        [ "$user_input" = "TTY" ] && LNOS_DESKTOP_ENABLED="false" || LNOS_DESKTOP_ENABLED="true"
        properties_generate
    fi
    gum_property "Desktop Environment" "$LNOS_DESKTOP_ENVIRONMENT"
    return 0
}

select_enable_desktop_driver() {
    if [ "$LNOS_DESKTOP_ENABLED" = "true" ]; then
        if [ -z "$LNOS_DESKTOP_GRAPHICS_DRIVER" ] || [ "$LNOS_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
            local user_input options
            options=("mesa" "intel_i915" "nvidia" "amd" "ati")
            user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
            [ -z "$user_input" ] && return 1
            LNOS_DESKTOP_GRAPHICS_DRIVER="$user_input" && properties_generate
        fi
        gum_property "Desktop Graphics Driver" "$LNOS_DESKTOP_GRAPHICS_DRIVER"
    fi
    return 0
}

select_enable_multilib() {
    if [ -z "$LNOS_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && { trap_gum_exit_confirm; return 1; }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        LNOS_MULTILIB_ENABLED="$user_input" && properties_generate
    fi
    gum_property "32 Bit Support" "$LNOS_MULTILIB_ENABLED"
    return 0
}

select_enable_aur() {
    if [ -z "$LNOS_AUR_HELPER" ]; then
        local user_input options
        options=("paru" "paru-git" "none")
        user_input=$(gum_choose --header "+ Choose AUR Helper (default: paru)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_AUR_HELPER="$user_input" && properties_generate
    fi
    gum_property "AUR Helper" "$LNOS_AUR_HELPER"
    return 0
}

select_package_profile() {
    if [ -z "$LNOS_PACKAGE_PROFILE" ]; then
        local user_input options
        options=("CSE" "Custom" "Minimal")
        user_input=$(gum_choose --header "+ Choose Package Profile" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1
        LNOS_PACKAGE_PROFILE="$user_input" && properties_generate
    fi
    gum_property "Package Profile" "$LNOS_PACKAGE_PROFILE"
    return 0
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# INSTALLATION FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

install_base_system() {
    gum_info "Installing base system..."
    
    # Check boot mode
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="uefi"
        log_info "UEFI detected"
    else
        BOOT_MODE="bios"
        log_info "BIOS/Legacy boot detected"
    fi
    
    # Update system clock
    timedatectl set-ntp true
    
    # Partition disk based on boot mode
    wipefs -af "$LNOS_DISK"
    sgdisk --zap-all "$LNOS_DISK"
    
    if [ "$BOOT_MODE" = "uefi" ]; then
        # UEFI partitioning (GPT)
        sgdisk -o "$LNOS_DISK"
        sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$LNOS_DISK"
        sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$LNOS_DISK"
    else
        # BIOS partitioning (MBR)
        parted "$LNOS_DISK" mklabel msdos
        parted "$LNOS_DISK" mkpart primary ext2 1MiB 513MiB
        parted "$LNOS_DISK" mkpart primary $LNOS_FILESYSTEM 513MiB 100%
        parted "$LNOS_DISK" set 1 boot on
    fi
    
    partprobe "$LNOS_DISK"
    
    # Handle encryption
    if [ "$LNOS_ENCRYPTION_ENABLED" = "true" ]; then
        echo -n "$LNOS_PASSWORD" | cryptsetup luksFormat "$LNOS_ROOT_PARTITION"
        echo -n "$LNOS_PASSWORD" | cryptsetup open "$LNOS_ROOT_PARTITION" cryptroot
    fi
    
    # Format partitions
    if [ "$BOOT_MODE" = "uefi" ]; then
        mkfs.fat -F 32 -n BOOT "$LNOS_BOOT_PARTITION"
    else
        mkfs.ext2 -L BOOT "$LNOS_BOOT_PARTITION"
    fi
    
    if [ "$LNOS_FILESYSTEM" = "ext4" ]; then
        [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot || mkfs.ext4 -F -L ROOT "$LNOS_ROOT_PARTITION"
    else
        [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && mkfs.btrfs -f -L BTRFS /dev/mapper/cryptroot || mkfs.btrfs -f -L BTRFS "$LNOS_ROOT_PARTITION"
    fi
    
    # Mount filesystems
    [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && mount /dev/mapper/cryptroot /mnt || mount "$LNOS_ROOT_PARTITION" /mnt
    mount --mkdir "$LNOS_BOOT_PARTITION" /mnt/boot
    
    # Install base packages
    local packages=(base linux-hardened linux-firmware base-devel git networkmanager)
    [ "$LNOS_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs)
    
    # Add bootloader packages based on boot mode
    if [ "$LNOS_BOOTLOADER" = "grub" ]; then
        packages+=(grub)
        [ "$BOOT_MODE" = "uefi" ] && packages+=(efibootmgr)
    elif [ "$BOOT_MODE" = "uefi" ]; then
        # systemd-boot is part of systemd package, no additional packages needed
        :
    else
        # Force GRUB for BIOS systems even if user selected systemd-boot
        packages+=(grub)
        gum_warn "Forcing GRUB bootloader for BIOS/Legacy systems"
        LNOS_BOOTLOADER="grub"
    fi
    
    pacstrap -K /mnt "${packages[@]}"
    genfstab -U /mnt >> /mnt/etc/fstab
    
    gum_info "Base system installed successfully"
}

configure_system() {
    gum_info "Configuring system..."
    
    # Set timezone
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/${LNOS_TIMEZONE}" /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    # Set locale
    for ((i = 0; i < ${#LNOS_LOCALE_GEN_LIST[@]}; i++)); do 
        sed -i "s/^#${LNOS_LOCALE_GEN_LIST[$i]}/${LNOS_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"
    done
    arch-chroot /mnt locale-gen
    echo "LANG=${LNOS_LOCALE_LANG}.UTF-8" > /mnt/etc/locale.conf
    
    # Set console keymap
    echo "KEYMAP=$LNOS_VCONSOLE_KEYMAP" > /mnt/etc/vconsole.conf
    
    # Set hostname
    echo "LnOS" > /mnt/etc/hostname
    {
        echo "127.0.0.1 localhost.localdomain localhost"
        echo "::1 localhost.localdomain localhost"
    } > /mnt/etc/hosts
    
    # Configure mkinitcpio
    if [ "$LNOS_ENCRYPTION_ENABLED" = "true" ]; then
        sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect microcode modconf sd-vconsole block sd-encrypt filesystems fsck)/" /mnt/etc/mkinitcpio.conf
    fi
    arch-chroot /mnt mkinitcpio -P
    
    # Create user
    arch-chroot /mnt useradd -m -G wheel,audio,video,optical,storage -s /bin/bash "$LNOS_USERNAME"
    printf "%s\n%s" "${LNOS_PASSWORD}" "${LNOS_PASSWORD}" | arch-chroot /mnt passwd
    printf "%s\n%s" "${LNOS_PASSWORD}" "${LNOS_PASSWORD}" | arch-chroot /mnt passwd "$LNOS_USERNAME"
    
    # Configure sudoers
    sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers
    
    # Enable services
    arch-chroot /mnt systemctl enable NetworkManager
    
    gum_info "System configuration completed"
}

install_bootloader() {
    gum_info "Installing bootloader..."
    
    local kernel_args=('rw' 'init=/usr/lib/systemd/systemd')
    [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && kernel_args+=("rd.luks.name=$(blkid -s UUID -o value "${LNOS_ROOT_PARTITION}")=cryptroot" "root=/dev/mapper/cryptroot") || kernel_args+=("root=PARTUUID=$(lsblk -dno PARTUUID "${LNOS_ROOT_PARTITION}")")
    
    if [ "$LNOS_BOOTLOADER" = "grub" ]; then
        sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&${kernel_args[*]}," /mnt/etc/default/grub
        
        if [ "$BOOT_MODE" = "uefi" ]; then
            arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        else
            arch-chroot /mnt grub-install --target=i386-pc "$LNOS_DISK"
        fi
        
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    else
        # systemd-boot only works with UEFI
        if [ "$BOOT_MODE" = "bios" ]; then
            gum_warn "systemd-boot only supports UEFI. Falling back to GRUB for BIOS systems."
            # Install GRUB as fallback
            arch-chroot /mnt pacman -S --noconfirm grub
            sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&${kernel_args[*]}," /mnt/etc/default/grub
            arch-chroot /mnt grub-install --target=i386-pc "$LNOS_DISK"
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        else
            arch-chroot /mnt bootctl --esp-path=/boot install
            {
                echo 'default main.conf'
                echo 'console-mode auto'
                echo 'timeout 0'
                echo 'editor yes'
            } > /mnt/boot/loader/loader.conf
            
            {
                echo 'title   LnOS'
                echo 'linux   /vmlinuz-linux-hardened'
                echo 'initrd  /initramfs-linux-hardened.img'
                echo "options ${kernel_args[*]}"
            } > /mnt/boot/loader/entries/main.conf
        fi
    fi
    
    gum_info "Bootloader installed"
}

install_desktop_environment() {
    if [ "$LNOS_DESKTOP_ENABLED" = "true" ]; then
        gum_info "Installing desktop environment: $LNOS_DESKTOP_ENVIRONMENT"
        
        case "$LNOS_DESKTOP_ENVIRONMENT" in
            "Gnome")
                arch-chroot /mnt pacman -S --noconfirm xorg xorg-server gnome gdm
                arch-chroot /mnt systemctl enable gdm.service
                ;;
            "KDE")
                arch-chroot /mnt pacman -S --noconfirm xorg xorg-server plasma kde-applications sddm
                arch-chroot /mnt systemctl enable sddm.service
                ;;
            "Hyprland")
                arch-chroot /mnt pacman -S --noconfirm wayland hyprland noto-fonts kitty networkmanager
                # Create basic hyprland config
                mkdir -p "/mnt/home/${LNOS_USERNAME}/.config/hypr"
                echo 'exec-once = kitty' > "/mnt/home/${LNOS_USERNAME}/.config/hypr/hyprland.conf"
                arch-chroot /mnt chown -R "$LNOS_USERNAME":"$LNOS_USERNAME" "/home/${LNOS_USERNAME}/.config"
                ;;
            "DWM")
                gum_warn "DWM installation not fully implemented - installing minimal X11"
                arch-chroot /mnt pacman -S --noconfirm xorg xorg-server xterm
                ;;
        esac
        
        gum_info "Desktop environment installed"
    fi
}

install_graphics_driver() {
    if [ -n "$LNOS_DESKTOP_GRAPHICS_DRIVER" ] && [ "$LNOS_DESKTOP_GRAPHICS_DRIVER" != "none" ]; then
        gum_info "Installing graphics driver: $LNOS_DESKTOP_GRAPHICS_DRIVER"
        
        case "$LNOS_DESKTOP_GRAPHICS_DRIVER" in
            "mesa")
                arch-chroot /mnt pacman -S --noconfirm mesa mesa-utils
                [ "$LNOS_MULTILIB_ENABLED" = "true" ] && arch-chroot /mnt pacman -S --noconfirm lib32-mesa
                ;;
            "intel_i915")
                arch-chroot /mnt pacman -S --noconfirm mesa intel-media-driver vulkan-intel
                [ "$LNOS_MULTILIB_ENABLED" = "true" ] && arch-chroot /mnt pacman -S --noconfirm lib32-mesa lib32-vulkan-intel
                ;;
            "nvidia")
                arch-chroot /mnt pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
                [ "$LNOS_MULTILIB_ENABLED" = "true" ] && arch-chroot /mnt pacman -S --noconfirm lib32-nvidia-utils
                ;;
            "amd")
                arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-amdgpu vulkan-radeon
                [ "$LNOS_MULTILIB_ENABLED" = "true" ] && arch-chroot /mnt pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon
                ;;
            "ati")
                arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-ati
                [ "$LNOS_MULTILIB_ENABLED" = "true" ] && arch-chroot /mnt pacman -S --noconfirm lib32-mesa
                ;;
        esac
        
        gum_info "Graphics driver installed"
    fi
}

enable_multilib() {
    if [ "$LNOS_MULTILIB_ENABLED" = "true" ]; then
        gum_info "Enabling multilib repository..."
        sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
        arch-chroot /mnt pacman -Syyu --noconfirm
        gum_info "Multilib enabled"
    fi
}

install_aur_helper() {
    if [ -n "$LNOS_AUR_HELPER" ] && [ "$LNOS_AUR_HELPER" != "none" ]; then
        gum_info "Installing AUR helper: $LNOS_AUR_HELPER"
        
        # Temporarily allow passwordless sudo for user
        echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /mnt/etc/sudoers
        
        # Clone and build AUR helper
        local repo_url="https://aur.archlinux.org/${LNOS_AUR_HELPER}.git"
        arch-chroot /mnt /usr/bin/runuser -u "$LNOS_USERNAME" -- bash -c "
            cd /tmp
            git clone $repo_url
            cd $LNOS_AUR_HELPER
            makepkg -si --noconfirm
        "
        
        # Remove passwordless sudo
        sed -i '/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL$/d' /mnt/etc/sudoers
        
        gum_info "AUR helper installed"
    fi
}

install_packages() {
    gum_info "Installing packages based on profile: $LNOS_PACKAGE_PROFILE"
    
    case "$LNOS_PACKAGE_PROFILE" in
        "CSE")
            # Essential development tools for computer science students
            local packages=(
                # Development tools
                vim nano git wget curl
                # Programming languages and tools  
                gcc clang make cmake gdb valgrind
                python python-pip nodejs npm
                # Text editors and IDEs
                code # VSCode from official repos
                # System utilities
                htop tree unzip zip
                # Network tools
                openssh
            )
            
            arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"
            
            # Install AUR packages if AUR helper is available
            if [ -n "$LNOS_AUR_HELPER" ] && [ "$LNOS_AUR_HELPER" != "none" ]; then
                local aur_packages=(brave-bin)
                arch-chroot /mnt /usr/bin/runuser -u "$LNOS_USERNAME" -- "$LNOS_AUR_HELPER" -S --noconfirm "${aur_packages[@]}"
            fi
            ;;
        "Custom")
            gum_info "Custom package installation - user will be prompted"
            # This would be handled in the interactive part
            ;;
        "Minimal")
            local packages=(vim git wget curl openssh)
            arch-chroot /mnt pacman -S --noconfirm "${packages[@]}"
            ;;
    esac
    
    gum_info "Package installation completed"
}

copy_lnos_files() {
    gum_info "Copying LnOS files..."
    
    local lnos_repo="/root/LnOS"
    if [ -d "$lnos_repo" ]; then
        mkdir -p /mnt/root/LnOS
        cp -r "$lnos_repo"/* /mnt/root/LnOS/ 2>/dev/null || true
        
        # Set custom os-release
        if [ -f "/mnt/root/LnOS/files/os-release" ]; then
            cp /mnt/root/LnOS/files/os-release /mnt/etc/os-release
        fi
        
        gum_info "LnOS files copied"
    else
        gum_warn "LnOS repository not found at $lnos_repo"
    fi
}

finalize_installation() {
    gum_info "Finalizing installation..."
    
    # Copy installer files to user home
    cp -f "$SCRIPT_CONFIG" "/mnt/home/${LNOS_USERNAME}/installer.conf" 2>/dev/null || true
    cp -f "$SCRIPT_LOG" "/mnt/home/${LNOS_USERNAME}/installer.log" 2>/dev/null || true
    arch-chroot /mnt chown -R "$LNOS_USERNAME":"$LNOS_USERNAME" "/home/${LNOS_USERNAME}/" 2>/dev/null || true
    
    # Remove orphaned packages
    arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true'
    
    gum_info "Installation finalized"
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MAIN FUNCTION
# ////////////////////////////////////////////////////////////////////////////////////////////////////

main() {
    # Clear log file
    [ -f "$SCRIPT_LOG" ] && rm "$SCRIPT_LOG"
    
    # Check if gum is available
    if ! command -v gum &> /dev/null; then
        echo "Installing gum..."
        pacman -Sy --noconfirm gum
    fi
    
    # Check prerequisites
    [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && log_fail "Must be run from Arch ISO!" && exit 1
    
    # Print version to logfile
    log_info "LnOS Installer ${VERSION}"
    
    # Main configuration loop
    while true; do
        print_header "LnOS Installer"
        
        gum_white 'Please make sure you have:' && echo
        gum_white '• Backed up your important data'
        gum_white '• A stable internet connection'
        gum_white '• Secure Boot disabled'
        gum_white '• Boot Mode set to UEFI'
        echo
        
        # Network check
        if ! gum_confirm "Connect to internet? (Required for installation)"; then
            exit 1
        fi
        
        # Launch network configuration if needed
        if ! ping -c 1 google.com &>/dev/null; then
            gum_warn "No internet connection detected. Opening network manager..."
            nmtui
        fi
        
        # Core setup
        echo && gum_title "Core Setup"
        until select_username; do :; done
        until select_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_filesystem; do :; done
        until select_bootloader; do :; done
        until select_disk; do :; done
        
        # Desktop setup
        echo && gum_title "Desktop Setup"
        until select_enable_desktop_environment; do :; done
        until select_enable_desktop_driver; do :; done
        
        # Feature setup
        echo && gum_title "Feature Setup"
        until select_enable_encryption; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_package_profile; do :; done
        
        # Confirm installation
        echo && gum_title "Installation Summary"
        gum_info "Configuration completed successfully"
        
        if gum_confirm "Start LnOS Installation?"; then
            break
        fi
    done
    
    # Start installation
    gum_title "LnOS Installation"
    local start_time=$SECONDS
    
    # Installation steps
    install_base_system
    configure_system
    install_bootloader
    enable_multilib
    install_desktop_environment
    install_graphics_driver
    install_aur_helper
    install_packages
    copy_lnos_files
    finalize_installation
    
    # Calculate duration
    local duration=$((SECONDS - start_time))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))
    
    gum_green --bold "Installation completed in ${duration_min} minutes and ${duration_sec} seconds"
    log_info "Installation completed in ${duration_min} minutes and ${duration_sec} seconds"
    
    # Post-installation options
    if gum_confirm "Reboot to LnOS now?"; then
        umount -R /mnt 2>/dev/null || true
        [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot 2>/dev/null || true
        reboot
    else
        gum_warn "LnOS is installed but not rebooted. System is mounted at /mnt"
        if gum_confirm "Unmount LnOS from /mnt?"; then
            umount -R /mnt 2>/dev/null || true
            [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot 2>/dev/null || true
        fi
    fi
    
    gum_info "Installation complete. You may now reboot manually."
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ARGUMENT HANDLING AND SCRIPT START
# ////////////////////////////////////////////////////////////////////////////////////////////////////

if [ "$1" = "--target=x86_64" ]; then
    main
elif [ "$1" = "--target=aarch64" ]; then
    gum_fail "ARM64 support not yet implemented"
    exit 1
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    gum_style \
        --foreground 255 --border-foreground 130 --border double \
        --width 80 --margin "1 2" --padding "2 4" \
        'LnOS Installer Help:' \
        'Usage: ./LnOS-installer.sh --target=[x86_64 | aarch64]' \
        '' \
        'Options:' \
        '  --target=x86_64    Install for x86_64 architecture' \
        '  --target=aarch64   Install for ARM64 architecture (WIP)' \
        '  -h, --help         Show this help message' \
        '  --version          Show version information' \
        '' \
        'This installer sets up Arch Linux with LnOS customizations.'
    exit 0
else
    gum_style \
        --foreground 255 --border-foreground 1 --border double \
        --width 80 --margin "1 2" --padding "2 4" \
        'Error: Invalid or missing arguments' \
        '' \
        'Usage: ./LnOS-installer.sh --target=[x86_64 | aarch64]' \
        'Use -h or --help for more information'
    exit 1
fi