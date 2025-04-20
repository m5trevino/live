#!/bin/bash

# ############################################################################
# create_pop_boot_entries.sh (v3 - Interactive & Styled)
#
# PURPOSE: Creates various systemd-boot entries for Pop!_OS with different
#          kernel parameters for troubleshooting, automatically detecting
#          kernel paths and root UUID, with user confirmation.
#
# STYLE:   Inspired by Flintx's Cyberpunk Theme
#
# ############################################################################

# --- Color Definitions ---
COLOR_BANNER='\033[38;5;46m' # Neon Green
COLOR_CMD='\033[38;5;208m'    # Orange
COLOR_ERROR='\033[38;5;196m'   # Red
COLOR_SUCCESS='\033[38;5;46m' # Neon Green
COLOR_PROMPT='\033[38;5;51m'   # Cyan-Blue
COLOR_MENU='\033[38;5;213m'    # Pink/Purple
COLOR_INFO='\033[38;5;147m'    # Light Gray/Blue
COLOR_RESET='\033[0m'        # Reset
COLOR_TYPEWRITER='\033[38;5;220m' # Yellow for typewriter

# --- Output Functions ---
banner() {
    echo -e "${COLOR_BANNER}"
    echo '╔═════════════════════════════════════════════════════════════╗'
    echo '║    ____ ____ ___ ____ ____ ____ ____ ____ ____ ____ ____     ║'
    echo '║    ||P |||o |||p |||! |||_ |||O |||S |||B |||o |||o |||t ||    ║'
    echo '║    ||__|||__|||__|||__|||__|||__|||__|||__|||__|||__|||__||    ║'
    echo '║    |/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|/__\|    ║'
    echo '║         E N T R Y   C R E A T O R   (v3)                  ║'
    echo '╚═════════════════════════════════════════════════════════════╝'
    echo -e "${COLOR_RESET}"
}

show_command() {
    # $1 = command description, $2 = actual command (optional)
    echo -e "${COLOR_CMD}[ACTION]  → $1${COLOR_RESET}"
    if [ -n "$2" ]; then
      echo -e "${COLOR_CMD}          ↳ $2${COLOR_RESET}"
    fi
}

error() {
    echo -e "${COLOR_ERROR}[ERROR]   → $1${COLOR_RESET}"
}

success() {
    echo -e "${COLOR_SUCCESS}[SUCCESS] → $1${COLOR_RESET}"
}

info() {
    echo -e "${COLOR_INFO}[INFO]    → $1${COLOR_RESET}"
}

# --- Typewriter Function ---
type_out() {
    local text="$1"
    local delay=${2:-0.02} # Default delay 0.02s
    echo -n -e "${COLOR_TYPEWRITER}" # Set color for typing
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo -e "${COLOR_RESET}" # Reset color after typing
}


# --- Main Script Logic ---
banner # Show banner first

# --- Prerequisite Checks ---
info "Checking prerequisites..."
if ! command -v findmnt > /dev/null; then
    error "'findmnt' command not found (usually part of 'util-linux'). Cannot detect root UUID."
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
     if ! command -v sudo > /dev/null; then
        error "'sudo' command not found and not running as root. Cannot write to ESP."
        exit 1
    fi
     if ! sudo -v > /dev/null 2>&1; then
       error "Could not obtain sudo privileges. Check password or sudoers config."
       exit 1
    fi
     SUDO_CMD="sudo"
     success "Sudo available."
else
    SUDO_CMD="" # Running as root, no sudo needed prefix
    success "Running as root."
fi
success "Prerequisites met."
echo "" # newline

# --- Auto-Detect Paths and UUID ---
info "Auto-detecting system info..."
ROOT_UUID=$(findmnt -n -o UUID /)
if [ -z "$ROOT_UUID" ]; then
    error "Could not automatically determine ROOT filesystem UUID."
    exit 1
fi
info "Detected ROOT UUID: ${ROOT_UUID}" # Display normally first

# Determine ESP mount point
ESP_DIR="/boot/efi"
if [ ! -d "$ESP_DIR" ]; then
    error "ESP directory '${ESP_DIR}' not found. Cannot proceed."
    exit 1
fi
info "Using ESP Path: ${ESP_DIR}"

# Construct kernel/initrd paths
ESP_POP_DIR_REL="EFI/Pop_OS-${ROOT_UUID}"
KERNEL_PATH_REL="/${ESP_POP_DIR_REL}/vmlinuz.efi"
INITRD_PATH_REL="/${ESP_POP_DIR_REL}/initrd.img"
info "Using Kernel Path for entries: ${KERNEL_PATH_REL}"
info "Using Initrd Path for entries: ${INITRD_PATH_REL}"

# Check if the target directory for entries exists
ENTRIES_DIR="${ESP_DIR}/loader/entries"
if [ ! -d "$ENTRIES_DIR" ]; then
    info "Entries directory '${ENTRIES_DIR}' not found. Attempting to create..."
    show_command "Creating directory ${ENTRIES_DIR}" "$SUDO_CMD mkdir -p ${ENTRIES_DIR}"
    $SUDO_CMD mkdir -p "${ENTRIES_DIR}"
    if [ $? -ne 0 ]; then
        error "Failed to create entries directory. Check permissions."
        exit 1
    fi
    success "Entries directory created."
