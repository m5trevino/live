#!/usr/bin/env bash

# Focused Nvidia Install Script - v1.0
# Runs the 'Method B' install (Nvidia Repo Driver + Toolkit)
# ASSUMES SYSTEM IS CLEAN, PREPPED, and DISPLAY MANAGER is STOPPED.

# START ### CONFIGURATION ###
SCRIPT_VERSION="1.0 - Focused Install"
USER_HOME="" # Determined by check_sudo()
LOG_DIR=""   # Determined by check_sudo()
MAIN_LOG_FILE="" # Determined by check_sudo()
# FINISH ### CONFIGURATION ###

# START ### COLOR PALETTE ###
GREEN='\e[92m'    # Bright Green (Success, Info)
PURPLE='\e[95m'   # Bright Purple (Section Headers, Highlights)
CYAN='\e[96m'     # Bright Cyan (Commands, Explanations)
YELLOW='\e[93m'   # Bright Yellow (Prompts, Warnings)
RED='\e[91m'      # Bright Red (ERRORS, Critical Warnings)
NC='\e[0m'       # No Color (Reset)
# FINISH ### COLOR PALETTE ###

# START ### HELPER FUNCTIONS ###
print_color() { echo -e "${1}${2}${NC}" >&2; }

log_msg() {
    if [[ -z "$MAIN_LOG_FILE" ]]; then echo "FATAL: Log file not initialized!" >&2; exit 1; fi
    local level="$1"; local message="$2"; local log_line;
    log_line="$(date +'%Y-%m-%d %H:%M:%S') [$level] - $message"
    echo "$log_line" >> "$MAIN_LOG_FILE"
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        local color="$YELLOW"; [[ "$level" == "ERROR" ]] && color="$RED"
        print_color "$color" "[$level] $message"
    fi
}

prompt_confirm() {
    local message="$1"; local default_choice="${2:-N}"; local psfx="[y/N]";
    [[ "$default_choice" =~ ^[Yy]$ ]] && psfx="[Y/n]"
    while true; do
        echo -en "$(print_color "$YELLOW" "$message $psfx: ")" >&2
        read -r choice < /dev/tty
        choice="${choice:-$default_choice}";
        case "$choice" in
            [Yy]*) log_msg "USER" "Confirmed: '$message'"; return 0;;
            [Nn]*) log_msg "USER" "Cancelled: '$message'"; return 1;;
            *) print_color "$RED" "Invalid input.";;
        esac
    done
}

check_sudo() {
    if [[ -z "$SUDO_USER" || "$EUID" -ne 0 ]]; then print_color "$RED" "Error: This script must be run using sudo."; exit 1; fi
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then USER_HOME=$(eval echo ~"$SUDO_USER"); fi; # Basic fallback
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then print_color "$RED" "FATAL: Could not determine home directory for user '$SUDO_USER'."; exit 1; fi
    LOG_DIR="$USER_HOME/gpu_manager_logs"; MAIN_LOG_FILE="$LOG_DIR/focused_install_$(date +%Y%m%d_%H%M%S).log";
    mkdir -p "$LOG_DIR" || { print_color "$RED" "FATAL: Could not create log directory '$LOG_DIR'"; exit 1; };
    touch "$MAIN_LOG_FILE" || { print_color "$RED" "FATAL: Could not create main log file '$MAIN_LOG_FILE'"; exit 1; };
    chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR" "$MAIN_LOG_FILE" || print_color "$YELLOW" "Warn: Could not chown log dir/file to $SUDO_USER."
    log_msg "INFO" "Sudo check passed. User: $SUDO_USER. Home: $USER_HOME. Logging: $MAIN_LOG_FILE."
}

run_command() {
    # Simplified version for this focused script
    local cmd_string="$1"
    local cmd_desc="${2:-Command}"
    local status

    log_msg "EXEC" "($cmd_desc): $cmd_string"
    print_color "$CYAN" "Running: $cmd_string"
    print_color "$CYAN" "(Output will appear below and in $MAIN_LOG_FILE)"

    # Execute and capture status, tee output to log and TTY
    local temp_status_file; temp_status_file=$(mktemp)
    local pipe_chain="(eval \"$cmd_string\"; echo \$? > \"$temp_status_file\") 2>&1 | tee -a \"$MAIN_LOG_FILE\" > /dev/tty"

    bash -c "$pipe_chain"
    status=$(cat "$temp_status_file" 2>/dev/null)
    [[ -z "$status" ]] && status=1 # Assume failure if status capture failed
    rm "$temp_status_file"

    log_msg "INFO" "($cmd_desc) finished status: $status"
    if [[ "$status" -ne 0 ]]; then
        print_color "$RED" "Command ($cmd_desc) failed! Status: $status"
        print_color "$YELLOW" "Check output above and log file: $MAIN_LOG_FILE"
        return "$status"
    fi
    return 0
}
# FINISH ### HELPER FUNCTIONS ###

