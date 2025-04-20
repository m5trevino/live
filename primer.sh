#!/bin/bash

# ############################################################################
# check_graphics_state.sh (v6 - Ultra Simple Report)
#
# PURPOSE: Gathers info about the current graphics state (Nvidia/Nouveau),
#          configuration, and potential issues to help decide on safe
#          boot options before rebooting.
#          **THIS SCRIPT PROVIDES INFO & SUGGESTIONS - NO GUARANTEES!**
#
# HOW TO USE:
# 1. Make executable: chmod +x primer.sh
# 2. Run it: ./primer.sh
# 3. Read the report and warnings carefully.
# 4. Choose your GRUB/systemd-boot option based on the intel.
#
# ############################################################################

# START ### INITIAL SETUP ###
echo "--- Pre-Boot Graphics State Check ---"
echo "Gathering intel... Be patient, my boy."
echo ""
# set -e # Keep disabled for now to allow script to complete even if minor checks fail

# Initialize status variables
nvidia_loaded="No"
nouveau_loaded="No"
nvidia_blacklisted="No"
nouveau_blacklisted="No"
dkms_ok="N/A"
nvidia_pkg_installed="No"
nouveau_pkg_installed="No"
firmware_pkg_installed="No"
xorg_driver="Auto/Unknown"
warnings=()
suggestions=()
# FINISH ### INITIAL SETUP ###

# START ### FUNCTION DEFINITIONS ###
info() { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; warnings+=("$1"); }
error() { echo "[ERROR] $1"; warnings+=("$1"); }
critical() { echo "[CRITICAL] $1"; warnings+=("CRITICAL: $1"); }
suggest() { suggestions+=("$1"); }
# FINISH ### FUNCTION DEFINITIONS ###


# START ### KERNEL INFO ###
KERNEL_VERSION=$(uname -r)
info "Current Kernel: ${KERNEL_VERSION}"
# FINISH ### KERNEL INFO ###

# START ### LOADED MODULES ###
info "Checking loaded kernel modules..."
if lsmod | grep -q '^nvidia\s'; then
    nvidia_loaded="Yes"
    info "  - Nvidia driver module IS LOADED."
else
    info "  - Nvidia driver module IS NOT loaded."
fi
if lsmod | grep -q '^nouveau\s'; then
    nouveau_loaded="Yes"
    info "  - Nouveau driver module IS LOADED."
else
    info "  - Nouveau driver module IS NOT loaded."
fi
if [ "$nvidia_loaded" = "No" ] && [ "$nouveau_loaded" = "No" ]; then
    info "  - Neither Nvidia nor Nouveau modules loaded (using basic video)."
fi
if [ "$nvidia_loaded" = "Yes" ] && [ "$nouveau_loaded" = "Yes" ]; then
    warn "Both Nvidia AND Nouveau modules seem loaded - potential conflict."
fi
# FINISH ### LOADED MODULES ###

# START ### BLACKLIST CHECK ###
info "Checking module blacklists in /etc/modprobe.d/ ..."
if find /etc/modprobe.d/ -type f -exec grep -H -E '^\s*blacklist\s+nouveau' {} + 2>/dev/null | grep -v ':#' > /dev/null; then
    nouveau_blacklisted="Yes"
    info "  - Nouveau IS blacklisted."
else
    info "  - Nouveau does NOT appear blacklisted."
fi
if find /etc/modprobe.d/ -type f -exec grep -H -E '^\s*blacklist\s+nvidia' {} + 2>/dev/null | grep -v ':#' > /dev/null; then
    nvidia_blacklisted="Yes"
    info "  - Nvidia IS blacklisted (uncommon unless forcing Nouveau)."
else
    info "  - Nvidia does NOT appear blacklisted."
fi
# FINISH ### BLACKLIST CHECK ###

