#!/bin/bash

# === CONFIGURATION ===
# Directory where we stash the goods temporarily
BASE_DUMP_DIR="/tmp"

# === COLORS (Cyberpunk Hacker Shit) ===
GREEN=$(tput setaf 2; tput bold)
CYAN=$(tput setaf 6; tput bold)
WHITE=$(tput setaf 7; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1; tput bold)
RESET=$(tput sgr0)

# === FUNCTIONS ===

# Function to print styled messages
echoc() {
    COLOR=$1
    shift
    echo -e "${COLOR}$*${RESET}"
}

# Function to copy files/dirs, verbose, handles missing files
copy_item() {
    SOURCE=$1
    DEST_DIR=$2
    echoc $YELLOW ">>> Grabbing: $SOURCE"
    # Use sudo cp -a to preserve permissions/timestamps, handle errors gracefully
    sudo cp -av "$SOURCE" "$DEST_DIR/" 2> >(while read line; do echoc $RED "    WARN: $line"; done) || echoc $RED "    !!! FAILED or NOT FOUND: $SOURCE"
}

# Function to run command and save output
run_command() {
    CMD_DESC=$1
    CMD_STR=$2
    OUTPUT_FILE=$3
    echoc $YELLOW ">>> Running: $CMD_DESC"
    # Use script to redirect stderr, capture exit code
    script -q -c "sudo $CMD_STR" /dev/null | tee "$OUTPUT_FILE" > /dev/null
    EXIT_CODE=${PIPESTATUS[0]}
    if [ $EXIT_CODE -ne 0 ]; then
        echoc $RED "    !!! Command failed with exit code $EXIT_CODE: $CMD_STR"
        echo "--- COMMAND FAILED (Exit Code: $EXIT_CODE) ---" >> "$OUTPUT_FILE"
    fi
    # Add a separator for readability in the output file
    echo -e "\n\n" >> "$OUTPUT_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# === SCRIPT START ===
echoc $GREEN "############################################################"
echoc $GREEN "#        ${CYAN}COMPREHENSIVE SYSTEM LOG & INFO GRABBER${GREEN}       #"
echoc $GREEN "#              ${WHITE}KEEP IT 100 - DIAGNOSTICS${GREEN}             #"
echoc $GREEN "############################################################"
echo ""

# Check if running as root, needed for many operations
if [ "$(id -u)" -ne 0 ]; then
  echoc $RED "!!! This script needs root privileges for full log access."
  echoc $RED "!!! Run it like: sudo ./comprehensive_log_grabber.sh"
  exit 1
fi

# Timestamp for the dump directory
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DUMP_DIR_NAME="system_dump_${TIMESTAMP}"
FULL_DUMP_PATH="${BASE_DUMP_DIR}/${DUMP_DIR_NAME}"
TARBALL_NAME="${DUMP_DIR_NAME}.tar.gz"
FULL_TARBALL_PATH="${BASE_DUMP_DIR}/${TARBALL_NAME}"

echoc $CYAN ">>> Setting up temporary dump directory: ${WHITE}${FULL_DUMP_PATH}"
mkdir -p "$FULL_DUMP_PATH"
if [ ! -d "$FULL_DUMP_PATH" ]; then
    echoc $RED "!!! Failed to create dump directory. Check permissions or /tmp space."
    exit 1
fi

# --- 1. Grab Standard Log Files ---
echoc $CYAN "\n--- Grabbing Standard Log Files ---"
LOG_DIR="/var/log"
copy_item "${LOG_DIR}/syslog" "$FULL_DUMP_PATH"         # Main system log
copy_item "${LOG_DIR}/kern.log" "$FULL_DUMP_PATH"       # Kernel messages
copy_item "${LOG_DIR}/messages" "$FULL_DUMP_PATH"      # Another common system log
copy_item "${LOG_DIR}/auth.log" "$FULL_DUMP_PATH"       # Authentication events (logins, sudo)
copy_item "${LOG_DIR}/boot.log" "$FULL_DUMP_PATH"       # Boot messages (if bootlogd was used/configured)
copy_item "${LOG_DIR}/dpkg.log" "$FULL_DUMP_PATH"       # Package manager actions (Debian/MX specific)
copy_item "${LOG_DIR}/apt/" "$FULL_DUMP_PATH"           # APT package manager history (Debian/MX specific)
copy_item "${LOG_DIR}/lightdm/" "$FULL_DUMP_PATH"       # LightDM display manager logs
copy_item "${LOG_DIR}/Xorg.0.log" "$FULL_DUMP_PATH"     # Current X server log
copy_item "${LOG_DIR}/Xorg.1.log" "$FULL_DUMP_PATH"     # Previous X server log (if exists)
# Copy rotated logs too - grab the last few for context
echoc $YELLOW ">>> Grabbing rotated logs (syslog*, kern.log*, messages*, auth.log*)"
sudo find "$LOG_DIR" -maxdepth 1 \( -name 'syslog.*' -o -name 'kern.log.*' -o -name 'messages.*' -o -name 'auth.log.*' \) -print0 | sudo xargs -0 -I {} cp -v {} "$FULL_DUMP_PATH/" 2> >(while read line; do echoc $RED "    WARN: $line"; done)

# --- 2. Check and Grab Journald Logs (If Available) ---
echoc $CYAN "\n--- Checking for systemd-journald Logs (Even on SysVinit) ---"
if command_exists journalctl; then
    echoc $YELLOW ">>> journalctl found. Attempting to grab journal logs."
    run_command "Journald Logs (Current Boot)" "journalctl -b" "$FULL_DUMP_PATH/journalctl_current_boot.log"
    run_command "Journald Logs (Previous Boot)" "journalctl -b -1" "$FULL_DUMP_PATH/journalctl_previous_boot.log"
    run_command "Journald Disk Usage" "journalctl --disk-usage" "$FULL_DUMP_PATH/journalctl_disk_usage.txt"
    copy_item "/etc/systemd/journald.conf" "$FULL_DUMP_PATH" # Grab config to see 'Storage=' setting
else
    echoc $YELLOW ">>> journalctl command not found. Skipping journal logs."
fi

# --- 3. Run Diagnostic Commands ---
echoc $CYAN "\n--- Running Diagnostic Commands ---"
run_command "Kernel Messages (dmesg)" "dmesg -T" "$FULL_DUMP_PATH/dmesg.log" # -T adds human-readable timestamps
run_command "Loaded Kernel Modules" "lsmod" "$FULL_DUMP_PATH/lsmod.txt"
run_command "PCI Devices" "lspci -vvv" "$FULL_DUMP_PATH/lspci.txt" # Very verbose
run_command "USB Devices" "lsusb -v" "$FULL_DUMP_PATH/lsusb.txt" # Verbose
run_command "Memory Usage" "free -h" "$FULL_DUMP_PATH/memory_usage.txt"
run_command "Disk Usage" "df -h" "$FULL_DUMP_PATH/disk_usage.txt"
run_command "Disk Usage (/var/log)" "du -sh /var/log" "$FULL_DUMP_PATH/var_log_size.txt"
run_command "System Info (uname)" "uname -a" "$FULL_DUMP_PATH/uname.txt"
run_command "CPU Info" "lscpu" "$FULL_DUMP_PATH/lscpu.txt"
run_command "Kernel Boot Parameters" "cat /proc/cmdline" "$FULL_DUMP_PATH/kernel_cmdline.txt"
run_command "Filesystem Table" "cat /etc/fstab" "$FULL_DUMP_PATH/fstab.txt"
run_command "Network Interfaces (ip)" "ip a" "$FULL_DUMP_PATH/ip_addr.txt"
run_command "Network Routing (ip)" "ip r" "$FULL_DUMP_PATH/ip_route.txt"
run_command "Network Interfaces (ifconfig)" "ifconfig -a" "$FULL_DUMP_PATH/ifconfig.txt" # Old school too
run_command "SysVinit Service Status" "service --status-all" "$FULL_DUMP_PATH/service_status_all.txt"
# Check for optional hardware commands
if command_exists lshw; then
    run_command "Hardware Summary (lshw)" "lshw -short" "$FULL_DUMP_PATH/lshw_short.txt"
else
    echoc $YELLOW ">>> lshw command not found. Skipping hardware summary."
fi
if command_exists dmidecode; then
    run_command "BIOS/DMI Info (dmidecode)" "dmidecode" "$FULL_DUMP_PATH/dmidecode.txt"
else
    echoc $YELLOW ">>> dmidecode command not found. Skipping BIOS info."
fi
# Get detailed info about loaded nvidia driver if present
if lsmod | grep -q nvidia; then
    run_command "NVIDIA SMI" "nvidia-smi" "$FULL_DUMP_PATH/nvidia-smi.txt"
    run_command "NVIDIA Settings Query" "nvidia-settings -q all" "$FULL_DUMP_PATH/nvidia-settings.txt"
fi
# Get general system info with inxi if available
if command_exists inxi; then
    run_command "System Info (inxi)" "inxi -Fxxxz" "$FULL_DUMP_PATH/inxi_Fxxxz.txt"
else
    echoc $YELLOW ">>> inxi command not found. Skipping inxi."
fi

# --- 4. Grab Relevant Configuration Files ---
echoc $CYAN "\n--- Grabbing Configuration Files ---"
copy_item "/etc/default/grub" "$FULL_DUMP_PATH"         # GRUB configuration defaults
copy_item "/boot/grub/grub.cfg" "$FULL_DUMP_PATH"       # Actual GRUB config (usually generated)
copy_item "/etc/X11/xorg.conf" "$FULL_DUMP_PATH"        # Main Xorg config (if it exists)
copy_item "/etc/X11/xorg.conf.d/" "$FULL_DUMP_PATH"     # Xorg config directory
copy_item "/etc/lightdm/lightdm.conf" "$FULL_DUMP_PATH" # LightDM main config
copy_item "/etc/lightdm/lightdm.conf.d/" "$FULL_DUMP_PATH" # LightDM config directory
copy_item "/etc/rsyslog.conf" "$FULL_DUMP_PATH"         # Rsyslog main config (for checking persistence)
copy_item "/etc/rsyslog.d/" "$FULL_DUMP_PATH"           # Rsyslog config directory

# --- 5. Check Log Persistence Status (Rsyslog) ---
echoc $CYAN "\n--- Checking Log Persistence (Rsyslog Status) ---"
echoc $YELLOW ">>> Checking if rsyslog service is active..."
if command_exists service; then
    RSYSLOG_STATUS=$(service rsyslog status 2>&1)
    if [[ "$RSYSLOG_STATUS" == *"is running"* || "$RSYSLOG_STATUS" == *"active (running)"* ]]; then
        echoc $GREEN "    +++ Rsyslog service appears to be running. Logs *should* be persistent."
        echo "Rsyslog service appears to be running." > "$FULL_DUMP_PATH/rsyslog_status.txt"
        echo "$RSYSLOG_STATUS" >> "$FULL_DUMP_PATH/rsyslog_status.txt"
    else
        echoc $RED "    !!! Rsyslog service does NOT appear to be running. Logs might not be saved across reboots!"
        echo "!!! WARNING: Rsyslog service does not appear to be running !!!" > "$FULL_DUMP_PATH/rsyslog_status.txt"
        echo "$RSYSLOG_STATUS" >> "$FULL_DUMP_PATH/rsyslog_status.txt"
        echoc $RED "    !!! Check your system config ('sudo service rsyslog start', check /etc/rsyslog.conf)."
    fi
    echoc $YELLOW "    (Check grabbed rsyslog config files to confirm settings.)"
else
    echoc $YELLOW ">>> 'service' command not found? Skipping rsyslog status check."
fi

# --- 6. Package Everything Up ---
echoc $CYAN "\n--- Packaging Logs and Info ---"
echoc $YELLOW ">>> Creating tarball: ${WHITE}${FULL_TARBALL_PATH}"
# Use tar with -C to change directory, avoids including full path from /tmp
if sudo tar czf "$FULL_TARBALL_PATH" -C "$BASE_DUMP_DIR" "$DUMP_DIR_NAME"; then
    echoc $GREEN "+++ Successfully created tarball."
    # Clean up the temporary directory ONLY if tar was successful
    echoc $YELLOW ">>> Cleaning up temporary directory: ${WHITE}${FULL_DUMP_PATH}"
    sudo rm -rf "$FULL_DUMP_PATH"
    echoc $GREEN "+++ Done."
    echo ""
    echoc $GREEN "############################################################"
    echoc $GREEN "#                ${CYAN}COLLECTION COMPLETE${GREEN}                 #"
    echoc $GREEN "############################################################"
    echoc $WHITE "Your system logs and info have been packed into:"
    echoc $CYAN "$FULL_TARBALL_PATH"
    echoc $WHITE "Grab this file and analyze it, my G."
    echoc $WHITE "You can extract it using: ${YELLOW}tar xzf ${TARBALL_NAME}"
else
    echoc $RED "!!! Failed to create tarball!"
    echoc $RED "!!! Dump directory ${WHITE}${FULL_DUMP_PATH}${RED} left in place for manual inspection."
    exit 1
fi

exit 0