# START ### NVIDIA REPO SETUP AND DRIVER INSTALL ###
setup_repo_and_install_driver() {
    print_color "$PURPLE" "\n--- Step 1: Setup Nvidia Repo & Install Driver ---";
    log_msg "INFO" "Starting Nvidia Repo setup and cuda-drivers install."

    print_color "$CYAN" "Checking/Installing prerequisite tools (wget, gnupg)...";
    run_command "apt-get update" "Pre-update for repo tools" || { print_color "$YELLOW" "Warn: apt update failed."; } # Continue if update fails
    run_command "apt-get install -y software-properties-common gnupg wget" "Install common tools" || { log_msg "ERROR" "Failed prerequisite tools install."; return 1; }

    print_color "$CYAN" "Checking/Installing Nvidia repo keyring...";
    local os_codename; os_codename=$(lsb_release -cs);
    if [[ -z "$os_codename" ]]; then print_color "$RED" "Cannot determine OS codename."; log_msg "ERROR" "Cannot get OS codename."; return 1; fi
    local repo_base_url="https://developer.download.nvidia.com/compute/cuda/repos"
    local keyring_deb="cuda-keyring_1.1-1_all.deb"
    local keyring_url="${repo_base_url}/${os_codename}/x86_64/${keyring_deb}"
    local keyring_installed=false
    if dpkg-query -W -f='${Status}' cuda-keyring 2>/dev/null | grep -q "ok installed"; then
        log_msg "INFO" "cuda-keyring already installed."; keyring_installed=true;
    else
        print_color "$YELLOW" "'cuda-keyring' not found. Attempting download and install...";
        if ! run_command "wget $keyring_url -O /tmp/${keyring_deb}" "Download Keyring"; then log_msg "ERROR" "Keyring download failed."; return 1; fi
        if ! run_command "dpkg -i /tmp/${keyring_deb}" "Install Keyring"; then log_msg "ERROR" "Keyring install failed."; rm -f /tmp/${keyring_deb}; return 1; fi
        rm -f /tmp/${keyring_deb}; log_msg "INFO" "cuda-keyring installed."; keyring_installed=true;
    fi
    if [[ "$keyring_installed" != true ]]; then print_color "$RED" "Failed to ensure cuda-keyring is installed."; return 1; fi

    print_color "$CYAN" "Checking/Adding Nvidia CUDA repository file...";
    local repo_file="/etc/apt/sources.list.d/cuda-${os_codename}-x86_64.list"
    local repo_line="deb ${repo_base_url}/${os_codename}/x86_64/ /"
    local repo_changed=false
    if [[ ! -f "$repo_file" ]]; then
         print_color "$CYAN" "Adding Nvidia CUDA repository file: $repo_file...";
         if echo "$repo_line" | sudo tee "$repo_file" > /dev/null; then
            sudo chown root:root "$repo_file" && sudo chmod 644 "$repo_file"
            log_msg "INFO" "Nvidia CUDA repository file created."; repo_changed=true;
         else
            log_msg "ERROR" "Failed to create CUDA repository file: $repo_file."; return 1;
         fi
    else
        log_msg "INFO" "Nvidia CUDA repository file already exists: $repo_file"
        if ! grep -qxF "$repo_line" "$repo_file"; then
            print_color "$YELLOW" "Repo file exists but missing expected line. Appending..."
            if echo "$repo_line" | sudo tee -a "$repo_file" > /dev/null; then
                 log_msg "INFO" "Appended Nvidia repo line to $repo_file"; repo_changed=true;
            else
                 log_msg "ERROR" "Failed to append repo line to $repo_file"; return 1;
            fi
        fi
    fi

    if [[ "$repo_changed" == true ]]; then
        print_color "$CYAN" "Updating APT cache after repo configuration...";
        run_command "apt-get update" "Update after repo setup" || print_color "$YELLOW" "Warn: apt update failed."
    fi

    print_color "$CYAN" "Installing 'cuda-drivers' meta-package from Nvidia repo...";
    if run_command "apt-get install cuda-drivers -y" "Install cuda-drivers"; then
        log_msg "INFO" "cuda-drivers install completed.";
        print_color "$CYAN" "Verifying DKMS status after driver install..."; sleep 2;
        run_command "dkms status" "DKMS Status Check"
        if dkms status | grep -q "nvidia/"; then
             print_color "$GREEN" "DKMS module seems built."; log_msg "INFO" "DKMS check PASSED post cuda-drivers install."; return 0;
        else
             print_color "$RED" "ERROR: DKMS module NOT found after cuda-drivers install!"; log_msg "ERROR" "DKMS check FAILED post cuda-drivers install."; return 1;
        fi
    else
        log_msg "ERROR" "apt-get install cuda-drivers failed.";
        print_color "$YELLOW" "Attempting fix...";
        run_command "dpkg --configure -a" "dpkg configure"
        run_command "apt-get install -f -y" "apt fix"
        return 1;
    fi
}
# FINISH ### NVIDIA REPO SETUP AND DRIVER INSTALL ###