# START ### PACKAGE & DKMS CHECK ###
info "Checking relevant packages (using dpkg)..."
if command -v dpkg-query > /dev/null; then
    if dpkg-query -W -f='${Status}' nvidia-driver-* 2>/dev/null | grep -q "install ok installed" || \
       dpkg-query -W -f='${Status}' nvidia-tesla-.*-driver 2>/dev/null | grep -q "install ok installed" || \
       dpkg-query -W -f='${Status}' nvidia-legacy-.*-driver 2>/dev/null | grep -q "install ok installed" || \
       dpkg-query -W -f='${Status}' nvidia-dkms-* 2>/dev/null | grep -q "install ok installed" ; then
        nvidia_pkg_installed="Yes"
        info "  - Nvidia driver package/DKMS appears installed."

        info "Checking Nvidia DKMS status..."
        if command -v dkms > /dev/null; then
            dkms_output=$(dkms status 2>/dev/null | grep -i nvidia)
            if [ -n "$dkms_output" ]; then
                if echo "$dkms_output" | grep -q "${KERNEL_VERSION}"; then
                     if echo "$dkms_output" | grep -q -E 'installed|built'; then
                         dkms_ok="Yes"
                         info "  - DKMS module for Nvidia IS BUILT/installed for kernel ${KERNEL_VERSION}."
                     else
                         dkms_ok="No"
                         error "DKMS shows Nvidia module for ${KERNEL_VERSION} exists but status is NOT 'installed' or 'built'."
                     fi
                else
                    dkms_ok="No"
                    critical "Nvidia DKMS module IS NOT BUILT for current kernel ${KERNEL_VERSION}! Nvidia boot will likely FAIL."
                fi
            else
                 info "  - No Nvidia DKMS modules found registered."
                 dkms_ok="No" # Changed this logic slightly - if no modules, DKMS isn't 'OK' for Nvidia
            fi
        else
            warn "dkms command not found - unable to verify Nvidia module build."
        fi
    else
        info "  - Nvidia driver package/DKMS NOT found."
    fi

    if dpkg-query -W -f='${Status}' xserver-xorg-video-nouveau 2>/dev/null | grep -q "install ok installed"; then
        nouveau_pkg_installed="Yes"
        info "  - xserver-xorg-video-nouveau package IS installed."
    else
        info "  - xserver-xorg-video-nouveau package NOT found."
    fi
    if dpkg-query -W -f='${Status}' linux-firmware 2>/dev/null | grep -q "install ok installed" || \
       dpkg-query -W -f='${Status}' firmware-misc-nonfree 2>/dev/null | grep -q "install ok installed"; then
        firmware_pkg_installed="Yes"
        info "  - Relevant firmware package (linux-firmware or firmware-misc-nonfree) IS installed."
    else
        info "  - Common firmware packages NOT found."
        if [ "$nvidia_pkg_installed" = "No" ] || [ "$nouveau_blacklisted" = "No" ]; then
            warn "Firmware package missing - may impact Nouveau stability/features."
        fi
    fi
else
    warn "Cannot check package status (dpkg not found)."
fi
# FINISH ### PACKAGE & DKMS CHECK ###

# START ### XORG CONFIG CHECK ###
info "Checking Xorg configuration..."
xorg_driver_found_in_config="No"
if grep -r -l -E '^\s*Driver\s+"nvidia"' /etc/X11/xorg.conf /etc/X11/xorg.conf.d/ /usr/share/X11/xorg.conf.d/ 2>/dev/null | grep -v ':#' > /dev/null; then
    xorg_driver="nvidia (explicit)"
    xorg_driver_found_in_config="Yes"
    info "  - Found Xorg config explicitly setting Driver 'nvidia'."
elif grep -r -l -E '^\s*Driver\s+"nouveau"' /etc/X11/xorg.conf /etc/X11/xorg.conf.d/ /usr/share/X11/xorg.conf.d/ 2>/dev/null | grep -v ':#' > /dev/null; then
    xorg_driver="nouveau (explicit)"
    xorg_driver_found_in_config="Yes"
    info "  - Found Xorg config explicitly setting Driver 'nouveau'."
else
    info "  - No explicit 'nvidia' or 'nouveau' Driver line detected in common Xorg configs."
fi
# FINISH ### XORG CONFIG CHECK ###

# START ### HARDWARE CHECK ###
info "Checking PCI device list for Nvidia card..."
LSPCI_CMD="lspci"
# Check if sudo exists and we're not root
if command -v sudo > /dev/null && [ "$(id -u)" -ne 0 ]; then
    # Check if we can run lspci without password prompt (usually group access like 'sudo')
    if sudo -n lspci -k >/dev/null 2>&1; then
        LSPCI_CMD="sudo lspci"
    else
        # If passwordless sudo fails, try plain lspci, might be enough
        LSPCI_CMD="lspci"
        warn "Could not run lspci with sudo without password. Output might be limited."
    fi
elif [ "$(id -u)" -eq 0 ]; then
    # Already root, just run it
    LSPCI_CMD="lspci"
else
    # No sudo and not root, just run it
    LSPCI_CMD="lspci"
fi

# Check if the selected lspci command runs successfully
if $LSPCI_CMD -k >/dev/null 2>&1; then
    # Use -nn to get vendor/device IDs, more reliable than just name grep
    if $LSPCI_CMD -nnk | grep -i -E 'VGA compatible controller.*NVIDIA|3D controller.*NVIDIA' > /dev/null; then
        info "  - Nvidia graphics hardware DETECTED."
    else
        # Changed from error to warning - might not be a primary card issue or lspci limitation
        warn "Nvidia graphics hardware NOT detected via lspci (or permission issue/limited output)!"
    fi
else
    error "Failed to run lspci command ($LSPCI_CMD). Cannot check hardware."
fi
# FINISH ### HARDWARE CHECK ###


# START ### ANALYSIS & SUGGESTIONS ###
info "--- Analysis & Suggestions ---"

# Analyze consistency and formulate suggestions
if [ "$nvidia_pkg_installed" = "Yes" ] && [ "$dkms_ok" = "Yes" ] && [ "$nouveau_blacklisted" = "Yes" ]; then
    suggest "Primary setup appears functional Nvidia (DKMS OK, Nouveau blacklisted)."
    suggest "Suggest standard Nvidia boot (e.g., with nvidia-drm.modeset=1)."
    if [ "$nvidia_loaded" = "No" ]; then
        warn "Nvidia setup OK but module not loaded? Check initramfs/current session (may load on reboot)."
    fi
    if [ "$xorg_driver_found_in_config" = "Yes" ] && [ "$xorg_driver" != "nvidia (explicit)" ]; then
         warn "Xorg config sets non-Nvidia driver ('${xorg_driver}'), may conflict."
    fi

