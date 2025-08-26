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
# @brief Installs Arch linux and 
# @author Betim-Hodza, Ric3y
# @date 2025
#

set -e

# GLOBALS
VERSION='1.0.0'
SCRIPT_LOG="./installer.log"

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


# required vars
LNOS_USERNAME="null"
LNOS_USERPASS="null"
LNOS_ROOTPASS="null"
LNOS_TIMEZONE="null"
LNOS_LOCALE_LANG="null"
LNOS_KEYBOARD_KEYMAP="null"
LNOS_DISK="null"
LNOS_ENCRYPTION="null"
LNOS_DESKTOP_GRAPHICS_DRIVER="null"
LNOS_AUR_HELPER="null"



# ----------------------------- GUM WRAPPER ----------------------------- #

# Gum wrapper
gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_FOREGROUND" --selected.background "$COLOR_FOREGROUND" --selected.foreground "$COLOR_BACKGROUND" --unselected.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --cursor.foreground "$COLOR_FOREGROUND" --prompt.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_FOREGROUND" --cursor.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_FOREGROUND" --indicator.foreground "$COLOR_FOREGROUND" --match.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_write() { gum write --prompt "> " --show-cursor-line --char-limit 0 --cursor.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_FOREGROUND" --spinner.foreground "$COLOR_FOREGROUND" "${@}"; }


# Gum colors (https://github.com/muesli/termenv?tab=readme-ov-file#color-chart)
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

# ----------------------------- LOGGING WRAPPER ----------------------------- #

write_log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | arch-os | ${*}" >>"$SCRIPT_LOG"; }
log_info() { write_log "INFO | ${*}"; }
log_warn() { write_log "WARN | ${*}"; }
log_fail() { write_log "FAIL | ${*}"; }
log_head() { write_log "HEAD | ${*}"; }
log_proc() { write_log "PROC | ${*}"; }
log_prop() { write_log "PROP | ${*}"; }

# ----------------------------- Helper Functions ----------------------------- #

