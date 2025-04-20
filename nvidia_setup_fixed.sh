#!/bin/bash

# Color definitions
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Function to echo with color
echoc() {
    echo -e "${1}${2}${RESET}"
}

# Function to check command success
check_success() {
    if [ $? -ne 0 ]; then
        echoc $RED "!!! ERROR: $1 failed."
        exit 1
    fi
    echoc $GREEN "+++ SUCCESS: $1 completed."
}

echoc $CYAN "===== Starting Nvidia Driver Setup Script ====="

# START ### SYSTEM UPDATE ###
echoc $YELLOW ">>> Updating package lists and upgrading system..."
sudo apt update && sudo apt upgrade -y
check_success "System update and upgrade"
# FINISH ### SYSTEM UPDATE ###

# START ### INSTALL BUILD ESSENTIALS ###
echoc $YELLOW ">>> Installing build-essential and linux-headers..."
# Install headers for the *currently running* kernel
sudo apt install -y build-essential linux-headers-$(uname -r)
check_success "Installation of build-essential and kernel headers"
# FINISH ### INSTALL BUILD ESSENTIALS ###

# START ### BLACKLIST NOUVEAU ###
echoc $YELLOW ">>> Blacklisting the Nouveau driver..."
BLACKLIST_FILE="/etc/modprobe.d/blacklist-nvidia-nouveau.conf"
if [ ! -f "$BLACKLIST_FILE" ] || ! grep -q "blacklist nouveau" "$BLACKLIST_FILE"; then
    echoc $WHITE "--- Creating/updating $BLACKLIST_FILE..."
    echo "blacklist nouveau" | sudo tee -a "$BLACKLIST_FILE" > /dev/null
    echo "options nouveau modeset=0" | sudo tee -a "$BLACKLIST_FILE" > /dev/null
    check_success "Blacklisting Nouveau driver"
else
    echoc $GREEN "--- Nouveau already blacklisted in $BLACKLIST_FILE."
fi
# FINISH ### BLACKLIST NOUVEAU ###

# START ### ADD NVIDIA MODESET TO GRUB ###
echoc $YELLOW ">>> Adding nvidia-drm.modeset=1 to GRUB..."
GRUB_FILE="/etc/default/grub"
if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=.*nvidia-drm.modeset=1" "$GRUB_FILE"; then
    echoc $GREEN "--- 'nvidia-drm.modeset=1' already present in GRUB_CMDLINE_LINUX_DEFAULT."
else
    echoc $WHITE "--- Modifying $GRUB_FILE to add nvidia-drm.modeset=1..."
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ { /nvidia-drm.modeset=1/! s/"/"nvidia-drm.modeset=1 /; s/  */ /g; s/" /"/g; s/ "$/"/g; }' "$GRUB_FILE"
    if [ $? -eq 0 ]; then
        echoc $GREEN "+++ Successfully modified $GRUB_FILE."
        echoc $YELLOW ">>> Verification:"
        echoc $WHITE "--------------------------------------------------"
        sudo grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE"
        echoc $WHITE "--------------------------------------------------"
        echoc $YELLOW ">>> Make sure 'nvidia-drm.modeset=1' is now present inside the quotes."
        # Update grub only if modification was successful
        echoc $YELLOW ">>> Updating GRUB configuration..."
        sudo update-grub
        check_success "GRUB update"
    else
        echoc $RED "!!! Failed to modify $GRUB_FILE. Check permissions or sed errors."
        exit 1 # Exit if sed failed
    fi
fi
# FINISH ### ADD NVIDIA MODESET TO GRUB ###


# START ### UPDATE INITRAMFS ###
echoc $YELLOW ">>> Updating initramfs for all kernels..."
sudo update-initramfs -u -k all
check_success "Initramfs update"
# FINISH ### UPDATE INITRAMFS ###

# START ### REBOOT PROMPT ###
echoc $MAGENTA "=============================================="
echoc $MAGENTA " Nvidia setup steps complete."
echoc $MAGENTA " A REBOOT is REQUIRED to apply all changes."
echoc $YELLOW " Do you want to reboot now? (y/N)"
read -p "> " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    echoc $CYAN ">>> Rebooting system NOW..."
    sudo reboot
else
    echoc $CYAN ">>> Please reboot your system manually later."
fi
# FINISH ### REBOOT PROMPT ###

echoc $GREEN "===== Nvidia Driver Setup Script Finished ====="
exit 0
