#!/bin/bash

# ############################################################################
# check_graphics_state.sh (v1)
#
# PURPOSE: Gathers info about the current graphics state (Nvidia/Nouveau),
#          configuration, and potential issues to help decide on safe
#          boot options before rebooting.
#          **THIS SCRIPT PROVIDES INFO & SUGGESTIONS - NO GUARANTEES!**
#
# HOW TO USE:
# 1. Make executable: chmod +x check_graphics_state.sh
# 2. Run it: ./check_graphics_state.sh
# 3. Read the report and warnings carefully.
# 4. Choose your GRUB boot option based on the intel.
#
# ############################################################################

echo "--- Pre-Boot Graphics State Check ---"
echo "Gathering intel... Be patient, my boy."
echo ""

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

# START ### KERNEL INFO ###
KERNEL_VERSION=$(uname -r)
echo "[INFO] Current Kernel: ${KERNEL_VERSION}"
# FINISH ### KERNEL INFO ###

# START ### LOADED MODULES ###
echo "[INFO] Checking loaded kernel modules..."
if lsmod | grep -q '^nvidia\s'; then
    nvidia_loaded="Yes"
    echo "  - Nvidia driver module IS LOADED."
else
    echo "  - Nvidia driver module IS NOT loaded."
fi
if lsmod | grep -q '^nouveau\s'; then
    nouveau_loaded="Yes"
    echo "  - Nouveau driver module IS LOADED."
else
    echo "  - Nouveau driver module IS NOT loaded."
fi
if [ "$nvidia_loaded" = "No" ] && [ "$nouveau_loaded" = "No" ]; then
    echo "  - Neither Nvidia nor Nouveau modules loaded (likely using basic framebuffer/vesa)."
    warnings+=("Neither Nvidia nor Nouveau kernel modules currently loaded.")
fi
if [ "$nvidia_loaded" = "Yes" ] && [ "$nouveau_loaded" = "Yes" ]; then
    echo "  [WARNING] Both Nvidia AND Nouveau modules appear loaded? This is unusual/problematic."
    warnings+=("Both Nvidia AND Nouveau modules seem loaded - potential conflict.")
fi
# FINISH ### LOADED MODULES ###

# START ### BLACKLIST CHECK ###
echo "[INFO] Checking module blacklists in /etc/modprobe.d/ ..."
if grep -r -E '^\s*blacklist\s+nouveau' /etc/modprobe.d/ | grep -v '^#' > /dev/null; then
    nouveau_blacklisted="Yes"
    echo "  - Nouveau IS blacklisted."
else
    echo "  - Nouveau does NOT appear blacklisted."
fi
if grep -r -E '^\s*blacklist\s+nvidia' /etc/modprobe.d/ | grep -v '^#' > /dev/null; then
    nvidia_blacklisted="Yes"
    echo "  - Nvidia IS blacklisted (uncommon unless forcing Nouveau)."
else
    echo "  - Nvidia does NOT appear blacklisted."
fi
# FINISH ### BLACKLIST CHECK ###

# START ### PACKAGE & DKMS CHECK ###
echo "[INFO] Checking relevant packages..."
if dpkg -s nvidia-driver > /dev/null 2>&1 || dpkg -s nvidia-tesla-\S+-driver > /dev/null 2>&1 || dpkg -s nvidia-legacy-\S+-driver > /dev/null 2>&1 ; then
    nvidia_pkg_installed="Yes"
    echo "  - Nvidia driver package appears installed."

    # Check DKMS status ONLY if nvidia driver is installed
    echo "[INFO] Checking Nvidia DKMS status..."
    if command -v dkms > /dev/null; then
        # Check if *any* nvidia module is built for the *current* kernel
        dkms_output=$(dkms status | grep -i nvidia)
        if echo "$dkms_output" | grep -q "${KERNEL_VERSION}"; then
             if echo "$dkms_output" | grep -q "installed"; then
                 dkms_ok="Yes"
                 echo "  - DKMS module for Nvidia IS BUILT and installed for kernel ${KERNEL_VERSION}."
             else
                 dkms_ok="No"
                 echo "  [ERROR] DKMS shows Nvidia module for ${KERNEL_VERSION} exists but status is NOT 'installed'."
                 warnings+=("Nvidia DKMS module status for current kernel is problematic!")
             fi
        else
            dkms_ok="No"
            echo "  [ERROR] Nvidia DKMS module IS NOT BUILT for current kernel ${KERNEL_VERSION}!"
            warnings+=("CRITICAL: Nvidia DKMS module MISSING for current kernel. Nvidia boot will likely FAIL.")
        fi
    else
        echo "  - dkms command not found, cannot check Nvidia module build status."
        warnings+=("dkms command not found - unable to verify Nvidia module build.")
    fi