gum_header() 
{
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

print_filled_space() 
{
    local total="$1" && local text="$2" && local length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    local padding=$((total - length)) && printf '%s%*s\n' "$text" "$padding" ""
}


# Presets for the user to fill out

get_username() 
{
    # prompt for user
    local username

    while true; do
        username=$(gum input --prompt "Enter username: ")
        if [ -z "$username" ]; then
            gum_error "Error: Username cannot be empty."
        else
            break
        fi
    done

    LNOS_USERNAME=$username
    gum_property "Username" "$LNOS_USERNAME"
    return 0
}

get_password() 
{ 
    local rtpass
    local rtpass_verify

    while true; do
        rtpass=$(gum input --password --placeholder="Enter root password: ")
        rtpass_verify=$(gum input --password --placeholder="Enter root password again: ")
        if [ "$rtpass" = "$rtpass_verify" ]; then
            echo "root:$rtpass" | chpasswd
            break
        else
            gum confirm "Passwords do not match. Try again?" || exit 1
        fi
    done
    LNOS_ROOTPASS=$rtpass

    local uspass
    local uspass_verify

    # Get users password
    while true; do
        uspass=$(gum input --password --placeholder="Enter password for $username: ")
        uspass_verify=$(gum input --password --placeholder="Enter password for $username again: ")
        if [ "$uspass" = "$uspass_verify" ]; then
            echo "$username:$uspass" | chpasswd
            break
        else
            gum confirm "Passwords do not match. Try again?" || exit 1
        fi
    done

    LNOS_USERPASS=$uspass
    
    return 0
}

get_timezone() 
{

    local tz_auto user_input
    tz_auto="$(curl -s http://ip-api.com/line?fields=timezone)"
    user_input=$(gum_input --header "+ Enter Timezone (auto-detected)" --value "$tz_auto") || exit 1
    [ -z "$user_input" ] && return 1 # Check if new value is null
    if [ ! -f "/usr/share/zoneinfo/${user_input}" ]; then
        gum_confirm --affirmative="Ok" --negative="" "Timezone '${user_input}' is not supported"
        return 1
    fi
    LNOS_TIMEZONE="$user_input" && properties_generate # Set property and generate properties file

    gum_property "Timezone" "$ARCH_OS_TIMEZONE"
    return 0
}


# shellcheck disable=SC2001
select_language() 
{
    
    local user_input items options filter
    # Fetch available options (list all from /usr/share/i18n/locales and check if entry exists in /etc/locale.gen)
    mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@") # Create array without @ files
    # Add only available locales (!!! intense command !!!)
    options=() && for item in "${items[@]}"; do grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item"); done
    # shellcheck disable=SC2002
    [ -r /root/.zsh_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
    # Select locale
    user_input=$(gum_filter --value="$filter" --header "+ Choose Language" "${options[@]}") || exit 1
    [ -z "$user_input" ] && return 1  # Check if new value is null
    LNOS_LOCALE_LANG="$user_input" # Set property
    # Set locale.gen properties (auto generate LNOS_LOCALE_GEN_LIST)
    LNOS_LOCALE_GEN_LIST=() && while read -r locale_entry; do
        LNOS_LOCALE_GEN_LIST+=("$locale_entry")
        # Remove leading # from matched lang in /etc/locale.gen and add entry to array
    done < <(sed "/^#${LNOS_LOCALE_LANG}/s/^#//" /etc/locale.gen | grep "$LNOS_LOCALE_LANG")
    # Add en_US fallback (every language) if not already exists in list
    [[ "${LNOS_LOCALE_GEN_LIST[*]}" != *'en_US.UTF-8 UTF-8'* ]] && LNOS_LOCALE_GEN_LIST+=('en_US.UTF-8 UTF-8')
    properties_generate # Generate properties file (for LNOS_LOCALE_LANG & LNOS_LOCALE_GEN_LIST)

    gum_property "Language" "$LNOS_LOCALE_LANG"
    return 0
}


select_keyboard() 
{
    
    local user_input items options filter
    mapfile -t items < <(command localectl list-keymaps)
    options=() && for item in "${items[@]}"; do options+=("$item"); done
    # shellcheck disable=SC2002
    [ -r /root/.bash_history ] && filter=$(cat /root/.zsh_history | grep 'loadkeys' | head -n 2 | tail -n 1 | cut -d';' -f2 | cut -d' ' -f2 | cut -d'-' -f1)
    user_input=$(gum_filter --value="$filter" --header "+ Choose Keyboard" "${options[@]}") || exit 1
    [ -z "$user_input" ] && return 1                             # Check if new value is null
    LNOS_KEYBOARD_KEYMAP="$user_input"

    gum_property "Keyboard" "$LNOS_KEYBOARD_KEYMAP"
    return 0
}

select_disk() 
{

    # Prompt user to select a disk
    local DISK_SELECTION DISK
    DISK_SELECTION=$(lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E 'disk' | grep -E 'nvme|sd[a-z]|mmcblk[0-9]' | gum choose --header "Select the disk to install on (or Ctrl-C to exit):")
    DISK="/dev/$(echo "$DISK_SELECTION" | awk '{print $1}')"

    if [ -z "$DISK" ]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 1 "Error: No disk selected."
        log_fail "No Disk Selected"
        exit 1
    fi

    LNOS_DISK=$DISK
    
    gum_property "Disk" "$LNOS_DISK"
    return 0
}

select_enable_encryption() 
{
    gum_confirm "Enable Disk Encryption?"
    local user_confirm=$?
    [ $user_confirm = 130 ] && {
        return 1
    }
    local user_input
    [ $user_confirm = 1 ] && user_input="false"
    [ $user_confirm = 0 ] && user_input="true"
    LNOS_ENCRYPTION="$user_input" 
    
    gum_property "Disk Encryption" "$LNOS_ENCRYPTION"
    return 0
}


choose_desktop_environment() 
{
    # Desktop Environment Installation
    local DE_CHOICE
    while true; do
		DE_CHOICE=$(gum choose --header "Choose your Desktop Environment (DE):" \
            "Gnome(Good for beginners, similar to Mac)" \
            "KDE(Good for beginners, similar to Windows)" \
            "Hyprland(Tiling WM, basic dotfiles but requires more DIY)" \
            "DWM(Similar to Hyprland)" \
            "TTY (No install required)")
            
		if [[ "$DE_CHOICE" == "TTY (No install required)" ]]; then
			echo "TTY is preinstalled !"
            break
        fi
        
        gum confirm "You selected: $DE_CHOICE. Proceed with installation?" && break
        gum_echo "Returning to selection menu..."
    done

    LNOS_DE=$DE_CHOICE
    return 0
}

select_enable_desktop_driver() 
{
    if [ -z "$LNOS_DESKTOP_GRAPHICS_DRIVER" ] || [ "$LNOS_DESKTOP_GRAPHICS_DRIVER" = "null" ]; then
        local user_input options
        options=("mesa" "intel_i915" "nvidia" "amd" "ati")
        user_input=$(gum_choose --header "+ Choose Desktop Graphics Driver (default: mesa)" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$user_input" ] && return 1                                     # Check if new value is null
        LNOS_DESKTOP_GRAPHICS_DRIVER="$user_input"
    fi

    gum_property "Desktop Graphics Driver" "$LNOS_DESKTOP_GRAPHICS_DRIVER"
    
    return 0
}


select_enable_aur() 
{
    local user_input options
    options=("paru" "paru-bin" "paru-git" "none")
    user_input=$(gum_choose --header "+ Choose AUR Helper (default: paru)" "${options[@]}") || trap_gum_exit_confirm
    [ -z "$user_input" ] && return 1                        # Check if new value is null
    LNOS_AUR_HELPER="$user_input" 
    
    gum_property "AUR Helper" "$LNOS_AUR_HELPER"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_multilib() {
    if [ -z "$ARCH_OS_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32 Bit Support?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_MULTILIB_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "32 Bit Support" "$ARCH_OS_MULTILIB_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_housekeeping() {
    if [ -z "$ARCH_OS_HOUSEKEEPING_ENABLED" ]; then
        gum_confirm "Enable Housekeeping?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_HOUSEKEEPING_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Housekeeping" "$ARCH_OS_HOUSEKEEPING_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_shell_enhancement() {
    if [ -z "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" ]; then
        gum_confirm "Enable Shell Enhancement?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_SHELL_ENHANCEMENT_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Shell Enhancement" "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED"
    return 0
}

# ---------------------------------------------------------------------------------------------------

select_enable_manager() 
{
    if [ -z "$ARCH_OS_MANAGER_ENABLED" ]; then
        gum_confirm "Enable Arch OS Manager?"
        local user_confirm=$?
        [ $user_confirm = 130 ] && {
            trap_gum_exit_confirm
            return 1
        }
        local user_input
        [ $user_confirm = 1 ] && user_input="false"
        [ $user_confirm = 0 ] && user_input="true"
        ARCH_OS_MANAGER_ENABLED="$user_input" && properties_generate # Set value and generate properties file
    fi
    gum_property "Arch OS Manager" "$ARCH_OS_MANAGER_ENABLED"
    return 0
}


# logging functions (only for 1 line)
gum_echo()
{
    gum style --border normal --margin "1 2" --padding "2 4" --border-foreground 130 "$@"
}
gum_error()
{
    gum style --border double --margin "1 2" --padding "2 4" --border-foreground 1 "$@"
}
gum_complete()
{
    gum style --border normal --margin "1 2" --padding "2 4" --border-foreground 158 "$@"
}


# Combines part 2 into part 1 script as to make installation easier
# sets up the desktop environment and packages
setup_desktop_and_packages()
{
    local username="$1" # Pass username as parameter

    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Hello, there. Welcome to LnOs auto setup script"

    # Install essential packages 
  	gum spin --spinner dot --title "Installing developer tools needed for packages" -- pacman -S --noconfirm base-devel git wget networkmanager btrfs-progs openssh git dhcpcd networkmanager vi vim iw netcl wget curl xdg-user-dirs
    
    # Enable network services
    systemctl enable dhcpcd
    systemctl enable NetworkManager

    # Desktop Environment Installation
    while true; do
		DE_CHOICE=$(gum choose --header "Choose your Desktop Environment (DE):" \
            "Gnome(Good for beginners, similar to Mac)" \
            "KDE(Good for beginners, similar to Windows)" \
            "Hyprland(Tiling WM, basic dotfiles but requires more DIY)" \
            "DWM(Similar to Hyprland)" \
            "TTY (No install required)")
            
		if [[ "$DE_CHOICE" == "TTY (No install required)" ]]; then
			echo "TTY is preinstalled !"
            break
        fi
        
        gum confirm "You selected: $DE_CHOICE. Proceed with installation?" && break
        gum_echo "Returning to selection menu..."
    done

    case "$DE_CHOICE" in
        "Gnome(Good for beginners, similar to Mac)")
            gum_echo "Installing Gnome..."
            pacman -S --noconfirm xorg xorg-server gnome gdm
            systemctl enable gdm.service
            ;;
				"KDE(Good for beginners, similar to Windows)")
            gum_echo "Installing KDE..."
            pacman -S --noconfirm xorg xorg-server plasma kde-applications sddm
            systemctl enable sddm.service
            ;;
        "Hyprland(Tiling WM, basic dotfiles but requires more DIY)")
            gum_echo "Installing Hyprland..."
            pacman -S --noconfirm wayland hyprland noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra kitty networkmanager

            # call and run JaKooLit's arch hyprland install
            gum_echo "Downloading JaKooLit's Hyprland, please run the script after installation!"
            sleep 2
            wget https://raw.githubusercontent.com/JaKooLit/Arch-Hyprland/main/auto-install.sh
        
            ;;
		"DWM(Similar to Hyprland)")
            gum_echo "Installing DWM..."
			gum_echo "[WARNING] DWM requires more work in the future, for now this option doesn't do anything"
            #pacman -S --noconfirm uwsm
            #systemctl enable lightdm.service
            ;;
    esac

    # Package Installation
    while true; do
        THEME=$(gum choose --header "Choose your installation profile:" "CSE" "Custom")
        gum confirm "You selected: $THEME. Proceed with installation?" && break
    done

    case "$THEME" in
        "CSE")
            # ensure we have the right packages
            PACMAN_PACKAGES=$(cat /root/LnOS/pacman_packages/CSE_packages.txt)
            if [ ! -f "/root/LnOS/pacman_packages/CSE_packages.txt" ]; then
                gum_error  "Error: CSE_packages.txt not found in /root/LnOS/pacman_packages/. ."
            else
                # checking if cloned
                if $CLONED ; then
                    PACMAN_PACKAGES=$(cat /root/LnOS/scripts/pacman_packages/CSE_packages.txt)
                else
                    gum_error "Error: CSE_packages.txt not found in /root/LnOS/scripts/pacman_packages/."
                    exit 1
                fi
            fi
			# Choose packages from CSE list (PACMAN)
            PACMAN_PACKAGES=$(cat /root/LnOS/pacman_packages/CSE_packages.txt)
            gum spin --spinner dot --title "Installing pacman packages..." -- pacman -S --noconfirm "$PACMAN_PACKAGES" 

            # AUR will most likely be short with a few packages
            # webcord, brave are the big ones that come to mind
            # the reason is id like to teach users how to properly use aur
            gum style \
                --foreground 255 --border-foreground 130 --border double \
                --width 100 --margin "1 2" --padding "2 4" \
                'AUR (Arch User Repository) is less secure because its not maintained by Arch.' \
                'LnOS Maintainers picked these packages because their releases were signed with PGP keys' \
            
            gum confirm "Will you proceed to download AUR packages ? (i.e. brave, webcord)" || return
            
            # clone paru and build
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si
            # exit and clean up paru
            cd ..
            rm -rf paru


            gum_echo "Please review the packages you're about to download"
            # check if we have the right packages
            PARU_PACKAGES=$(cat /root/LnOS/paru_packages/paru_packages.txt)
            if [ ! -f "/root/LnOS/paru_packages/paru_packages.txt" ]; then
                gum_error  "Error: CSE_packages.txt not found in /root/LnOS/paru_packages/. ."
            else
                # checking if cloned
                if $CLONED ; then
                    PARU_PACKAGES=$(cat /root/LnOS/scripts/paru_packages/paru_packages.txt)
                else
                    gum_error "Error: CSE_packages.txt not found in /root/LnOS/scripts/paru_packages/."
                    exit 1
                fi
            fi
            paru -S "$PARU_PACKAGES"


            ;;
        "Custom")
            PACMAN_PACKAGES=$(gum input --header "Enter the pacman packages you want (space-separated):")
            if [ -n "$PACMAN_PACKAGES" ]; then
                gum spin --spinner dot --title "Installing pacman packages..." -- pacman -S --noconfirm "$PACMAN_PACKAGES"
            fi

            gum_echo "AUR (Arch User Repository) is less secure because it's not maintained by Arch. LnOS Maintainers picked these packages because their releases were signed with PGP keys"
            gum confirm "Will you proceed to download AUR packages ? (i.e. brave, webcord)" || return
            
            # clone paru and build
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si
            # exit and clean up paru
            cd ..
            rm -rf paru


            gum_echo "Please enter and review the packages you're about to download"
            PARU_PACKAGES=$(gum input --header "Enter the paru packages you want (space-seperated):")
            if [ -n "$PARU_PACKAGES" ]; then
                paru -S "$PARU_PACKAGES"
            fi
            
            ;;
    esac
}