elif [ "$nouveau_pkg_installed" = "Yes" ] && [ "$nvidia_blacklisted" = "Yes" ]; then
     suggest "Primary setup appears Nouveau (Nvidia driver likely blacklisted/not primary)."
     suggest "Suggest standard GUI/TTY boot options (likely default)."
     if [ "$nouveau_loaded" = "No" ]; then
         warn "Setup seems Nouveau, but module not loaded? Check session (may load on reboot)."
     fi
     if [ "$xorg_driver_found_in_config" = "Yes" ] && [ "$xorg_driver" != "nouveau (explicit)" ]; then
         warn "Xorg config sets non-Nouveau driver ('${xorg_driver}'), may conflict."
     fi

elif [ "$nouveau_pkg_installed" = "Yes" ] && [ "$nouveau_blacklisted" = "No" ] && [ "$nvidia_pkg_installed" = "No" ]; then
    suggest "Setup appears Nouveau (Nvidia not installed, Nouveau active)."
    suggest "Suggest standard GUI/TTY boot options (likely default)."

elif [ "$nvidia_pkg_installed" = "Yes" ] && [ "$dkms_ok" = "No" ]; then
    suggest "Nvidia installed BUT DKMS module MISSING/FAILED for kernel ${KERNEL_VERSION}."
    suggest "!!! Nvidia boot WILL LIKELY FAIL !!!"
    suggest "STRONGLY recommend booting 'nomodeset' / safe mode / previous kernel."
    suggest "Fix DKMS (reinstall nvidia-dkms? Check headers? Check logs: /var/lib/dkms/nvidia/.../build/make.log)."

elif [ "$nvidia_loaded" = "Yes" ] && [ "$nouveau_blacklisted" = "No" ]; then
    warn "Nvidia loaded, but Nouveau NOT blacklisted. Potential conflict at boot."
    suggest "Suggest blacklisting Nouveau (/etc/modprobe.d/) for reliable Nvidia boot."
    suggest "Try Nvidia options, but have 'nomodeset' ready."

elif [ "$nouveau_loaded" = "Yes" ] && [ "$nouveau_blacklisted" = "Yes" ]; then
     warn "Nouveau loaded, but it's ALSO blacklisted? Conflicting state (maybe initramfs issue?)."
     suggest "Review blacklist files and update initramfs (sudo update-initramfs -u)."
     suggest "Boot unpredictable. Safest bet: 'nomodeset' or basic TTY first."

else
    # Catch-all for less common/clear states
    suggest "Could not determine clear optimal setup based on common patterns."
    if [ "$nvidia_pkg_installed" = "Yes" ] && [ "$dkms_ok" = "Yes" ] && [ "$nouveau_blacklisted" = "No" ]; then
       warn "Nvidia appears ready (DKMS OK), but Nouveau NOT blacklisted. Potential conflict!"
       suggest "Strongly suggest blacklisting Nouveau and updating initramfs."
       suggest "Try Nvidia boot options, have 'nomodeset' ready."
    elif [ "$nvidia_pkg_installed" = "No" ] && [ "$nouveau_pkg_installed" = "No" ]; then
       warn "Neither Nvidia nor Nouveau packages seem installed. Basic display likely."
       suggest "Install appropriate driver (Nouveau usually default if firmware present)."
    else
       suggest "Suggest safe option: 'nomodeset' or basic TTY."
       suggest "Review modules, blacklists, packages manually for inconsistencies."
    fi
fi

# Always add fallback advice
suggest "ALWAYS have a 'nomodeset' or recovery/previous kernel boot option available."

# FINISH ### ANALYSIS & SUGGESTIONS ###

# START ### REPORT OUTPUT ###
echo ""
echo "*** REPORT SUMMARY ***"
if [ ${#warnings[@]} -gt 0 ]; then
    echo ""
    echo "!! WARNINGS !!"
    # Simple loop using indices
    i=0
    while [ $i -lt ${#warnings[@]} ]; do
        echo "  - ${warnings[$i]}"
        i=$((i + 1))
    done
    echo "!!"----------!!"
fi

echo ""
echo ">> SUGGESTED ACTIONS <<"
if [ ${#suggestions[@]} -gt 0 ]; then
    # Simple loop using indices
    i=0
    while [ $i -lt ${#suggestions[@]} ]; do
        echo "  -> ${suggestions[$i]}"
        i=$((i + 1))
    done
else
    echo "  -> No specific suggestions generated." # Handle empty array case
fi
echo ">>-----------------<<"

echo ""
echo "--- Check Complete ---"
echo "Remember: This is intel, not a guarantee. Choose your boot option wisely."
# FINISH ### REPORT OUTPUT ###

# Removed set -e earlier, so exit normally
exit 0
