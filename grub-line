#!/bin/bash

# --- Colors ---
GREEN=$(tput setaf 2; tput bold)
CYAN=$(tput setaf 6; tput bold)
WHITE=$(tput setaf 7; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1; tput bold)
RESET=$(tput sgr0)

# --- Kernel Parameters & Descriptions ---
# Use parallel arrays: one for the param string, one for the description
PARAMS=(
    "nomodeset"
    "loglevel=7"
    "debug"
    "i915.modeset=0"
    "i915.enable_psr=0"
    "nvidia-drm.modeset=1"
    "rd.driver.blacklist=nouveau module_blacklist=nouveau"
    "acpi_osi=! acpi_osi=\"Windows 2020\"" # Note: Quoted for the script logic, may need adjustment in GRUB itself if quotes cause issues
    "pcie_aspm=force"
    "pcie_aspm=off"
    "intel_pstate=disable"
    "processor.max_cstate=1"
    "nvme_core.default_ps_max_latency_us=0"
    "iwlwifi.power_save=0"
    "iwlwifi.bt_coex_active=0"
)

DESCRIPTIONS=(
    "Disable Kernel Mode Setting (Use for boot display glitches/black screen)"
    "Max Kernel Boot Verbosity (See ALL boot messages for hidden errors)"
    "Extreme Kernel Debug Logging (Even more detail than loglevel=7, slows boot)"
    "Disable Intel GPU modesetting ONLY (If Intel graphics suspected culprit)"
    "Disable Panel Self Refresh (Fix random screen flickering on laptop display)"
    "Enable NVIDIA Kernel Mode Setting (RECOMMENDED for proprietary driver smoothness)"
    "BLACKLIST Nouveau Driver (ESSENTIAL for proprietary NVIDIA driver stability)"
    "Pretend to be Windows for ACPI (Fix Function Keys/Power/Fan issues - try other 'Windows 20XX')"
    "Force ASPM Power Saving (Save battery via PCIe power states, potential instability)"
    "Disable ASPM Power Saving (Fix instability maybe caused by ASPM, uses more power)"
    "Disable Intel P-State Driver (Use older acpi-cpufreq for CPU scaling if P-State buggy)"
    "Limit Deepest CPU Sleep State (Fix random system freezes, uses more power)"
    "Disable NVMe Power Saving (Fix storage hangs after idle, uses more power)"
    "Disable WiFi Power Saving (Fix unstable/dropping WiFi connection, uses more battery)"
    "Disable WiFi/Bluetooth Coexistence (Fix interference/slowdowns when both are active)"
)

# --- Script Logic ---

# Header
echo "${GREEN}############################################################${RESET}"
echo "${GREEN}#        ${CYAN}GRUB KERNEL PARAMETER GENERATOR${GREEN}             #${RESET}"
echo "${GREEN}#                ${WHITE}Street Tech Edition${GREEN}                 #${RESET}"
echo "${GREEN}############################################################${RESET}"
echo ""
echo "${YELLOW}Select the parameters you need for troubleshooting. Enter numbers separated by spaces.${RESET}"
echo "${YELLOW}Example: ${WHITE}1 6 7 13${RESET}"
echo ""

# Display Options
NUM_PARAMS=${#PARAMS[@]}
for i in $(seq 0 $((NUM_PARAMS - 1))); do
    printf "${CYAN}%2d) ${WHITE}%-45s ${YELLOW}%s${RESET}\n" "$((i+1))" "${PARAMS[$i]}" "${DESCRIPTIONS[$i]}"
done
echo ""

# Get User Input
read -p "${CYAN}Enter parameter numbers: ${WHITE}" SELECTION

# Process Selection
FINAL_PARAMS=""
VALID_SELECTION=false
for num in $SELECTION; do
    # Check if it's a number and within range
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$NUM_PARAMS" ]; then
        index=$((num - 1))
        # Add parameter, ensuring space separation
        if [ -z "$FINAL_PARAMS" ]; then
            FINAL_PARAMS="${PARAMS[$index]}"
        else
            FINAL_PARAMS="$FINAL_PARAMS ${PARAMS[$index]}"
        fi
        VALID_SELECTION=true
    else
        echo "${RED}Warning: Skipping invalid input '$num'. Must be a number between 1 and $NUM_PARAMS.${RESET}"
    fi
done

# Ask about removing quiet splash
echo ""
read -p "${CYAN}Remove 'quiet' and 'splash' for max boot visibility? (y/N): ${WHITE}" REMOVE_QS

REMOVE_QS_FLAG=false
if [[ "$REMOVE_QS" =~ ^[Yy]$ ]]; then
    REMOVE_QS_FLAG=true
    echo "${YELLOW}Okay, will recommend removing 'quiet splash'.${RESET}"
else
    echo "${YELLOW}Keeping 'quiet splash' (or your current defaults).${RESET}"
fi


# Output Result
echo ""
echo "${GREEN}############################################################${RESET}"
echo "${GREEN}#                 ${CYAN}GENERATED GRUB LINE${GREEN}                  #${RESET}"
echo "${GREEN}############################################################${RESET}"

if [ "$VALID_SELECTION" = true ]; then
    echo "${YELLOW}Copy the parameters below. At the GRUB menu, press 'e' to edit, find the line starting with 'linux', go to the end, add a space, and paste these:${RESET}"
    echo ""
    echo "${WHITE}${FINAL_PARAMS}${RESET}"
    echo ""
    if [ "$REMOVE_QS_FLAG" = true ]; then
        echo "${YELLOW}ALSO: Remember to DELETE the words '${WHITE}quiet${YELLOW}' and '${WHITE}splash${YELLOW}' from that same line.${RESET}"
    else
        echo "${YELLOW}Remember you can manually delete '${WHITE}quiet${YELLOW}' and '${WHITE}splash${YELLOW}' if needed for debugging.${RESET}"
    fi
    echo ""
    echo "${YELLOW}Press ${WHITE}Ctrl+X${YELLOW} or ${WHITE}F10${YELLOW} to boot with these temporary changes.${RESET}"
    echo "${YELLOW}If it works, edit ${WHITE}/etc/default/grub${YELLOW} and run ${WHITE}sudo update-grub${YELLOW} (or equivalent) to make it permanent.${RESET}"
else
    echo "${RED}No valid parameters selected. Nothing generated.${RESET}"
fi

echo "${GREEN}############################################################${RESET}"

exit 0