# Function to configure the system (common for both architectures)
configure_system()
{
    # install gum again for pretty format
    pacman -Sy --noconfirm gum

    # Set timezone
    ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
    hwclock --systohc

    # Set locale
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # Set hostname
    echo "LnOs" > /etc/hostname

    # Set hosts file
    echo "127.0.0.1 localhost" > /etc/hosts
    echo "::1 localhost" >> /etc/hosts

    # Add DNS servers
    echo "nameserver 1.1.1.1" > /etc/resolv.conf # Cloudflare

    # Configure /etc/os-release to be ours
    cat /root/LnOS/os-release > /etc/os-release

    # Set root password
    while true; do
        rtpass=$(gum input --password --placeholder="Enter root password: ")
        rtpass_verify=$(gum input --password --placeholder="Enter root password again: ")
        if [ "$rtpass" = "$rtpass_verify" ]; then
            echo "root:$rtpass" | chpasswd
            break
        else
            gum confirm "Passwords do not match. Try again?" || exit 1
        fi
    done

    # Create normal user
    while true; do
        username=$(gum input --prompt "Enter username: ")
        if [ -z "$username" ]; then
            gum_error "Error: Username cannot be empty."
        else
            break
        fi
    done

    # set groups to user
    useradd -m -G audio,video,input,wheel,sys,log,rfkill,lp,adm -s /bin/bash "$username"

    # Get users password
    while true; do
        uspass=$(gum input --password --placeholder="Enter password for $username: ")
        uspass_verify=$(gum input --password --placeholder="Enter password for $username again: ")
        if [ "$uspass" = "$uspass_verify" ]; then
            echo "$username:$uspass" | chpasswd
            break
        else
            gum confirm "Passwords do not match. Try again?" || exit 1
        fi
    done

    # Configure sudoers for wheel group
    pacman -S --noconfirm sudo
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
    chmod 440 /etc/sudoers.d/10-wheel

    # Update 
    pacman -Syu --noconfirm

    
    # setup the desktop environment
    setup_desktop_and_packages "$username"

	gum_echo "LnOS Basic DE/Package install completed!"

    exit 0
}

