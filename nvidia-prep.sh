#!/bin/bash

# --- Color Definitions (Inspired by your example) ---
COLOR_BANNER='\033[38;5;46m' # Neon Green
COLOR_CMD='\033[38;5;208m'    # Orange
COLOR_ERROR='\033[38;5;196m'   # Red
COLOR_SUCCESS='\033[38;5;46m' # Neon Green
COLOR_PROMPT='\033[38;5;51m'   # Cyan-Blue
COLOR_MENU='\033[38;5;213m'    # Pink/Purple
COLOR_INFO='\033[38;5;147m'    # Light Gray/Blue
COLOR_RESET='\033[0m'        # Reset

# --- Output Functions ---
banner() {
    echo -e "${COLOR_BANNER}"
    echo '╔═════════════════════════════════════════════════════════════╗'
    echo '║  ╦╔╗╔╔═╗╦╔═╔═╗╦  ╔═╗╦═╗╔═╗╔═╗╦╔═╗╔╦╗                      ║'
    echo '║  ║║║║╠═╣╠╩╗╠═╣║  ╠═╣╠╦╝╚═╗║ ║║╠═╣ ║║                      ║'
    echo '║  ╩╝╚╝╩ ╩╩ ╩╩ ╩╩═╝╩ ╩╩╚═╚═╝╚═╝╩╩ ╩═╩╝                      ║'
    echo '║                 N V I D I A   P R E P                     ║'
    echo '╚═════════════════════════════════════════════════════════════╝'
    echo -e "${COLOR_RESET}"
}