# START ### CUDA TOOLKIT INSTALL CORE ###
install_cuda_toolkit_core() {
    local toolkit_pkg="cuda-toolkit" # Using the generic meta-package
    print_color "$PURPLE" "\n--- Step 2: Install CUDA Toolkit ---";
    log_msg "INFO" "Starting CUDA Toolkit install ($toolkit_pkg)."

    # We assume repo is set up from previous step, just install
    print_color "$CYAN" "Running: apt-get install $toolkit_pkg -y";
    if run_command "apt-get install $toolkit_pkg -y" "Install CUDA Toolkit"; then
        log_msg "INFO" "CUDA Toolkit install ($toolkit_pkg) finished.";
        print_color "$GREEN" "CUDA Toolkit install finished.";
        print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
        local nvcc_path; nvcc_path=$(command -v nvcc || echo "/usr/local/cuda/bin/nvcc");
        if [[ -x "$nvcc_path" ]]; then
             local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release');
             print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
        else
             print_color "$YELLOW" "nvcc not found in PATH or default location.";
             print_color "$YELLOW" "IMPORTANT: Add export PATH=/usr/local/cuda/bin:\$PATH to ~/.bashrc";
             print_color "$YELLOW" "And export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH";
             log_msg "WARN" "nvcc check FAILED. Manual PATH/LD_LIBRARY_PATH setup needed.";
             # Don't fail the whole script here, just warn user.
        fi;
        return 0;
    else
        log_msg "ERROR" "apt-get install $toolkit_pkg failed."; return 1;
    fi
}
# FINISH ### CUDA TOOLKIT INSTALL CORE ###

# START ### MAIN EXECUTION ###
main() {
    check_sudo
    log_msg "INFO" "====== Focused Install Script Started (v${SCRIPT_VERSION}) ======"
    print_color "$PURPLE" "=== Focused Nvidia Install (Nvidia Repo Method) ==="
    print_color "$YELLOW" "This script assumes you have ALREADY cleaned the system, stopped the DM, and prepped the build env."
    if ! prompt_confirm "Ready to proceed with installation?"; then exit 1; fi

    local overall_status=0

    # Step 1: Setup Repo and Install Driver
    setup_repo_and_install_driver || overall_status=$?
    if [[ $overall_status -ne 0 ]]; then
        print_color "$RED" "INSTALL FAILED: Driver installation step failed.";
        log_msg "ERROR" "Install FAILED at Step 1 (Driver Install)."
        exit 1;
    fi
    print_color "$GREEN" "Driver Installation Step Successful."

    # Step 2: Install CUDA Toolkit
    install_cuda_toolkit_core || overall_status=$?
     if [[ $overall_status -ne 0 ]]; then
        print_color "$RED" "INSTALL FAILED: CUDA Toolkit installation step failed.";
        log_msg "ERROR" "Install FAILED at Step 2 (Toolkit Install)."
        exit 1;
    fi
    print_color "$GREEN" "CUDA Toolkit Installation Step Successful."

    # Step 3: Update Initramfs
    print_color "$PURPLE" "\n--- Step 3: Update Initramfs ---";
    log_msg "INFO" "Updating initramfs."
    if run_command "update-initramfs -u -k all" "Update Initramfs Post-Install"; then
        print_color "$GREEN" "Initramfs update successful."; log_msg "INFO" "Initramfs update successful.";
    else
        print_color "$YELLOW" "Warning: Initramfs update failed. Check logs."; log_msg "WARN" "Initramfs update failed post-install.";
        # Don't exit, just warn.
    fi

    print_color "$GREEN" "\n--- INSTALLATION COMPLETE ---"
    log_msg "INFO" "Focused Install Script finished."
    print_color "$YELLOW" "Reboot is REQUIRED now."
    print_color "$CYAN" "After reboot, verify with 'nvidia-smi' and 'nvcc --version'."
    print_color "$YELLOW" "Consider using Kernel Pinning (via nvidia-mybitch.sh Menu 9 -> 6) to lock the current working kernel."
    exit 0
}

main
# FINISH ### MAIN EXECUTION ###