else
    echo "  - Nvidia driver package NOT found."
fi

if dpkg -s xserver-xorg-video-nouveau > /dev/null 2>&1; then
    nouveau_pkg_installed="Yes"
    echo "  - xserver-xorg-video-nouveau package IS installed."
else
    echo "  - xserver-xorg-video-nouveau package NOT found."
fi
if dpkg -s firmware-misc-nonfree > /dev/null 2>&1; then
    firmware_pkg_installed="Yes"
    echo "  - firmware-misc-nonfree package IS installed (often helps Nouveau)."
else
    echo "  - firmware-misc-nonfree package NOT found."
    if [ "$nouveau_loaded" = "Yes" ] || [ "$nouveau_blacklisted" = "No" ]; then
        warnings+=("firmware-misc-nonfree package missing - may impact Nouveau stability/features.")
    fi
fi
# FINISH ### PACKAGE & DKMS CHECK ###

# START ### XORG CONFIG CHECK ###
echo "[INFO] Checking Xorg configuration (/etc/X11/)..."
xorg_conf_files=$(find /etc/X11/ -maxdepth 2 -name '*.conf' -type f 2>/dev/null)
xorg_driver_found_in_config="No"
if [ -n "$xorg_conf_files" ]; then
    if grep -r -E '^\s*Driver\s+"nvidia"' $xorg_conf_files | grep -v '^#' > /dev/null; then
        xorg_driver="nvidia (explicit)"
        xorg_driver_found_in_config="Yes"
        echo "  - Found Xorg config explicitly setting Driver 'nvidia'."
    elif grep -r -E '^\s*Driver\s+"nouveau"' $xorg_conf_files | grep -v '^#' > /dev/null; then
        xorg_driver="nouveau (explicit)"
        xorg_driver_found_in_config="Yes"
        echo "  - Found Xorg config explicitly setting Driver 'nouveau'."
    else
         echo "  - Found Xorg config files, but no explicit 'nvidia' or 'nouveau' Driver line detected."
    fi
else
    echo "  - No standard Xorg config files found (likely using auto-configuration)."
fi
# FINISH ### XORG CONFIG CHECK ###

# START ### HARDWARE CHECK ###
echo "[INFO] Checking PCI device list for Nvidia card..."
if lspci -k | grep -A 3 -i -E 'vga|3d controller' | grep -iq nvidia; then
    echo "  - Nvidia graphics hardware DETECTED."
else
    echo "  [ERROR] Nvidia graphics hardware NOT detected via lspci!"
    warnings+=("CRITICAL: Nvidia hardware not detected by lspci. Major issue.")
fi
# FINISH ### HARDWARE CHECK ###

# START ### ANALYSIS & SUGGESTIONS ###
echo ""
echo "--- Analysis & Suggestions ---"

# Analyze consistency and formulate suggestions
if [ "$nvidia_pkg_installed" = "Yes" ] && [ "$dkms_ok" = "Yes" ] && [ "$nouveau_blacklisted" = "Yes" ]; then
    suggestions+=("Primary setup appears to be functional Nvidia.")
    suggestions+=("Suggest using standard Nvidia GUI/TTY boot options.")
    if [ "$nvidia_loaded" = "No" ]; then
        warnings+=("Nvidia setup seems okay (DKMS, blacklist) but module isn't loaded now? Check current session.")
    fi
    if [ "$xorg_driver_found_in_config" = "Yes" ] && [ "$xorg_driver" != "nvidia (explicit)" ]; then
         warnings+=("Xorg config explicitly sets non-Nvidia driver, may conflict with intended Nvidia setup.")
    fi