# Prompts the user and parititions the users selected disk from what we can find
# This makes 2-3 parititions: BOOT, SWAP (if < 15GB ram), BTRFS Linux filesystem
# * Automatically detects UEFI or BIOS, this will mount the parititions as well
setup_drive()
{
    # Prompt user to select a disk
    DISK_SELECTION=$(lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E 'disk' | grep -E 'nvme|sd[a-z]|mmcblk[0-9]' | gum choose --header "Select the disk to install on (or Ctrl-C to exit):")
    DISK="/dev/$(echo "$DISK_SELECTION" | awk '{print $1}')"

    if [ -z "$DISK" ]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 1 "Error: No disk selected."
        exit 1
    fi

    # Confirm disk selection
    if ! gum confirm "WARNING: This will erase all data on $DISK. Continue?"; then
        exit 1
    fi

    # check what type of drive
    if grep -q "nvme" <<< "$DISK"; then
        NVME=1
    else
        NVME=0
    fi   

    # Detect UEFI or BIOS
    if [ -d /sys/firmware/efi ]; then
        UEFI=1
    else
        UEFI=0
    fi

    # Check RAM and decide swap size
    RAM_GB=$(awk '/MemTotal/ {print int($2 / 1024 / 1024)}' /proc/meminfo)
    if [ "$RAM_GB" -lt 15 ]; then
        SWAP_SIZE=4096  # 4 GiB
        gum_echo "System has ${RAM_GB}GB RAM. Creating 4 GiB swap partition"
    else
        SWAP_SIZE=0
        gum_echo "System has ${RAM_GB}GB RAM."
    fi

    # Partition the disk UEFI and DOS compatible
    if [ $UEFI -eq 1 ]; then
        parted "$DISK" mklabel gpt
        parted "$DISK" mkpart ESP fat32 1MiB 513MiB
        parted "$DISK" set 1 esp on        
        if [ $SWAP_SIZE -gt 0 ]; then
            parted "$DISK" mkpart swap linux-swap 513MiB $((513 + SWAP_SIZE))MiB
            parted "$DISK" mkpart root btrfs $((513 + SWAP_SIZE))MiB 100%
            SWAP_PART=2
            ROOT_PART=3
        else
            parted "$DISK" mkpart root btrfs 513MiB 100%
            ROOT_PART=2
        fi
        BOOT_PART=1
    else
        parted "$DISK" mklabel msdos
        if [ $SWAP_SIZE -gt 0 ]; then
            parted "$DISK" mkpart primary linux-swap 1MiB ${SWAP_SIZE}MiB
            parted "$DISK" mkpart primary btrfs ${SWAP_SIZE}MiB 100%
            parted "$DISK" set 2 boot on
            SWAP_PART=1
            ROOT_PART=2
        else
            parted "$DISK" mkpart primary btrfs 1MiB 100%
            parted "$DISK" set 1 boot on
            ROOT_PART=1
        fi
    fi

    # Format partitions 
    if [ $UEFI -eq 1 ]; then
        # account for NVME drives seperating paritions with p
        if [ $NVME -eq 1 ]; then
            mkfs.fat -F32 "${DISK}p${BOOT_PART}"  
        else
            mkfs.fat -F32 "${DISK}${BOOT_PART}"
        fi
    fi
    if [ $SWAP_SIZE -gt 0 ]; then
        # account for NVME 
        if [ $NVME -eq 1 ]; then
            mkswap "${DISK}p${SWAP_PART}" 
        else
            mkswap "${DISK}${SWAP_PART}" 
        fi
    fi
    
    if [ $NVME -eq 1 ];then
        mkfs.btrfs -f "${DISK}p${ROOT_PART}"  
    else
        mkfs.btrfs -f "${DISK}${ROOT_PART}"  
    fi

    # Mount partitions
    if [ $NVME -eq 1 ]; then
        mount "${DISK}p${ROOT_PART}" /mnt
    else
        mount "${DISK}${ROOT_PART}" /mnt
    fi

    if [ $UEFI -eq 1 ]; then
        if [ $NVME -eq 1 ]; then
            mkdir /mnt/boot
            mount "${DISK}p${BOOT_PART}" /mnt/boot
        else
            mkdir /mnt/boot
            mount "${DISK}${BOOT_PART}" /mnt/boot
        fi
    fi
}