else
    info "Target directory for entries: ${ENTRIES_DIR}"
fi
echo ""

# --- Type out UUID ---
info "Detected UUID will be used for entries:"
type_out "${ROOT_UUID}" 0.03 # Slightly slower typing for UUID
echo ""

# --- Confirmation ---
echo -e "${COLOR_PROMPT}Generate boot entries with this configuration? (y/N): ${COLOR_RESET}"
read -r CONFIRM
echo "" # newline

# --- Conditional Entry Generation ---
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Aborting entry generation."
    exit 0
fi

# --- Proceed with Generation ---
info "Generating boot entry files..."
echo ""

# Define Base Options
BASE_OPTIONS="root=UUID=${ROOT_UUID} ro"
info "Base kernel options set to: ${BASE_OPTIONS}"
echo ""

created_count=0 # Initialize counter

# --- Function to Create Entry File ---
# Usage: create_entry "Filename_Suffix" "Title" "extra_options"
create_entry() {
    local suffix="$1"
    local title="$2"
    local extra_options="$3"
    local filename="Pop_OS-${suffix}.conf"
    local filepath="${ENTRIES_DIR}/${filename}"

    show_command "Creating entry: ${title}" "File: ${filepath}"

    local entry_content
    entry_content=$(cat << HEREDOC
title   ${title}
linux   ${KERNEL_PATH_REL}
initrd  ${INITRD_PATH_REL}
options ${BASE_OPTIONS} ${extra_options}
HEREDOC
)
    # Write content using sudo tee
    echo "${entry_content}" | $SUDO_CMD tee "${filepath}" > /dev/null
    if [ $? -eq 0 ]; then
        success "Created: ${filename}"
        ((created_count++)) # Increment counter on success
    else
        error "Failed to create: ${filename}"
    fi
    echo "" # Add a newline for readability
}

# --- Create the Entries ---
# (Calling the create_entry function for each option)
create_entry "failsafe-nomodeset" "Pop!_OS Failsafe (Text, nomodeset)" "3 nomodeset"
create_entry "kill-nouveau" "Pop!_OS Failsafe (Text, Kill Nouveau)" "3 nomodeset nouveau.modeset=0 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"
create_entry "recovery-single" "Pop!_OS Recovery (Single User, nomodeset)" "single nomodeset"
create_entry "nvidia-text" "Pop!_OS Nvidia (Text, Quiet)" "quiet 3 nvidia-drm.modeset=1"
create_entry "nvidia-text-verbose" "Pop!_OS Nvidia (Text, Verbose)" "loglevel=7 3 nvidia-drm.modeset=1"
create_entry "drm-debug" "Pop!_OS DRM Debug (log_buf_len=10M)" "drm.debug=0x1e log_buf_len=10M nvidia-drm.modeset=1"
create_entry "failsafe-ibt-off" "Pop!_OS Failsafe (Text, nomodeset, ibt=off)" "3 nomodeset ibt=off"
create_entry "kill-nouveau-ibt-off" "Pop!_OS Failsafe (Kill Nouveau, ibt=off)" "3 nomodeset nouveau.modeset=0 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau ibt=off"
create_entry "recovery-single-ibt-off" "Pop!_OS Recovery (Single User, nomodeset, ibt=off)" "single nomodeset ibt=off"
create_entry "nvidia-noaspm" "Pop!_OS Nvidia (PCIe ASPM Off)" "quiet nvidia-drm.modeset=1 pcie_aspm=off splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-nopstate" "Pop!_OS Nvidia (Intel P-State Off)" "quiet nvidia-drm.modeset=1 intel_pstate=disable splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-nocstates" "Pop!_OS Nvidia (Max C-State 1)" "quiet nvidia-drm.modeset=1 processor.max_cstate=1 intel_idle.max_cstate=1 splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-nomsi" "Pop!_OS Nvidia (MSI Disabled)" "quiet nvidia-drm.modeset=1 nvidia.NVreg_EnableMSI=0 splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-nopciepm" "Pop!_OS Nvidia (PCIe Port PM Off)" "quiet nvidia-drm.modeset=1 pcie_port_pm=off splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-swiommu" "Pop!_OS Nvidia (Software IOMMU)" "quiet nvidia-drm.modeset=1 iommu=soft splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-graphical" "Pop!_OS Nvidia (Graphical Target)" "quiet nvidia-drm.modeset=1 systemd.unit=graphical.target splash loglevel=0 systemd.show_status=false"
create_entry "nvidia-powerlimits" "Pop!_OS Nvidia (Max C-State 1, ASPM Off)" "quiet nvidia-drm.modeset=1 processor.max_cstate=1 intel_idle.max_cstate=1 pcie_aspm=off splash loglevel=0 systemd.show_status=false"

# --- Final Summary ---
echo ""
success "Finished generating entries."
echo ""
summary_msg="Successfully created ${created_count} boot entry file(s) in ${ENTRIES_DIR}"
type_out "${summary_msg}" 0.02 # Type out summary
echo ""
info "Reboot and use Spacebar/etc to access the systemd-boot menu."
echo ""

exit 0