elif [ "$nouveau_pkg_installed" = "Yes" ] && [ "$nvidia_blacklisted" = "Yes" ]; then
     suggestions+=("Primary setup appears to be Nouveau (Nvidia blacklisted).")
     suggestions+=("Suggest using Nouveau GUI/TTY boot options.")
     if [ "$nouveau_loaded" = "No" ]; then
         warnings+=("Setup seems configured for Nouveau, but module isn't loaded now? Check current session.")
     fi
     if [ "$xorg_driver_found_in_config" = "Yes" ] && [ "$xorg_driver" != "nouveau (explicit)" ]; then
         warnings+=("Xorg config explicitly sets non-Nouveau driver, may conflict with intended Nouveau setup.")
     fi

elif [ "$nouveau_pkg_installed" = "Yes" ] && [ "$nouveau_blacklisted" = "No" ] && [ "$nvidia_pkg_installed" = "No" ]; then
    suggestions+=("Setup appears to be Nouveau (Nvidia driver not installed).")
    suggestions+=("Suggest using Nouveau GUI/TTY boot options.")

elif [ "$nvidia_pkg_installed" = "Yes" ] && [ "$dkms_ok" = "No" ]; then
    suggestions+=("Nvidia driver installed BUT DKMS module is MISSING/FAILED for kernel ${KERNEL_VERSION}.")
    suggestions+=("!!! Nvidia boot options WILL LIKELY FAIL !!!")
    suggestions+=("STRONGLY recommend booting with Nouveau options OR 'nomodeset' / safe mode.")
    suggestions+=("You likely need to fix DKMS (reinstall nvidia-kernel-dkms? Check headers?).")

elif [ "$nvidia_loaded" = "Yes" ] && [ "$nouveau_blacklisted" = "No" ]; then
    warnings+=("Nvidia module loaded, but Nouveau is NOT blacklisted. Potential race condition on boot.")
    suggestions+=("Suggest ensuring Nouveau IS blacklisted in /etc/modprobe.d/ for reliable Nvidia boot.")
    suggestions+=("For now, Nvidia boot options *might* work, but have Nouveau/nomodeset ready.")

elif [ "$nouveau_loaded" = "Yes" ] && [ "$nouveau_blacklisted" = "Yes" ]; then
     warnings+=("Nouveau module loaded, but it's ALSO blacklisted? Conflicting state.")
     suggestions+=("Review your blacklist files in /etc/modprobe.d/. Boot may be unpredictable.")
     suggestions+=("Safest bet: try 'nomodeset' or basic TTY option first.")

else
    suggestions+=("Could not determine a clear primary driver setup based on current state.")
    suggestions+=("Suggest starting with a known safe option: 'nomodeset' or basic TTY.")
    suggestions+=("Review loaded modules, blacklists, and package status manually.")
fi

# Always add fallback advice
suggestions+=("ALWAYS have a 'nomodeset' or basic TTY fallback option in your GRUB menu.")

# FINISH ### ANALYSIS & SUGGESTIONS ###

# START ### REPORT OUTPUT ###
echo ""
echo "*** REPORT SUMMARY ***"
if [ ${#warnings[@]} -gt 0 ]; then
    echo ""
    echo "!! WARNINGS !!"
    for ((i=0; i<${#warnings[@]}; i++)); do
        echo "  - ${warnings[$i]}"
    done
    echo "!!"----------!!"
fi

echo ""
echo ">> SUGGESTED ACTIONS <<"
for ((i=0; i<${#suggestions[@]}; i++)); do
    echo "  -> ${suggestions[$i]}"
done
echo ">>-----------------<<"

echo ""
echo "--- Check Complete ---"
echo "Remember: This is intel, not a guarantee. Choose your boot option wisely."
# FINISH ### REPORT OUTPUT ###

exit 0