# Copies the repo's files into the chroot, this is for it to be permenant on reboot
copy_lnos_files()
{
	LNOS_REPO="/root/LnOS"
	if [ ! -d "$LNOS_REPO" ]; then
		gum style --border normal --margin "1" --padding "1" --border-foreground 1 "Error: LnOS repository not found at $LNOS_REPO. Please clone it before running the installer."
		exit 1
	fi
	mkdir -p /mnt/root/LnOS
	cp -r "$LNOS_REPO/scripts/pacman_packages" /mnt/root/LnOS/
    cp -r "$LNOS_REPO/scripts/files/os-release" /mnt/root/LnOS/
	cp "$LNOS_REPO/scripts/LnOS-auto-setup.sh" /mnt/root/LnOS/ 2>/dev/null || true # Optional, ignore if not present
	# Optionally copy documentation files
	cp -r "$LNOS_REPO/docs" /mnt/root/LnOS/ 2>/dev/null || true
	cp "$LNOS_REPO/README.md" "$LNOS_REPO/LICENSE" "$LNOS_REPO/AUTHORS" "$LNOS_REPO/SUMMARY.md" "$LNOS_REPO/TODO.md" /mnt/root/LnOS/ 2>/dev/null || true

}

# Function to install on x86_64 (runs from Arch live ISO)
install_x86_64()
{
	# prompt and paritition the drives
	setup_drive

    # Install base system (zen kernel may be cool, but after some research about hardening, the linux hardened kernel makes 10x more sense for students and will be the default)
    gum_echo "Installing base system, will take some time (Grab a coffee)"
    pacstrap /mnt base linux-hardened linux-firmware btrfs-progs base-devel git wget networkmanager btrfs-progs openssh git dhcpcd networkmanager vi vim iw wget curl xdg-user-dirs fastfetch

    gum_echo "Base system install done!"

	# Copy LnOS repository files to target system (in order for the spin to happen you have to startup a new bash instance)
	gum spin --spinner dot --title "copying LnOS files" -- bash -c "$(declare -f copy_lnos_files); copy_lnos_files"

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab

	# Chroot and configure the OS,
	# before we enter chroot we also need to declare
	# these bash functions as well so they can run
    arch-chroot /mnt /bin/bash -c "$(declare -f configure_system setup_desktop_and_packages gum_echo gum_error gum_complete); configure_system"

    # Cleanup and Install GRUB
    if [ $UEFI -eq 1 ]; then
        arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        arch-chroot /mnt pacman -S --noconfirm grub
        arch-chroot /mnt grub-install --target=i386-pc $DISK
    fi
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    # Unmount and reboot
    umount -R /mnt
    for i in {10..1}; do
        gum style --foreground 212 "Installation complete. Rebooting in $i seconds..."
        sleep 1
    done
    reboot
}