show_command() {
    echo -e "${COLOR_CMD}[RUNNING] → $1${COLOR_RESET}"
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

prompt_continue() {
    echo -e "${COLOR_PROMPT}"
    read -p "Press Enter to continue..."
    echo -e "${COLOR_RESET}"
}

# --- Action Functions ---

# 1. Blacklist Nouveau
blacklist_nouveau() {
    info "Checking Nouveau blacklist..."
    local BLACKLIST_FILE="/etc/modprobe.d/blacklist-nvidia-nouveau.conf"
    local LINE1="blacklist nouveau"
    local LINE2="options nouveau modeset=0"
    local MODIFIED=0

    # Ensure file exists (create if not)
    if [ ! -f "$BLACKLIST_FILE" ]; then
        show_command "sudo touch $BLACKLIST_FILE"
        sudo touch "$BLACKLIST_FILE"
        if [ $? -ne 0 ]; then
            error "Failed to create blacklist file $BLACKLIST_FILE. Check permissions."
            return 1
        fi
        info "Created $BLACKLIST_FILE."
        MODIFIED=1
    fi

    # Check for line 1
    if ! grep -q "^${LINE1}$" "$BLACKLIST_FILE"; then
        info "Adding '$LINE1' to $BLACKLIST_FILE"
        show_command "echo \"$LINE1\" | sudo tee -a $BLACKLIST_FILE > /dev/null"
        echo "$LINE1" | sudo tee -a "$BLACKLIST_FILE" > /dev/null
        if [ $? -ne 0 ]; then error "Failed to add '$LINE1'."; return 1; fi
        MODIFIED=1
    fi

    # Check for line 2
    if ! grep -q "^${LINE2}$" "$BLACKLIST_FILE"; then
        info "Adding '$LINE2' to $BLACKLIST_FILE"
        show_command "echo \"$LINE2\" | sudo tee -a $BLACKLIST_FILE > /dev/null"
        echo "$LINE2" | sudo tee -a "$BLACKLIST_FILE" > /dev/null
        if [ $? -ne 0 ]; then error "Failed to add '$LINE2'."; return 1; fi
        MODIFIED=1
    fi

    if [ $MODIFIED -eq 1 ]; then
        success "Nouveau blacklist configured in $BLACKLIST_FILE."
    else
        success "Nouveau blacklist already configured."
    fi
    return 0
}

# 2. Add Initramfs Modules
add_initramfs_modules() {
    info "Checking initramfs modules configuration..."
    local MODULES_FILE="/etc/initramfs-tools/modules"
    local MODULES_NEEDED=("nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm")
    local MODIFIED=0

    if [ ! -w "$MODULES_FILE" ]; then
         # Check if we can write with sudo, requires root access to the file itself eventually
         if ! sudo test -w "$MODULES_FILE" ; then
              error "Cannot write to $MODULES_FILE, even with sudo. Check permissions/existence."
              info "Attempting to create $MODULES_FILE if it doesn't exist..."
              show_command "sudo touch $MODULES_FILE"
              sudo touch "$MODULES_FILE" || return 1 # Exit function if touch fails
              if ! sudo test -w "$MODULES_FILE" ; then
                   error "Still cannot write to $MODULES_FILE after touch. Aborting module add."
                   return 1
              fi
         fi
    fi

    for module in "${MODULES_NEEDED[@]}"; do
        if ! grep -q "^${module}$" "$MODULES_FILE"; then
            info "Adding '$module' to $MODULES_FILE"
            show_command "echo \"$module\" | sudo tee -a $MODULES_FILE > /dev/null"
            echo "$module" | sudo tee -a "$MODULES_FILE" > /dev/null
            if [ $? -ne 0 ]; then
                error "Failed to add '$module'. Check permissions."
                # Don't necessarily return 1 here, try to add others
            else
                MODIFIED=1
            fi
        fi
    done

    if [ $MODIFIED -eq 1 ]; then
        success "Required Nvidia modules added/verified in $MODULES_FILE."
        info "Updating initramfs is recommended now."
        echo -e "${COLOR_PROMPT}Do you want to run 'update-initramfs -u -k all' now? (y/N): ${COLOR_RESET}"
        read RUN_UPDATE
        if [[ "$RUN_UPDATE" =~ ^[Yy]$ ]]; then
            show_command "sudo update-initramfs -u -k all"
            if sudo update-initramfs -u -k all; then
                success "Initramfs updated."
            else
                error "Initramfs update failed!"
                return 1
            fi
        else
            info "Skipping initramfs update. Remember to run it manually!"
        fi
    else
        success "Required Nvidia modules already present in $MODULES_FILE."
    fi
    return 0
}

# 3. Run Nvidia Diagnostics (Embedded)
run_diagnostics() {
    info "Running Nvidia Diagnostics..."
    echo "--------------------------------------------------"
    # --- Start Embedded Diagnostic Script ---
    echo "uname -a:"
    uname -a
    echo

    echo "/proc/version:"
    cat /proc/version 2>/dev/null || error "Could not read /proc/version"
    echo

    if [ -e /proc/driver/nvidia/version ]; then
        echo "/proc/driver/nvidia/version:"
        cat /proc/driver/nvidia/version 2>/dev/null || error "Could not read /proc/driver/nvidia/version"
        echo
    else
         info "/proc/driver/nvidia/version not found (driver likely not loaded)."
         echo
    fi

    if (lspci --version) > /dev/null 2>&1; then
        echo "lspci 'display controller [030?]':"
        # Run lspci with sudo if available, otherwise try without
        local LSPCI_CMD="lspci"
        if command -v sudo > /dev/null && [ "$(id -u)" -ne 0 ]; then
            LSPCI_CMD="sudo lspci"
            info "Using sudo for lspci..."
        fi
        for device in $($LSPCI_CMD -mn | awk '{ if ($2 ~ "\"030[0-2]\"") { print $1 } }'); do
            LC_ALL=C $LSPCI_CMD -vvnn -s $device || error "lspci command failed for $device"
        done
    else
         error "lspci command not found."
    fi
    echo

    if [ -x /bin/dmesg ]; then
        echo "dmesg (nvidia/nvrm/agp/vga):"
        # Run dmesg with sudo if available
        local DMESG_CMD="dmesg"
         if command -v sudo > /dev/null && [ "$(id -u)" -ne 0 ]; then
            DMESG_CMD="sudo dmesg"
            info "Using sudo for dmesg..."
        fi
        $DMESG_CMD | grep -iE 'nvidia|nvrm|agp|vga' || info "No relevant lines found in dmesg."
        echo
    else
         error "dmesg command not found."
    fi

    echo "Device node permissions:"
    ls -l /dev/dri/* /dev/nvidia* 2>/dev/null || info "No /dev/dri or /dev/nvidia nodes found."
    getent group video || info "Group 'video' not found."
    echo

    echo "Alternative 'nvidia':"
    update-alternatives --display nvidia || error "update-alternatives failed for nvidia"
    echo

    echo "Alternative 'glx':"
    update-alternatives --display glx || error "update-alternatives failed for glx"
    echo

    echo "Installed OpenGL/NVIDIA Libraries (Checking common paths):"
    ls -ld \
        /etc/alternatives/glx* \
        /etc/alternatives/nvidia* \
        /etc/ld.so.conf.d/*nvidia*.conf \
        /etc/ld.so.conf.d/*GL*.conf \
        /usr/lib/x86_64-linux-gnu/libnvidia* \
        /usr/lib/x86_64-linux-gnu/libGL* \
        /usr/lib/x86_64-linux-gnu/libEGL* \
        /usr/lib/x86_64-linux-gnu/nvidia/current/* \
        /usr/lib/i386-linux-gnu/libnvidia* \
        /usr/lib/i386-linux-gnu/libGL* \
        /usr/lib/i386-linux-gnu/libEGL* \
        /usr/lib/xorg/modules/drivers/nvidia_drv.so \
        /usr/lib/xorg/modules/extensions/libglxserver_nvidia.so \
        /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
        2>/dev/null || info "Some standard library paths not found."
    echo

    echo "/etc/modprobe.d/ contents:"
    ls -la /etc/modprobe.d/
    echo
    echo "Relevant lines in /etc/modprobe.d/:"
    grep -rHiE 'nvidia|nouveau' /etc/modprobe.d/ --color=never || info "No nvidia/nouveau lines found."
    echo

    echo "/etc/modules-load.d/ contents:"
    ls -la /etc/modules /etc/modules-load.d/ 2>/dev/null || info "/etc/modules or /etc/modules-load.d not found."
    echo
    echo "Relevant lines in /etc/modules*:"
    grep -rHiE 'nvidia|nouveau' /etc/modules /etc/modules-load.d/ --color=never 2>/dev/null || info "No nvidia/nouveau lines found."
    echo

    echo "Checking for nvidia-installer files:"
    ls -la /usr/bin/nvidia-installer /usr/bin/nvidia-uninstall /var/lib/nvidia 2>/dev/null || info "Standard nvidia-installer files not found."
    echo

    echo "Relevant Config/Log Files:"
    echo
    local files_to_check=( \
        "/etc/X11/xorg.conf" \
        "/etc/X11/xorg.conf.d/*.conf" \
        "/usr/share/X11/xorg.conf.d/*.conf" \
        "/etc/initramfs-tools/modules" \
        "/etc/initramfs-tools/initramfs.conf" \
    )
    # Dynamically find recent Xorg logs
    shopt -s nullglob # Make globs expand to nothing if no match
    local xorg_logs_user=($(ls -dt $HOME/.local/share/xorg/Xorg.*.log* 2>/dev/null | head -n 2))
    local xorg_logs_sys=($(ls -dt /var/log/Xorg.*.log* 2>/dev/null | head -n 2))
    shopt -u nullglob # Turn off nullglob

    files_to_check+=("${xorg_logs_user[@]}")
    files_to_check+=("${xorg_logs_sys[@]}")

    for file_pattern in "${files_to_check[@]}"; do
         # Handle wildcards
         for file in $file_pattern; do
              if [ -f "$file" ] && [ -r "$file" ]; then
                   echo -e "${COLOR_INFO}<<<<<<<<<< $file >>>>>>>>>>${COLOR_RESET}"
                   cat "$file" || error "Could not read $file"
                   echo -e "${COLOR_INFO}^^^^^^^^^^ $file ^^^^^^^^^^${COLOR_RESET}"
                   echo
              elif [ "$file_pattern" != "$file" ]; then # Avoid printing error if glob didn't expand
                   true # Do nothing if pattern didn't match anything
              elif [ ! -e "$file" ] && [[ "$file_pattern" != *\** ]]; then # Only error if specific file missing
                   info "File not found or not readable: $file"
              fi
         done
    done

    if [ -d /run/systemd/system ] && command -v journalctl > /dev/null; then
        echo -e "${COLOR_INFO}<<<<<<<<<< Xorg (journald) >>>>>>>>>>${COLOR_RESET}"
        # Run journalctl with sudo if available
        local JOURNAL_CMD="journalctl"
        if command -v sudo > /dev/null && [ "$(id -u)" -ne 0 ]; then
            JOURNAL_CMD="sudo journalctl"
            info "Using sudo for journalctl..."
        fi
        $JOURNAL_CMD -b _COMM=Xorg --no-pager || error "Could not run journalctl for Xorg."
        echo -e "${COLOR_INFO}^^^^^^^^^^ Xorg (journald) ^^^^^^^^^^${COLOR_RESET}"
        echo
    fi

    echo "Kernel modules: nvidia*.ko location:"
    find /lib/modules/$(uname -r) -name "nvidia*.ko" || info "No nvidia*.ko files found for current kernel."
    echo

    echo "lsmod | grep nvidia:"
    lsmod | grep nvidia || info "Nvidia modules not currently loaded."
    echo

    # --- End Embedded Diagnostic Script ---
    echo "--------------------------------------------------"
    success "Diagnostics complete."
    return 0
}

# --- Menu Function ---
show_menu() {
    echo -e "${COLOR_MENU}╔═══════ NVIDIA PREP MENU ═════════╗"
    echo "║                                  ║"
    echo "║ 1) Ensure Nouveau Blacklisted    ║"
    echo "║ 2) Add Nvidia Modules to Initramfs ║"
    echo "║ 3) Run Nvidia Diagnostics        ║"
    echo "║                                  ║"
    echo "║ 4) Run All Prep Steps (1 & 2)    ║"
    echo "║                                  ║"
    echo "║ 5) Exit                          ║"
    echo "║                                  ║"
    echo -e "╚══════════════════════════════════╝${COLOR_RESET}"
    echo
    echo -e "${COLOR_PROMPT}Select your action (1-5): ${COLOR_RESET}"
}

# --- Main Script Logic ---
banner
info "Checking for root privileges..."
if [ "$(id -u)" -ne 0 ]; then
    info "Some actions require root. Script will use 'sudo' when needed."
    # Verify sudo exists and works
    if ! command -v sudo > /dev/null; then
        error "'sudo' command not found. Please run script as root."
        exit 1
    fi
    if ! sudo -v > /dev/null 2>&1; then
       error "Could not obtain sudo privileges. Check password or sudoers config."
       exit 1
    fi
    success "Sudo available."
else
    success "Running as root."
fi
echo "" # newline

while true; do
    show_menu
    read CHOICE

    case $CHOICE in
        1)
            blacklist_nouveau
            prompt_continue
            ;;
        2)
            add_initramfs_modules
            prompt_continue
            ;;
        3)
            run_diagnostics
            prompt_continue
            ;;
        4)
            info "Running all prep steps..."
            blacklist_nouveau && add_initramfs_modules
            # Don't prompt here, let the add_initramfs_modules handle its prompt if needed
            info "All prep steps attempted."
            prompt_continue
            ;;
        5)
            info "Exiting script. We out! 🔥"
            exit 0
            ;;
        *)
            error "Invalid choice, fam! Try again."
            prompt_continue
            ;;
    esac
done

exit 0