# Function to prepare ARM SD card (for Raspberry Pi, run from existing Linux system)
prepare_arm()
{
    # Prompt for SD card device using GUM
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    DISK=$(lsblk -d -o NAME | grep -E 'sd[a-z]|mmcblk[0-9]' | gum choose --header "Select the SD card device to prepare (e.g., /dev/mmcblk0):" | sed 's|^|/dev/|')

    if [ -z "$DISK" ]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 1 "Error: No disk selected."
        exit 1
    fi

    # Confirm disk selection
    if ! gum confirm "WARNING: This will erase all data on $DISK. Continue?"; then
        exit 1
    fi

    # Partition the SD card
    parted "$DISK" mklabel msdos
    parted "$DISK" mkpart primary fat32 1MiB 257MiB
    parted "$DISK" mkpart primary btrfs 257MiB 100%

    # Format partitions
    mkfs.fat -F32 "${DISK}p1"
    mkfs.btrfs "${DISK}p2"

    # Mount partitions
    mount "${DISK}p2" /mnt
    mkdir /mnt/boot
    mount "${DISK}p1" /mnt/boot

    # Download and extract Arch Linux ARM tarball (Raspberry Pi 4 example)
    wget http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-4-ext4-root.tar.gz -O /tmp/archlinuxarm.tar.gz
    tar -xzf /tmp/archlinuxarm.tar.gz -C /mnt

    # Copy LnOS repository files to target system
    LNOS_REPO="/root/LnOS"
    if [ ! -d "$LNOS_REPO" ]; then
        gum style --border normal --margin "1" --padding "1" --border-foreground 1 "Error: LnOS repository not found at $LNOS_REPO. Please clone it before running the installer."
        exit 1
    fi
    mkdir -p /mnt/root/LnOS
    cp -r "$LNOS_REPO/scripts/pacman_packages" /mnt/root/LnOS/
    cp "$LNOS_REPO/scripts/LnOS-auto-setup.sh" /mnt/root/LnOS/ 2>/dev/null || true # Optional, ignore if not present
    # Optionally copy documentation files
    cp -r "$LNOS_REPO/docs" /mnt/root/LnOS/ 2>/dev/null || true
    cp "$LNOS_REPO/README.md" "$LNOS_REPO/LICENSE" "$LNOS_REPO/AUTHORS" "$LNOS_REPO/SUMMARY.md" "$LNOS_REPO/TODO.md" /mnt/root/LnOS/ 2>/dev/null || true

    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "Copied LnOS repository files to /mnt/root/LnOS"

    # Install qemu-user-static if not present
    if ! command -v qemu-arm-static &> /dev/null; then
        pacman -S --noconfirm qemu-user-static
    fi

    # Chroot and configure
    arch-chroot /mnt /bin/bash -c "$(declare -f configure_system setup_desktop_and_packages); configure_system"

    # Unmount
    umount -R /mnt
    gum style --border normal --margin "1" --padding "1" --border-foreground 212 "SD card preparation complete. Insert into Raspberry Pi and boot."
}

# Main logic

# Prechecks for users that are cloning the install script to run in the archinstaller iso and not the lnos iso
# the package paths are different on clones
if cat /root/LnOS/pacman_packages/CSE_packages.txt | grep git -q ; then
    #echo "Detected cloned install, setting cloned to 1"
    CLONED=1
else
CLONED=0
fi

# clear log
[ -f "$SCRIPT_LOG" ] && rm "$SCRIPT_LOG"

# init pacman key
pacman-key --init
# check gum and network manager
if ! command -v gum &> /dev/null; then
    echo "Installing gum..."
    pacman -Sy --noconfirm gum
fi
if ! command -v nmtui &> /dev/null; then
    echo "Installing network manager..."
    pacman -Sy --noconfirm networkmanager
    NetworkManager
fi

# Make user connect to internet
# make it a bit simpler and just force nmtui on them
echo "Please connect to the internet"

gum_echo "Connect to the internet? (Installer won't work without it)"
gum confirm || exit

nmtui

# user config
while (true); do

    gum_header "LnOS Installer"
    gum_white 'Please make sure you have: ' && echo
    gum_white '• Backed up your important data'
    gum_white '• A stable internet connection'
    gum_white '• Secure Boot disabled'

    echo #\n

    # Selectors
    echo && gum_title "Core Setup"
    until select_username; do :; done
    until select_password; do :; done
    until select_timezone; do :; done
    until select_language; do :; done
    until select_keyboard; do :; done
    until select_filesystem; do :; done
    until select_bootloader; do :; done
    until select_disk; do :; done
    echo && gum_title "Desktop Setup"
    until select_enable_desktop_environment; do :; done
    until select_enable_desktop_driver; do :; done
    until select_enable_desktop_slim; do :; done
    until select_enable_desktop_keyboard; do :; done
    echo && gum_title "Feature Setup"
    until select_enable_encryption; do :; done
    until select_enable_core_tweaks; do :; done
    until select_enable_bootsplash; do :; done
    until select_enable_multilib; do :; done
    until select_enable_aur; do :; done
    until select_enable_housekeeping; do :; done
    until select_enable_shell_enhancement; do :; done
    until select_enable_manager; do :; done

done



if [ "$1" = "--target=x86_64" ]; then
  install_x86_64
elif [ "$1" = "--target=aarch64" ]; then
  gum_error "WIP: Please come back later!"
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then

	gum style \
		--foreground 255 --border-foreground 130 --border double \
		--width 100 --margin "1 2" --padding "2 4" \
		'Help Menu:' \
		'Usage: installer.sh --target=[x86_64 | aarch64] or -h' \
		'[--target]: sets the installer"s target architecture (for the cpu)' \
		'Please check your cpu architecture by running: uname -m ' \
		'[-h] or [--help]: Brings up this help menu'

	exit 0
else
	gum style \
		--foreground 255 --border-foreground 1 --border double \
		--width 100 --margin "1 2" --padding "2 4" \
		'Usage: installer.sh --target=[x86_64 | aarch64] or -h' \
		'[--target]: sets the installer"s target architecture (for the cpu)' \
		'Please check your cpu architecture by running: uname -m ' \
		'[-h] or [--help]: Brings up this help menu'
	exit 1
fi
