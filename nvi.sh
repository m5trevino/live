#!/usr/bin/env bash

# NVIDIA Management Script - "nvidia-mybitch.sh" v1.11
# Built for the streets, respects the hustle. No more bullshit placeholders.

# START ### CONFIGURATION ###
SCRIPT_VERSION="1.11" # Guided Install, Kernel Pinning, Enhanced Clean
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
    # Check if log file path is set, exit if not (should be set by check_sudo)
    if [[ -z "$MAIN_LOG_FILE" ]]; then echo "FATAL: Main log file path not initialized!" >&2; exit 1; fi
    # Check if log file is writable, attempt to fix if not
    if [[ ! -w "$MAIN_LOG_FILE" && -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE not writable. Attempting chown..." >&2
         # Need sudo user context here, should be available
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "FATAL: Failed to chown log file. Cannot log." >&2; exit 1; }
         if [[ ! -w "$MAIN_LOG_FILE" ]]; then echo "FATAL: Log file still not writable after chown. Cannot log." >&2; exit 1; fi
    elif [[ ! -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE does not exist. Attempting touch..." >&2
         touch "$MAIN_LOG_FILE" || { echo "FATAL: Failed to touch log file. Cannot log." >&2; exit 1; }
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "Warning: Failed to chown new log file." >&2; }
    fi

    local level="$1"; local message="$2"; local log_line;
    log_line="$(date +'%Y-%m-%d %H:%M:%S') [$level] - $message"
    # Append to the log file
    echo "$log_line" >> "$MAIN_LOG_FILE"
    # Print ERROR and WARN messages to stderr as well, with color
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        local color="$YELLOW"; [[ "$level" == "ERROR" ]] && color="$RED"
        print_color "$color" "[$level] $message"
    fi
}


prompt_confirm() {
    local message="$1"; local default_choice="${2:-N}"; local psfx="[y/N]";
    [[ "$default_choice" =~ ^[Yy]$ ]] && psfx="[Y/n]"
    while true; do
        # Redirect stdin from /dev/tty to ensure it reads from keyboard even if script input is piped
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

type_effect() {
    local text="$1"; local delay="${2:-0.03}";
    # Check if NO_TYPE_EFFECT variable is set
    if [[ -z "$NO_TYPE_EFFECT" ]]; then
        local i;
        for (( i=0; i<${#text}; i++ )); do
             printf "%c" "${text:$i:1}" >&2;
             # Use awk for potentially more random sleep interval within bounds
             sleep "$(awk -v min=0.01 -v max="$delay" 'BEGIN{srand(); print min+rand()*(max-min)}')";
         done
    else
         # If NO_TYPE_EFFECT is set, just print the text without delay
         printf "%s" "$text" >&2;
    fi;
    # Always print a newline after the effect/text
    echo >&2;
}


check_sudo() {
    # Ensures script is run with sudo and determines the original user's home directory
    if [[ -z "$SUDO_USER" || "$EUID" -ne 0 ]]; then print_color "$RED" "Error: This script must be run using sudo."; exit 1; fi

    # Attempt to get the user's home directory reliably
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        # Log initial failure before fallback
        echo -e "${YELLOW}Warn: Could not reliably determine user home via getent for $SUDO_USER. Falling back...${NC}" >&2
        USER_HOME=$(eval echo ~"$SUDO_USER") # Fallback method
        if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
             print_color "$RED" "FATAL: Could not determine home directory for user '$SUDO_USER'. Exiting."
             # No log_msg here as logging isn't set up yet
             exit 1
        fi
    fi
    # Check if the determined home is /root, which might be wrong unless root logged in directly
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
        print_color "$YELLOW" "Warning: Determined user home is /root, but sudo user is $SUDO_USER. This might be incorrect."
        # Log this warning once logging is initialized below
     fi

    LOG_DIR="$USER_HOME/gpu_manager_logs"; MAIN_LOG_FILE="$LOG_DIR/nvidia-mybitch_main_$(date +%Y%m%d_%H%M%S).log";
    # Ensure log directory exists
    mkdir -p "$LOG_DIR" || { print_color "$RED" "FATAL: Could not create log directory '$LOG_DIR'"; exit 1; };
    # Create log file
    touch "$MAIN_LOG_FILE" || { print_color "$RED" "FATAL: Could not create main log file '$MAIN_LOG_FILE'"; exit 1; };
    # Change ownership to the original user so they can access logs without sudo later
    chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR" "$MAIN_LOG_FILE" || print_color "$YELLOW" "Warn: Could not chown log directory/file to $SUDO_USER."

    # Now that logging is set up, log the earlier warning if needed
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
         log_msg "WARN" "Determined user home is /root, but sudo user is $SUDO_USER."
     fi
    log_msg "INFO" "Sudo check passed. Original User: $SUDO_USER. User Home: $USER_HOME. Logging to: $MAIN_LOG_FILE."
}

check_tty() {
    # Check if running in a TTY and not under X/Wayland (DISPLAY is set)
    # Allow override if user confirms
    if ! tty -s; then
        log_msg "WARN" "Script not running in a TTY (stdin is not a terminal)."
        print_color "$YELLOW" "Warning: Not running in a TTY. Interactive prompts might behave unexpectedly."
        if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Not TTY."; return 1; fi
    elif [[ -n "$DISPLAY" ]]; then
         log_msg "WARN" "DISPLAY environment variable is set ($DISPLAY). Running under X/Wayland?"
         print_color "$YELLOW" "Warning: Running inside a graphical session? Some operations (like stopping DM) work best from a TTY."
         if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Running under GUI."; return 1; fi
    fi
    return 0;
}


get_display_manager() {
  local detected_dm=""; local final_dm=""; local user_input; log_msg "INFO" "Detecting DM...";
  # Check for common DMs via systemctl active state
  if systemctl list-units --type=service --state=active | grep -q -E 'gdm[0-9]*\.service|gdm\.service'; then detected_dm="gdm3.service";
  elif systemctl list-units --type=service --state=active | grep -q 'sddm\.service'; then detected_dm="sddm.service";
  elif systemctl list-units --type=service --state=active | grep -q 'lightdm\.service'; then detected_dm="lightdm.service";
  # Add other DMs here if needed (e.g., lxdm)
  fi;

  if [[ -n "$detected_dm" ]]; then
      log_msg "INFO" "Detected active DM: $detected_dm";
      read -r -p "$(print_color "$YELLOW" "Detected active Display Manager '$detected_dm'. Is this correct? [Y/n]: ")" confirm < /dev/tty; confirm="${confirm:-Y}";
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
           final_dm="$detected_dm"; log_msg "USER" "Confirmed DM: $final_dm";
      else
           log_msg "USER" "Rejected detected DM."; detected_dm=""; # Clear detected if rejected
      fi;
  fi;

  # If no DM confirmed or detected
  if [[ -z "$final_dm" ]]; then
       print_color "$YELLOW" "Could not detect/confirm Display Manager.";
       read -r -p "$(print_color "$YELLOW" "Enter your Display Manager service name (e.g., gdm3.service, sddm.service, lightdm.service) or leave blank to skip DM operations: ")" user_input < /dev/tty;
       if [[ -n "$user_input" ]]; then
            # Append .service if missing
            if [[ ! "$user_input" == *".service" ]]; then final_dm="${user_input}.service"; else final_dm="$user_input"; fi;
            log_msg "USER" "Manual DM entry: $final_dm";
            # Optional: Add a basic check if the service name seems valid?
            # if ! systemctl list-unit-files | grep -q "^${final_dm}"; then print_color "$YELLOW" "Warning: Service '$final_dm' not found by systemctl."; fi
       else
           print_color "$YELLOW" "Skipping Display Manager operations."; log_msg "USER" "Skipped DM entry."; final_dm="";
       fi;
  fi;

  echo "$final_dm"; # Return the determined DM name (or empty string)
  if [[ -n "$final_dm" ]]; then return 0; else return 1; fi; # Return status indicates if a DM was identified
}

run_command() {
    local cmd_string="$1"
    local log_output_to_file="${2:-false}" # Controls logging command's stdout/stderr to SEPARATE file (true/false)
    local cmd_desc="${3:-Command}"
    local tee_to_tty="${4:-true}" # Controls whether output is ALSO shown on screen (TTY)

    log_msg "EXEC" "($cmd_desc): $cmd_string"
    if [[ "$tee_to_tty" == true ]]; then
        print_color "$CYAN" "Running: $cmd_string"
    else
        # Avoid printing the command if output is hidden, just log it was executed
        log_msg "INFO" "Executing (output to log only): ($cmd_desc)"
    fi

    local output_log_file="${LOG_DIR}/cmd_output_$(date +%s)_$(echo "$cmd_desc" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c -50).log"
    local status
    # Base tee command always appends to main log file
    local tee_cmd_main="tee -a \"$MAIN_LOG_FILE\""
    local final_exec_cmd

    # Build the command execution string based on logging/display options
    # Pipe stderr to stdout using 2>&1 so both streams are processed by tee
    final_exec_cmd="(eval $cmd_string) 2>&1" # Start with the actual command + stderr redirection

    # Pipe through tee for main log file always
    final_exec_cmd+=" | $tee_cmd_main"

    # Optionally pipe through tee for separate log file
    if [[ "$log_output_to_file" == true ]]; then
        touch "$output_log_file" && chown "$SUDO_USER:$SUDO_USER" "$output_log_file" || log_msg "WARN" "Could not touch/chown output log $output_log_file"
        final_exec_cmd+=" | tee \"$output_log_file\""
        if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Logging output to $output_log_file AND main log AND screen)"
        else
             print_color "$CYAN" "(Logging output to $output_log_file AND main log ONLY)"
        fi
    else
         if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Command output will appear below and in main log)"
         else
              print_color "$CYAN" "(Command output to main log ONLY)"
          fi
    fi

    # Optionally redirect the final output to /dev/tty if requested
    if [[ "$tee_to_tty" == true ]]; then
        final_exec_cmd+=" > /dev/tty"
    else
        # If not teeing to tty, send final output to /dev/null to suppress it
        final_exec_cmd+=" > /dev/null"
    fi


    # Execute using bash -c to handle complex commands and pipes properly
    bash -c "$final_exec_cmd"
    # Get the exit status of the original 'eval' command using PIPESTATUS[0]
    # This requires the command to be the first element in the pipe handled by bash -c
    # We need to rethink how to capture the status correctly with all the tees.
    # A subshell approach might be better.

    # --- Alternative Status Capture (More reliable with complex pipes) ---
    local temp_status_file; temp_status_file=$(mktemp)
    final_exec_cmd="(eval $cmd_string; echo \$? > $temp_status_file) 2>&1 | $tee_cmd_main"
    if [[ "$log_output_to_file" == true ]]; then
        final_exec_cmd+=" | tee \"$output_log_file\""
    fi
    if [[ "$tee_to_tty" == true ]]; then
        final_exec_cmd+=" > /dev/tty"
    else
        final_exec_cmd+=" > /dev/null"
    fi

    bash -c "$final_exec_cmd"
    status=$(cat "$temp_status_file")
    rm "$temp_status_file"
    # --- End Alternative Status Capture ---


    log_msg "INFO" "($cmd_desc) finished status: $status"

    if [[ "$status" -ne 0 ]]; then
        # Ensure error message is visible even if tee_to_tty was false for the command itself
        print_color "$RED" "Command ($cmd_desc) failed! Status: $status"
        print_color "$YELLOW" "Check main log file: $MAIN_LOG_FILE"
        if [[ "$log_output_to_file" == true ]]; then print_color "$YELLOW" "Also check separate log: $output_log_file"; fi
        return "$status" # Use numeric return status
    fi

    # Clean up empty separate log file if it was created but not needed
    if [[ "$log_output_to_file" == true && -f "$output_log_file" && ! -s "$output_log_file" ]]; then
        log_msg "INFO" "Removing empty separate log file: $output_log_file"
        rm "$output_log_file" &> /dev/null
    fi
    return 0
}


view_log_file() {
    local log_path="$1"; local log_desc="$2";
    print_color "$CYAN" "Viewing: $log_desc ($log_path)"; log_msg "INFO" "Viewing log: $log_desc ($log_path)"
    if [[ ! -f "$log_path" ]]; then print_color "$YELLOW" "Not found: $log_path"; log_msg "WARN" "Log not found: $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Check read permissions for the effective user (root)
    if [[ ! -r "$log_path" ]]; then print_color "$RED" "Cannot read (check permissions): $log_path"; log_msg "ERROR" "Cannot read log (permissions?): $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Use less with flags for better viewing, ensuring it reads from TTY
    less -Rf "$log_path" < /dev/tty
}
# FINISH ### HELPER FUNCTIONS ###

# START ### MODULE DISPLAY MANAGER ###
run_manage_display_manager() {
    print_color "$PURPLE" "\n--- Module: Display Manager Control ---"; log_msg "INFO" "Starting DM Control.";
    local dm; dm=$(get_display_manager); if [[ $? -ne 0 || -z "$dm" ]]; then print_color "$YELLOW" "Cannot manage Display Manager (not found or skipped)."; return 1; fi;
    print_color "$YELLOW" "Action for Display Manager '$dm':"; echo " 1) Stop"; echo " 2) Start"; echo " 3) Status"; echo " 4) Cancel"; local choice;
    read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;
    case "$choice" in
        1) if ! check_tty; then return 1; fi; # Extra check before stopping DM
           run_command "systemctl stop $dm" false "Stop DM";;
        2) run_command "systemctl start $dm" false "Start DM";;
        3) run_command "systemctl status $dm --no-pager" false "DM Status";; # Added no-pager
        4) log_msg "USER" "Cancelled DM action."; return 1;; *) print_color "$RED" "Invalid."; return 1;;
    esac; return $?;
}
# FINISH ### MODULE DISPLAY MANAGER ###

# START ### MODULE PREPARE BUILD ENV ###
run_prepare_build_env() {
    print_color "$PURPLE" "\n--- Module: Prepare Build Environment ---"; log_msg "INFO" "Starting Build Env Prep.";
    print_color "$CYAN" "Ensures DKMS, build-essential, and headers for CURRENT kernel are installed.";
    local k; k=$(uname -r); local hdr="linux-headers-${k}"; local req="dkms build-essential ${hdr}";
    print_color "$CYAN" "Checking required packages (dkms, build-essential, $hdr)..."; log_msg "INFO" "Checking build env packages: $req"; local missing="";
    for pkg in dkms build-essential "$hdr"; do if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then missing+="$pkg "; fi; done;
    if [[ -n "$missing" ]]; then log_msg "WARN" "Missing build env packages: ${missing% }"; print_color "$YELLOW" "Missing packages: ${missing% }"; if ! prompt_confirm "Install/reinstall required packages?"; then log_msg "USER" "Skipped build env pkg install."; return 1; fi;
        print_color "$CYAN" "Running apt-get update & install..."; if ! run_command "apt-get update" false "Update build env"; then log_msg "WARN" "apt-get update failed."; fi; if ! run_command "apt-get install --reinstall -y $req" true "Install build env"; then log_msg "ERROR" "Build env install failed."; return 1; fi; log_msg "INFO" "Build env pkgs installed/reinstalled."; print_color "$GREEN" "Build env packages installed/reinstalled.";
    else log_msg "INFO" "Build env packages already present."; print_color "$GREEN" "Required build environment packages seem installed."; if prompt_confirm "Reinstall them anyway?"; then print_color "$CYAN" "Running apt-get update & reinstall..."; if ! run_command "apt-get update && apt-get install --reinstall -y $req" true "Reinstall build env"; then log_msg "ERROR" "Build env reinstall failed."; return 1; fi; log_msg "INFO" "Build env packages reinstalled."; print_color "$GREEN" "Build env packages reinstalled."; fi; fi;
    print_color "$CYAN" "Checking DKMS status..."; run_command "dkms status" false "DKMS Status Check"; print_color "$GREEN" "\n--- Build Env Prep Finished ---"; log_msg "INFO" "Build Env Prep finished."; return 0;
}
# FINISH ### MODULE PREPARE BUILD ENV ###

# START ### MODULE MANAGE GCC ###
run_manage_gcc() {
    print_color "$PURPLE" "\n--- Module: Manage GCC Version ---"; log_msg "INFO" "Starting GCC Mgmt.";
    local gcc; gcc=$(gcc --version | head -n1); local gpp; gpp=$(g++ --version | head -n1); print_color "$CYAN" "Current Default GCC: $gcc"; print_color "$CYAN" "Current Default G++: $gpp"; log_msg "INFO" "Current GCC: $gcc / G++: $gpp";
    print_color "$YELLOW" "\nNote: Nvidia drivers usually build with the default GCC for your Ubuntu release (e.g., 11 or 12 for 22.04).";
    print_color "$YELLOW" "Switching is generally only needed if a specific driver build fails and explicitly requires a different version.";
    echo "\nOptions:"; echo " 1) Check alternatives (installed versions)"; echo " 2) Install GCC/G++ 12 (if not present)"; echo " 3) Show manual switch commands (update-alternatives)"; echo " 4) Back"; local choice;
    read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;
    case "$choice" in
        1) print_color "$CYAN" "Checking gcc alternatives..."; run_command "update-alternatives --display gcc" false "GCC Alts"; print_color "$CYAN" "Checking g++ alternatives..."; run_command "update-alternatives --display g++" false "G++ Alts";;
        2) print_color "$CYAN" "Checking gcc-12/g++-12..."; if dpkg-query -W -f='${Status}' gcc-12 2>/dev/null | grep -q "ok installed" && dpkg-query -W -f='${Status}' g++-12 2>/dev/null | grep -q "ok installed"; then print_color "$GREEN" "gcc-12 & g++-12 already installed."; log_msg "INFO" "gcc-12/g++-12 already installed."; else print_color "$YELLOW" "gcc-12/g++-12 not found."; if prompt_confirm "Install gcc-12 and g++-12?"; then if run_command "apt-get update && apt-get install -y gcc-12 g++-12" true "Install GCC 12"; then log_msg "INFO" "Installed gcc-12/g++-12."; print_color "$YELLOW" "You may need to configure alternatives manually (Option 3) if needed."; else log_msg "ERROR" "Install GCC 12 failed."; fi; fi; fi;;
        3) print_color "$YELLOW" "MANUAL switch commands (run as needed):"; print_color "$CYAN" "# 1. Install versions if needed (see Option 2)"; print_color "$CYAN" "# 2. Add versions to alternatives system (adjust paths/priorities as needed):"; print_color "$CYAN" "sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 --slave /usr/bin/g++ g++ /usr/bin/g++-11"; print_color "$CYAN" "sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 --slave /usr/bin/g++ g++ /usr/bin/g++-12"; print_color "$CYAN" "# 3. Choose the default version interactively:"; print_color "$CYAN" "sudo update-alternatives --config gcc"; log_msg "INFO" "Showed manual GCC switch cmds.";;
        4) return 0;; *) print_color "$RED" "Invalid."; return 1;;
    esac; return 0;
}
# FINISH ### MODULE MANAGE GCC ###

# START ### MODULE NOUVEAU BLACKLIST ###
run_nouveau_blacklist() {
    print_color "$PURPLE" "\n--- Module: Blacklist Nouveau Driver ---"; log_msg "INFO" "Starting Nouveau Blacklist.";
    local conf="/etc/modprobe.d/blacklist-nvidia-nouveau-mybitch.conf"; # Use unique name
    local content="blacklist nouveau\noptions nouveau modeset=0";
    if [[ -f "$conf" ]]; then
         print_color "$YELLOW" "Blacklist file '$conf' already exists.";
         if ! prompt_confirm "Overwrite existing file?"; then log_msg "USER" "Skipped blacklist overwrite."; return 1; fi
    elif ! prompt_confirm "Create modprobe config '$conf' to blacklist Nouveau?"; then
         log_msg "USER" "Cancelled blacklist creation."; return 1;
    fi;
    print_color "$CYAN" "Creating/Overwriting $conf...";
    # Use run_command to create the file safely with sudo
    if run_command "echo -e \"$content\" | tee \"$conf\" > /dev/null" false "Write Nouveau Blacklist"; then
        print_color "$CYAN" "Running update-initramfs for all kernels...";
        if run_command "update-initramfs -u -k all" true "Update initramfs for blacklist"; then
            print_color "$GREEN" "Nouveau blacklisted successfully."; print_color "$YELLOW" "A reboot is required for changes to take effect."; log_msg "INFO" "Nouveau blacklisted ok."; return 0;
        else log_msg "ERROR" "update-initramfs failed after blacklist."; return 1; fi
    else log_msg "ERROR" "Write blacklist file failed."; return 1; fi
}
# FINISH ### MODULE NOUVEAU BLACKLIST ###

# START ### MODULE NVIDIA CLEANUP ###
run_nvidia_cleanup() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Deep Clean (Enhanced v1.11) ---"; log_msg "INFO" "Starting Enhanced Deep Clean.";
    print_color "$YELLOW" "This attempts to COMPLETELY remove Nvidia drivers, CUDA, configs, and DKMS entries.";
    if ! prompt_confirm "Proceed with Enhanced Deep Clean?"; then return 1; fi;
    # No TTY check here, user knows the risks
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then print_color "$CYAN" "Stopping Display Manager ($dm)..."; run_command "systemctl stop $dm" false "Stop DM Clean" || print_color "$YELLOW" "Warn: Stop DM failed, continuing anyway."; fi

    print_color "$CYAN" "\nStep 1: Removing DKMS modules..."; local dkms_mods; dkms_mods=$(dkms status | grep -Ei 'nvidia|nvidia-fs' | awk -F',|/' '{print $1"/"$2}' | sort -u); if [[ -n "$dkms_mods" ]]; then local fail=0; for mod in $dkms_mods; do print_color "$YELLOW" " Removing DKMS module: $mod"; run_command "dkms remove $mod --all" false "Remove DKMS $mod" || fail=1; done; if [[ $fail -eq 1 ]]; then log_msg "ERROR" "One or more DKMS remove commands failed."; fi; print_color "$CYAN" " Verifying DKMS status..."; sleep 1; if dkms status | grep -qEi 'nvidia|nvidia-fs'; then log_msg "WARN" "Nvidia DKMS modules may still remain!"; print_color "$YELLOW" "Warning: Nvidia DKMS modules may still remain! Check 'dkms status'."; else print_color "$GREEN" " All Nvidia DKMS modules removed."; log_msg "INFO" "Nvidia DKMS modules removed."; fi; else print_color "$GREEN" " No Nvidia DKMS modules found to remove."; log_msg "INFO" "No Nvidia DKMS modules found."; fi
    print_color "$CYAN" " Manually removing DKMS source tree (extra precaution)...";
    run_command "rm -rf /var/lib/dkms/nvidia*" false "Remove DKMS source"

    print_color "$CYAN" "\nStep 2: Finding & Purging related packages (Aggressive)...";
    # Expanded list with more potential packages
    local pkgs_pattern='nvidia|cuda|libnvidia|cublas|cufft|cufile|curand|cusolver|cusparse|npp|nvjpeg|libnvjitlink|nsight';
    local pkgs; pkgs=$(dpkg -l | grep -Ei "$pkgs_pattern" | grep -E '^ii' | awk '{print $2}' | tr '\n' ' ');
    if [[ -z "$pkgs" ]]; then print_color "$GREEN" " No related packages found via dpkg."; log_msg "INFO" "No packages found for purge."; else print_color "$YELLOW" " Found potentially related packages:"; echo "$pkgs" | fold -s -w 80 | sed 's/^/    /' >&2; log_msg "INFO" "Aggressive Purge list: $pkgs"; if ! prompt_confirm "Purge these packages?"; then log_msg "USER" "Cancelled package purge."; return 1; fi; print_color "$CYAN" " Purging packages (apt-get purge)..."; if ! run_command "apt-get purge --autoremove -y $pkgs" true "APT Purge Nvidia CUDA Aggressive"; then log_msg "ERROR" "apt purge failed."; print_color "$YELLOW" " Attempting fixes..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; print_color "$RED" "Purge failed, even after fixes."; return 1; else print_color "$GREEN" " Package purge complete."; log_msg "INFO" "APT purge done."; fi; fi

    print_color "$CYAN" "\nStep 3: Cleaning configuration & leftover files (Aggressive)...";
    local files_to_remove=(
        "/etc/modprobe.d/blacklist-nvidia*.conf"
        "/etc/modprobe.d/nvidia*.conf"
        "/etc/X11/xorg.conf*"
        "/etc/X11/xorg.conf.d/20-nvidia.conf" # Common location for generated config
        "/lib/udev/rules.d/*nvidia*.rules"
        "/etc/udev/rules.d/*nvidia*.rules"
        "/usr/share/X11/xorg.conf.d/*nvidia*.conf"
        "/usr/lib/nvidia" # Directories where drivers might install files
        "/usr/share/nvidia"
        "/etc/nvidia"     # Nvidia settings/profiles
        # Add more potentially problematic locations if known
    )
    print_color "$YELLOW" "Removing known config/rule/directory patterns:"
    for item in "${files_to_remove[@]}"; do
        # Handle directories, wildcards, and specific files
        if [[ "$item" == */ && -d "$item" ]]; then # Explicit directory check (though rm -rf handles it)
             run_command "rm -rfv $item" false "Remove Dir $item"
        elif [[ "$item" == *\* ]]; then # Pattern matching
             # Use find within the parent directory of the pattern
             local parent_dir; parent_dir=$(dirname "$item")
             local base_pattern; base_pattern=$(basename "$item")
             if [[ -d "$parent_dir" ]]; then
                  run_command "find \"$parent_dir\" -maxdepth 1 -name \"$base_pattern\" -print -delete" false "Remove Pattern $item"
             else
                  log_msg "INFO" "Parent directory $parent_dir for pattern $item not found, skipping."
             fi
        elif [[ -e "$item" || -L "$item" ]]; then # Specific file or symlink
             run_command "rm -vf $item" false "Remove File $item"
        else
             log_msg "INFO" "Item $item not found, skipping."
        fi
    done
    # Extra check for kernel modules that might be left
    print_color "$CYAN" " Searching for leftover Nvidia modules in current kernel dir (/lib/modules/$(uname -r)/)...";
    run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -ls" false "Find Leftover Modules"
    if prompt_confirm "Attempt to delete found leftover modules (Use with caution)?"; then
        run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -delete" false "Delete Leftover Modules"
    fi
    print_color "$GREEN" " Config/Leftover file cleanup attempted."

    print_color "$CYAN" "\nStep 4: Cleaning APT cache & fixing system...";
    run_command "apt-get clean" false "Clean APT Cache";
    run_command "apt-get --fix-broken install -y" true "Fix Broken Install";
    run_command "apt-get autoremove -y" true "Autoremove Orphans";
    run_command "dpkg --configure -a" false "Reconfigure dpkg";
    print_color "$GREEN" " System cleanup/fix steps done."

    print_color "$CYAN" "\nStep 5: Rebuilding initramfs for all kernels..."; if run_command "update-initramfs -u -k all" true "Update Initramfs After Clean"; then print_color "$GREEN" " Initramfs updated."; else log_msg "ERROR" "initramfs rebuild failed!"; fi

    print_color "$GREEN" "\n--- NVIDIA Enhanced Deep Clean Complete ---";
    print_color "$YELLOW" "Reboot strongly recommended before attempting reinstall."; log_msg "INFO" "Enhanced Deep Clean module finished.";
    if [[ -n "$dm" ]]; then if prompt_confirm "Attempt to restart Display Manager ($dm) now (might fail if X configs were removed)?" "N"; then run_command "systemctl start $dm" false "Restart DM after Clean"; fi; fi
    return 0
}
# FINISH ### MODULE NVIDIA CLEANUP ###

# START ### NVIDIA INSTALL FUNCTION ###
run_nvidia_install() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install ---"; log_msg "INFO" "Starting Driver Install.";
    print_color "$CYAN" "Pre-flight checks..."; if ! run_prepare_build_env; then log_msg "ERROR" "Aborting: Build env prep failed."; return 1; fi;
    local sb_stat; sb_stat=$(mokutil --sb-state 2>/dev/null || echo "Unknown"); log_msg "INFO" "Secure Boot: $sb_stat"; print_color "$CYAN" " Secure Boot: $sb_stat"; if [[ "$sb_stat" == "SecureBoot enabled" ]]; then print_color "$RED" " ERROR: Secure Boot ENABLED."; log_msg "ERROR" "Secure Boot enabled."; if ! prompt_confirm "Disable Secure Boot in BIOS/UEFI first? (Y=Exit now / n=Continue - INSTALL WILL LIKELY FAIL)"; then log_msg "WARN" "Continuing with Secure Boot enabled - Expect failure."; else return 1; fi; fi

    local driver_ver=""; local method=""
    # Select method first
    while true; do
        print_color "$YELLOW" "\nSelect install method:";
        echo " 1) APT (Ubuntu Repo - nvidia-driver-XXX)";
        echo " 2) Runfile ($USER_HOME - Offers download for specific versions)";
        echo " 3) APT (Nvidia Repo - cuda-drivers meta-package)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt_ubuntu"; break;;
            2) method="runfile"; break;;
            3) method="apt_nvidia"; break;;
            *) print_color "$RED" "Invalid.";;
        esac;
    done;
    log_msg "USER" "Selected method: $method"

    local status=1;
    if [[ "$method" == "apt_ubuntu" ]]; then
        # Ask for version specifically for this method
        while true; do print_color "$YELLOW" "\nSelect driver version for nvidia-driver-XXX package:"; echo " 1) 535"; echo " 2) 550"; echo " 3) 570"; read -r -p "$(print_color "$YELLOW" "Choice: ")" ver_choice < /dev/tty; case "$ver_choice" in 1) driver_ver="535"; break;; 2) driver_ver="550"; break;; 3) driver_ver="570"; break;; *) print_color "$RED" "Invalid.";; esac; done; log_msg "USER" "Selected driver version for APT Ubuntu: $driver_ver"
        install_nvidia_apt "$driver_ver"; status=$?;
    elif [[ "$method" == "apt_nvidia" ]]; then
        install_nvidia_apt_official_repo; status=$?; # Version is handled by cuda-drivers package
    elif [[ "$method" == "runfile" ]]; then
        install_nvidia_runfile; status=$?; # Runfile selection/download handles version inside
    else
        log_msg "ERROR" "Invalid method stored: $method"; status=1; # Should not happen
    fi

    if [[ $status -eq 0 ]]; then
         print_color "$GREEN" "\n--- Driver Install Complete ---";
         # Update initramfs after successful install is good practice
         if prompt_confirm "Run 'update-initramfs -u -k all' now?" "Y"; then
             run_command "update-initramfs -u -k all" true "Post-Install Initramfs Update"
         fi
         print_color "$YELLOW" "Reboot REQUIRED.";
         print_color "$CYAN" "Verify with 'nvidia-smi' after reboot.";
         log_msg "INFO" "Driver install success.";
    else
         print_color "$RED" "\n--- Driver Install Failed ---";
         log_msg "ERROR" "Driver install failed.";
    fi
    return $status
}
# FINISH ### NVIDIA INSTALL FUNCTION ###

# START ### NVIDIA INSTALL APT UBUNTU ###
install_nvidia_apt() {
    local ver="$1"; local pkg="nvidia-driver-$ver"
    print_color "$CYAN" "\nStarting Standard APT install (Ubuntu Repo): $pkg"; log_msg "INFO" "Starting APT Ubuntu install: $pkg"
    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for APT Ubuntu" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    run_command "apt-get update" false "Update before driver" || print_color "$YELLOW" "Warn: apt update failed."
    print_color "$CYAN" "Installing $pkg...";
    # Use 'apt-get' for better scriptability / consistency with purge
    if run_command "apt-get install $pkg -y" true "Install $pkg"; then # Log full output to separate file
        log_msg "INFO" "APT install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        # Check for the specific version installed via DKMS
        if echo "$dkms_out" | grep -q "nvidia/${ver}"; then print_color "$GREEN" "DKMS built ok for $ver."; log_msg "INFO" "DKMS PASSED for nvidia/${ver}."; return 0;
        # Fallback check in case version string has minor diffs (e.g. 535.183.01)
        elif echo "$dkms_out" | grep -q "nvidia/" | grep -q "${ver}\."; then print_color "$GREEN" "DKMS built ok (found ${ver}.x)."; log_msg "INFO" "DKMS PASSED (found nvidia/${ver}.x)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found for $ver!"; log_msg "ERROR" "DKMS FAILED for $ver."; print_color "$YELLOW" "Check logs (Option 11 -> 2)."; return 1; fi
    else log_msg "ERROR" "apt-get install $pkg failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi
}
# FINISH ### NVIDIA INSTALL APT UBUNTU ###

# START ### NVIDIA INSTALL APT NVIDIA REPO ###
# Installs driver using cuda-drivers from Nvidia repo, also sets up repo if needed.
install_nvidia_apt_official_repo() {
    # No version argument needed here.
    local setup_only="${1:-false}" # Optional arg to only setup repo without install

    if [[ "$setup_only" == true ]]; then
        print_color "$CYAN" "\nEnsuring Nvidia Repo is configured (Setup Only)..."; log_msg "INFO" "Starting Nvidia Repo setup check/config.";
    else
        print_color "$CYAN" "\nStarting Nvidia Repo APT install (using 'cuda-drivers')..."; log_msg "INFO" "Starting Nvidia Repo APT install.";
        if ! check_tty; then return 1; fi
        local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Nvidia Repo" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    fi

    print_color "$CYAN" "Checking/Installing prerequisite tools (wget, gnupg)...";
    run_command "apt-get update" false "Pre-update for repo tools" || print_color "$YELLOW" "Warn: apt update failed.";
    run_command "apt-get install -y software-properties-common gnupg wget" true "Install common tools" || { log_msg "ERROR" "Failed to install prerequisite tools"; return 1; }

    print_color "$CYAN" "Checking/Installing Nvidia repo keyring...";
    local os_codename; os_codename=$(lsb_release -cs);
    if [[ -z "$os_codename" ]]; then print_color "$RED" "Cannot determine OS codename."; log_msg "ERROR" "Cannot get OS codename."; return 1; fi
    local repo_base_url="https://developer.download.nvidia.com/compute/cuda/repos"
    local keyring_url="${repo_base_url}/${os_codename}/x86_64/cuda-keyring_1.1-1_all.deb"
    local keyring_installed=false
    if dpkg-query -W -f='${Status}' cuda-keyring 2>/dev/null | grep -q "ok installed"; then
        log_msg "INFO" "cuda-keyring already installed."; keyring_installed=true;
    else
        print_color "$YELLOW" "'cuda-keyring' not found. Attempting download and install...";
        if ! run_command "wget $keyring_url -O /tmp/cuda-keyring.deb" false "Download Keyring"; then log_msg "ERROR" "Keyring download failed."; return 1; fi
        if ! run_command "dpkg -i /tmp/cuda-keyring.deb" true "Install Keyring"; then log_msg "ERROR" "Keyring install failed."; rm -f /tmp/cuda-keyring.deb; return 1; fi
        rm -f /tmp/cuda-keyring.deb; log_msg "INFO" "cuda-keyring installed."; keyring_installed=true;
    fi
    if [[ "$keyring_installed" != true ]]; then print_color "$RED" "Failed to ensure cuda-keyring is installed."; return 1; fi

    print_color "$CYAN" "Checking/Adding Nvidia CUDA repository file...";
    local repo_file="/etc/apt/sources.list.d/cuda-${os_codename}-x86_64.list"
    local repo_line="deb ${repo_base_url}/${os_codename}/x86_64/ /"
    local repo_changed=false
    if [[ ! -f "$repo_file" ]]; then
         print_color "$CYAN" "Adding Nvidia CUDA repository file: $repo_file...";
         if run_command "echo \"$repo_line\" | tee \"$repo_file\" > /dev/null" false "Create Repo File"; then
             log_msg "INFO" "Nvidia CUDA repository file created."; repo_changed=true;
         else
             log_msg "ERROR" "Failed to create CUDA repository file: $repo_file."; return 1;
         fi
    else
        log_msg "INFO" "Nvidia CUDA repository file already exists: $repo_file"
        # Optional: Check content? Add if repo_line is missing?
        if ! grep -qxF "$repo_line" "$repo_file"; then
            print_color "$YELLOW" "Repo file exists but content might differ. Ensuring line is present..."
            # Check if line exists commented out, if so, uncomment? Or just append? Append is safest.
            if ! grep -qF "$repo_line" "$repo_file"; then
                 if run_command "echo \"$repo_line\" | tee -a \"$repo_file\" > /dev/null" false "Append Repo Line"; then
                     log_msg "INFO" "Appended Nvidia repo line to $repo_file"; repo_changed=true;
                 else
                      log_msg "ERROR" "Failed to append repo line to $repo_file"; return 1;
                 fi
            fi
        fi
    fi

    # Only run apt update if repo was added/changed or if installing
    if [[ "$repo_changed" == true || "$setup_only" == false ]]; then
        print_color "$CYAN" "Updating APT cache after repo configuration...";
        run_command "apt-get update" false "Update after repo setup" || print_color "$YELLOW" "Warn: apt update failed."
    fi

    if [[ "$setup_only" == true ]]; then
        print_color "$GREEN" "Nvidia repository setup complete."; return 0;
    fi

    # Proceed with driver install if not setup_only
    print_color "$CYAN" "Installing 'cuda-drivers' meta-package from Nvidia repo..."; log_msg "EXEC" "apt-get install cuda-drivers -y"
    if run_command "apt-get install cuda-drivers -y" true "Install cuda-drivers"; then
        log_msg "INFO" "APT cuda-drivers install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        if echo "$dkms_out" | grep -q "nvidia/"; then print_color "$GREEN" "DKMS module seems built."; log_msg "INFO" "DKMS check PASSED (found nvidia module)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found after cuda-drivers install!"; log_msg "ERROR" "DKMS check FAILED (no nvidia module found)."; return 1; fi
    else
        log_msg "ERROR" "apt-get install cuda-drivers failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1;
    fi
}
# FINISH ### NVIDIA INSTALL APT NVIDIA REPO ###

# START ### NVIDIA INSTALL RUNFILE ###
install_nvidia_runfile() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install via Runfile ---"; log_msg "INFO" "Starting Runfile Install Module.";

    # Check for wget
    if ! command -v wget &> /dev/null; then
        print_color "$YELLOW" "wget command not found, needed for downloads.";
        if prompt_confirm "Attempt to install wget (apt install wget)?"; then
            if ! run_command "apt-get update && apt-get install -y wget" true "Install wget"; then
                log_msg "ERROR" "Failed to install wget. Download unavailable."; return 1;
            fi
        else
            log_msg "WARN" "wget not installed. Download option disabled.";
            print_color "$RED" "Exiting runfile install as download might be required."; return 1;
        fi
    fi

    # --- Define known runfiles and URLs ---
    local runfile_535_name="NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_535_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/535.154.05/NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_570_name="NVIDIA-Linux-x86_64-570.133.07.run"
    local runfile_570_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/570.133.07/NVIDIA-Linux-x86_64-570.133.07.run"

    local runfile_path=""; local chosen_rn="";

    while [[ -z "$runfile_path" ]]; do
        print_color "$YELLOW" "\nSelect Runfile source:";
        echo " 1) Use $runfile_535_name (Check $USER_HOME, download if missing)";
        echo " 2) Use $runfile_570_name (Check $USER_HOME, download if missing)";
        echo " 3) Search $USER_HOME for other NVIDIA-*.run files";
        echo " 4) Cancel";
        read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;

        case "$choice" in
            1) # Specific 535
               chosen_rn="$runfile_535_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       # Use run_command to log wget output
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_535_url\"" true "Download $chosen_rn"; then
                            # Set ownership to user after download
                            run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                            print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                            log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                    print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 1
            2) # Specific 570
               chosen_rn="$runfile_570_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_570_url\"" true "Download $chosen_rn"; then
                           run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                           print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                           log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                   print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 2
            3) # Manual Search
               local runfile_opts=(); declare -A runfile_map; local count=1;
               print_color "$CYAN" "\nSearching driver .run files in $USER_HOME..."; log_msg "INFO" "Searching runfiles in $USER_HOME."
               # Use find directly, handle potential errors
               local find_output; find_output=$(find "$USER_HOME" -maxdepth 1 -name 'NVIDIA-Linux-x86_64-*.run' -print0 2>/dev/null)
               if [[ -z "$find_output" ]]; then
                    print_color "$RED" "No driver .run files found in $USER_HOME search."; log_msg "WARN" "No other driver runfiles found in search.";
                    runfile_path=""; # Stay in loop
               else
                   while IFS= read -r -d $'\0' f; do
                       local bn; bn=$(basename "$f");
                       # Exclude CUDA runfiles from this list
                       if [[ "$bn" != "cuda_"* ]]; then
                           runfile_opts+=("$bn"); runfile_map[$count]="$bn"; ((count++));
                       fi;
                   done <<< "$find_output" # Process the find output

                   if [[ ${#runfile_opts[@]} -eq 0 ]]; then
                        print_color "$RED" "No non-CUDA driver .run files found in $USER_HOME search."; log_msg "WARN" "No non-CUDA driver runfiles found in search.";
                        runfile_path=""; # Stay in loop
                   else
                       print_color "$YELLOW" "Select driver runfile:";
                       for i in "${!runfile_map[@]}"; do echo " $i) ${runfile_map[$i]}" >&2; done;
                       local search_choice;
                       while [[ -z "$runfile_path" ]]; do
                           read -r -p "$(print_color "$YELLOW" "Choice: ")" search_choice < /dev/tty;
                           if [[ "$search_choice" =~ ^[0-9]+$ && -v "runfile_map[$search_choice]" ]]; then
                               chosen_rn="${runfile_map[$search_choice]}";
                               runfile_path="$USER_HOME/$chosen_rn";
                               log_msg "USER" "Selected Runfile from search: $runfile_path";
                           else
                               print_color "$RED" "Invalid selection from search.";
                           fi;
                       done;
                   fi
               fi
               ;; # End case 3
            4) # Cancel
               log_msg "USER" "Cancelled Runfile install."; return 1;;
            *) # Invalid
               print_color "$RED" "Invalid choice.";;
        esac
    done # End while loop for selecting runfile

    # --- Proceed with installation using selected runfile_path ---
    if [[ -z "$runfile_path" || ! -f "$runfile_path" ]]; then
         print_color "$RED" "ERROR: Invalid or missing runfile selected. Exiting.";
         log_msg "ERROR" "Runfile path invalid or file missing before install: $runfile_path";
         return 1;
    fi

    print_color "$CYAN" "\nStarting Runfile install using: $chosen_rn";
    chmod +x "$runfile_path" || { log_msg "ERROR" "chmod failed on $runfile_path"; return 1; }

    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

    print_color "$YELLOW" "Ensure Build Env (Menu 9 -> 2) & Nouveau blacklist (Menu 5) are done.";
    print_color "$YELLOW" "Also ensure correct GCC is default (Menu 9 -> 3).";
    print_color "$CYAN" "Running installer '$chosen_rn' with --dkms flag (INTERACTIVE)..."
    log_msg "EXEC" "$runfile_path --dkms"

    # Run interactively - run_command cannot handle interactive installers easily
    print_color "$PURPLE" "--- Starting Interactive Installer ---";
    # Ensure installer runs with correct permissions and reads from TTY
    if "$runfile_path" --dkms < /dev/tty ; then
        local run_status=$?; # Capture status immediately
        print_color "$PURPLE" "--- Interactive Installer Finished (Status: $run_status) ---";
        log_msg "INFO" "Runfile '$chosen_rn' finished status: $run_status.";

        if [[ $run_status -eq 0 ]]; then
            print_color "$CYAN" "Verifying DKMS status after successful install..."; log_msg "INFO" "Verifying DKMS after runfile install..."; sleep 2;
            local ver; ver=$(echo "$chosen_rn" | grep -oP '[0-9]+(\.[0-9]+){1,2}' | head -n1);
            local dkms_out; dkms_out=$(dkms status);
            log_msg "INFO" "DKMS Status after install: $dkms_out";
            local major_ver; major_ver=$(echo "$ver" | cut -d. -f1);
            if echo "$dkms_out" | grep -q "nvidia/${major_ver}"; then
                print_color "$GREEN" "DKMS module seems built for version ${major_ver}.x."; log_msg "INFO" "DKMS check PASSED (found nvidia/${major_ver}).";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else
                print_color "$RED" "ERROR: DKMS module for version $ver (or ${major_ver}.x) NOT found after supposedly successful install!";
                log_msg "ERROR" "DKMS check FAILED after runfile install (looking for $ver or ${major_ver}.x).";
                print_color "$YELLOW" "Check 'dkms status' and /var/log/nvidia-installer.log.";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 1; # Return failure even if installer reported 0, because DKMS check failed
            fi
        else
             print_color "$RED" "ERROR: Runfile installer '$chosen_rn' reported failure! Status: $run_status";
             print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
             if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
             return $run_status;
        fi
    else
        local run_status=$?; # Capture status
        print_color "$PURPLE" "--- Interactive Installer Failed to Execute Properly (Status: $run_status) ---";
        log_msg "ERROR" "Runfile installer '$chosen_rn' execution failed. Status: $run_status."; print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
        if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
        return $run_status;
    fi
}
# FINISH ### NVIDIA INSTALL RUNFILE ###

# START ### HELPER INSTALL CUDA TOOLKIT APT CORE ###
# This function assumes Nvidia repo might already be configured.
# It only installs the toolkit package.
install_cuda_toolkit_apt_core() {
    local toolkit_pkg="cuda-toolkit" # Default, could be version specific like cuda-toolkit-12-2 if needed
    print_color "$CYAN" "\nInstalling CUDA Toolkit via APT ($toolkit_pkg)..."; log_msg "INFO" "Starting core CUDA APT install."

    # Ensure repo is configured before proceeding
    # Check if nvidia.com provides the package
    if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
         print_color "$YELLOW" "Nvidia repo doesn't seem to provide '$toolkit_pkg' or isn't configured/updated."
         if prompt_confirm "Attempt to configure Nvidia repo and update APT cache first?"; then
             # Run setup only, capture status
             local repo_setup_status=1
             install_nvidia_apt_official_repo "true"; repo_setup_status=$?
             if [[ $repo_setup_status -ne 0 ]]; then
                 print_color "$RED" "Nvidia repo setup failed. Cannot proceed reliably."; return 1;
             fi
             run_command "apt-get update" false "Update before CUDA core install" || { print_color "$RED" "APT update failed."; return 1; }
             # Re-check policy after update
             if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
                  print_color "$YELLOW" "Warning: Nvidia repo still doesn't seem to provide '$toolkit_pkg' after setup/update.";
                  log_msg "WARN" "Nvidia repo doesn't provide $toolkit_pkg after setup attempt."
                  if ! prompt_confirm "Continue anyway (may install older Ubuntu version)?"; then return 1; fi
             fi
         else
             print_color "$YELLOW" "Proceeding without confirmed Nvidia repo. May install older version from Ubuntu repos.";
             log_msg "WARN" "Proceeding with CUDA toolkit install without confirmed Nvidia repo."
         fi
    else
         log_msg "INFO" "Confirmed $toolkit_pkg available from Nvidia repo."
    fi

    print_color "$CYAN" "Running: apt-get install $toolkit_pkg -y";
    if run_command "apt-get install $toolkit_pkg -y" true "Install CUDA Toolkit APT Core"; then
        log_msg "INFO" "CUDA APT install ($toolkit_pkg) finished."; print_color "$GREEN" "CUDA APT install finished."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
        local nvcc_path; nvcc_path=$(command -v nvcc || echo "/usr/local/cuda/bin/nvcc");
        if [[ -x "$nvcc_path" ]]; then
             local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
        else
             print_color "$YELLOW" "nvcc not found in PATH or default location. Update PATH/LD_LIBRARY_PATH."; log_msg "WARN" "nvcc check FAILED.";
        fi;
        print_color "$YELLOW" "Ensure PATH includes /usr/local/cuda/bin and LD_LIBRARY_PATH includes /usr/local/cuda/lib64 if needed.";
        return 0;
    else
        log_msg "ERROR" "apt-get install $toolkit_pkg failed."; return 1;
    fi
}
# FINISH ### HELPER INSTALL CUDA TOOLKIT APT CORE ###


# START ### MODULE CUDA INSTALL ###
run_cuda_install() {
    print_color "$PURPLE" "\n--- Module: CUDA Toolkit Install ---"; log_msg "INFO" "Starting CUDA Install.";
    # Simplified pre-check
    if ! nvidia-smi &> /dev/null; then
        log_msg "WARN" "nvidia-smi command failed. Is driver installed and running?";
        print_color "$RED" "WARN: nvidia-smi failed. Driver may be inactive.";
        if ! prompt_confirm "Continue CUDA install anyway (NOT Recommended)?"; then return 1; fi;
    else
        print_color "$GREEN" "nvidia-smi check passed."; log_msg "INFO" "nvidia-smi check passed.";
    fi
    local method="";
    local specific_cuda_runfile_name="cuda_12.2.2_535.104.05_linux.run"

    while true; do
        print_color "$YELLOW" "\nSelect CUDA install method:"
        echo "  1) APT ('cuda-toolkit' - Best if Nvidia Repo is configured)";
        echo "  2) Runfile (Check for '$specific_cuda_runfile_name' or search $USER_HOME)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt"; break;;
            2) method="runfile"; break;;
            *) print_color "$RED" "Invalid.";;
        esac
    done;
    log_msg "USER" "Selected CUDA method: $method"

    if [[ "$method" == "apt" ]]; then
        # Call the simplified core install function
        install_cuda_toolkit_apt_core; return $?;

    elif [[ "$method" == "runfile" ]]; then
        # (Keep existing runfile logic from v1.10 - it's already complex and functional)
        local chosen_cuda_runfile_path=""; local chosen_cuda_rn="";
        while [[ -z "$chosen_cuda_runfile_path" ]]; do
            print_color "$YELLOW" "\nSelect CUDA Runfile source:";
            echo " 1) Use $specific_cuda_runfile_name (Check $USER_HOME)";
            echo " 2) Search $USER_HOME for other cuda_*.run files";
            echo " 3) Cancel";
            read -r -p "$(print_color "$YELLOW" "Choice [1-3]: ")" cuda_choice < /dev/tty;
            case "$cuda_choice" in
                1) chosen_cuda_rn="$specific_cuda_runfile_name";
                   if [[ -f "$USER_HOME/$chosen_cuda_rn" ]]; then
                       chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; print_color "$GREEN" "Found locally: $chosen_cuda_runfile_path"; log_msg "INFO" "Found specific CUDA runfile: $chosen_cuda_runfile_path";
                   else print_color "$RED" "Specific file not found: $USER_HOME/$chosen_cuda_rn"; log_msg "WARN" "Specific CUDA runfile missing."; print_color "$YELLOW" "Please download manually or choose search."; fi ;; # Stay in loop
                2) local cuda_runfile_opts=(); declare -A cuda_runfile_map; local ccount=1;
                   print_color "$CYAN" "\nSearching CUDA .run files in $USER_HOME..."; log_msg "INFO" "Searching CUDA runfiles in $USER_HOME."
                   local cuda_find_output; cuda_find_output=$(find "$USER_HOME" -maxdepth 1 -name 'cuda_*_linux.run' -print0 2>/dev/null)
                   if [[ -z "$cuda_find_output" ]]; then print_color "$RED" "No CUDA .run files found in search."; log_msg "WARN" "No CUDA runfiles found in search.";
                   else
                        while IFS= read -r -d $'\0' f; do local bn; bn=$(basename "$f"); cuda_runfile_opts+=("$bn"); cuda_runfile_map[$ccount]="$bn"; ((ccount++)); done <<< "$cuda_find_output"
                       if [[ ${#cuda_runfile_opts[@]} -eq 0 ]]; then print_color "$RED" "Error processing found CUDA files."; log_msg "ERROR" "Processing find results for CUDA failed.";
                       else
                           print_color "$YELLOW" "Select CUDA runfile:";
                           for i in "${!cuda_runfile_map[@]}"; do echo " $i) ${cuda_runfile_map[$i]}" >&2; done;
                           local csearch_choice;
                           while [[ -z "$chosen_cuda_runfile_path" ]]; do
                               read -r -p "$(print_color "$YELLOW" "Choice: ")" csearch_choice < /dev/tty;
                               if [[ "$csearch_choice" =~ ^[0-9]+$ && -v "cuda_runfile_map[$csearch_choice]" ]]; then
                                   chosen_cuda_rn="${cuda_runfile_map[$csearch_choice]}"; chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; log_msg "USER" "Selected CUDA Runfile from search: $chosen_cuda_runfile_path";
                               else print_color "$RED" "Invalid selection."; fi;
                           done;
                        fi
                   fi ;; # End search logic
                3) log_msg "USER" "Cancelled CUDA Runfile install."; return 1;; *) print_color "$RED" "Invalid choice.";;
            esac
        done # End CUDA runfile selection loop

        # --- Proceed with CUDA Runfile Install ---
        if [[ -z "$chosen_cuda_runfile_path" || ! -f "$chosen_cuda_runfile_path" ]]; then print_color "$RED" "ERROR: Invalid CUDA runfile. Exiting."; log_msg "ERROR" "CUDA Runfile path invalid."; return 1; fi

        print_color "$CYAN" "\nInstalling CUDA via Runfile ($chosen_cuda_rn)..."; log_msg "INFO" "Starting CUDA Runfile install: $chosen_cuda_runfile_path"
        chmod +x "$chosen_cuda_runfile_path" || { log_msg "ERROR" "chmod CUDA runfile failed"; return 1; }
        if ! check_tty; then return 1; fi; local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for CUDA runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

        print_color "$YELLOW" "Runfile Install Options (IMPORTANT!)";
        print_color "$YELLOW" " -> Answer 'accept' to EULA.";
        print_color "$RED"    " -> DESELECT the 'Driver' component if you already installed drivers separately.";
        print_color "$YELLOW" " -> Keep 'CUDA Toolkit' selected.";
        log_msg "INFO" "Instructed user on runfile options (deselect driver).";

        print_color "$CYAN" "Running CUDA Runfile '$chosen_cuda_rn' INTERACTIVELY..."; log_msg "EXEC" "$chosen_cuda_runfile_path";
        print_color "$PURPLE" "--- Starting Interactive CUDA Installer ---";
        if "$chosen_cuda_runfile_path" < /dev/tty ; then
            local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Finished (Status: $cuda_run_status) ---"; log_msg "INFO" "CUDA Runfile finished status $cuda_run_status.";
            if [[ $cuda_run_status -eq 0 ]]; then
                print_color "$GREEN" "CUDA Runfile finished successfully."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
                local cuda_base_path="/usr/local"; local latest_cuda_link="$cuda_base_path/cuda"; local nvcc_path="";
                if [[ -L "$latest_cuda_link" ]] && [[ -x "$latest_cuda_link/bin/nvcc" ]]; then nvcc_path="$latest_cuda_link/bin/nvcc";
                else local newest_cuda_dir; newest_cuda_dir=$(find "$cuda_base_path" -maxdepth 1 -name 'cuda-*' -type d -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-); if [[ -n "$newest_cuda_dir" ]] && [[ -x "$newest_cuda_dir/bin/nvcc" ]]; then nvcc_path="$newest_cuda_dir/bin/nvcc"; else nvcc_path="/usr/local/cuda/bin/nvcc"; fi; fi
                if [[ -x "$nvcc_path" ]]; then local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
                else print_color "$YELLOW" "nvcc not found. Update PATH/LD_LIB."; log_msg "WARN" "nvcc FAILED check."; fi;
                print_color "$YELLOW" "Ensure PATH/LD_LIBRARY_PATH are set if needed.";
                 if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else log_msg "ERROR" "CUDA Runfile failed status $cuda_run_status."; print_color "$RED" "CUDA Runfile Failed!"; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return 1; fi
        else local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Failed Execution (Status: $cuda_run_status) ---"; log_msg "ERROR" "CUDA Runfile execution failed. Status: $cuda_run_status."; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return $cuda_run_status; fi
    fi # End method if/elif
}
# FINISH ### MODULE CUDA INSTALL ###

# START ### GRUB CUSTOM BUILDER FUNCTION ###
run_grub_custom_builder() {
    local grub_def="/etc/default/grub"; local current_cmdline=""
    print_color "$PURPLE" "\n--- GRUB Custom Parameter Builder (Experimental) ---"; log_msg "INFO" "Starting GRUB Custom Builder."

    # Read current setting
    if [[ -f "$grub_def" ]]; then
        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_def" | cut -d'=' -f2 | sed 's/"//g')
        print_color "$CYAN" "Current GRUB_CMDLINE_LINUX_DEFAULT: \"$current_cmdline\""
        log_msg "INFO" "Current GRUB CMDLINE: $current_cmdline"
    else
        print_color "$RED" "Cannot read $grub_def!"; log_msg "ERROR" "Cannot read $grub_def in custom builder."; return 1;
    fi

    # Initialize parameters based on current settings or defaults
    local params; params=($current_cmdline) # Convert string to array
    local use_quiet="N"; [[ " ${params[@]} " =~ " quiet " ]] && use_quiet="Y"
    local use_splash="N"; [[ " ${params[@]} " =~ " splash " ]] && use_splash="Y"
    local use_nomodeset="N"; [[ " ${params[@]} " =~ " nomodeset " ]] && use_nomodeset="Y"
    local use_nvidiadrm="N"; [[ " ${params[@]} " =~ " nvidia-drm.modeset=1 " ]] && use_nvidiadrm="Y"
    local custom_params=""

    # Filter out the params we will toggle, keep others
    local other_params=()
    for p in "${params[@]}"; do
        if [[ "$p" != "quiet" && "$p" != "splash" && "$p" != "nomodeset" && "$p" != "nvidia-drm.modeset=1" ]]; then
            other_params+=("$p")
        fi
    done
    custom_params=$(echo "${other_params[@]}") # Join remaining params back into a string

    print_color "$YELLOW" "\nConfigure parameters (Current state shown):"
    prompt_confirm "Include 'quiet' parameter?" "$use_quiet"; [[ $? -eq 0 ]] && use_quiet="Y" || use_quiet="N"
    prompt_confirm "Include 'splash' parameter?" "$use_splash"; [[ $? -eq 0 ]] && use_splash="Y" || use_splash="N"
    prompt_confirm "Include 'nomodeset' parameter? (Disables most KMS drivers)" "$use_nomodeset"; [[ $? -eq 0 ]] && use_nomodeset="Y" || use_nomodeset="N"
    prompt_confirm "Include 'nvidia-drm.modeset=1' parameter? (Recommended for Nvidia)" "$use_nvidiadrm"; [[ $? -eq 0 ]] && use_nvidiadrm="Y" || use_nvidiadrm="N"

    print_color "$YELLOW" "\nCurrent other/custom parameters: $custom_params"
    read -r -p "$(print_color "$YELLOW" "Enter any ADDITIONAL custom parameters (space-separated, or leave blank): ")" additional_params < /dev/tty
    custom_params="$custom_params $additional_params"
    # Clean up potential double spaces and leading/trailing whitespace
    custom_params=$(echo "$custom_params" | tr -s ' ' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Build the new command line
    local new_cmdline_array=()
    [[ "$use_quiet" == "Y" ]] && new_cmdline_array+=("quiet")
    [[ "$use_splash" == "Y" ]] && new_cmdline_array+=("splash")
    [[ "$use_nomodeset" == "Y" ]] && new_cmdline_array+=("nomodeset")
    [[ "$use_nvidiadrm" == "Y" ]] && new_cmdline_array+=("nvidia-drm.modeset=1")
    # Add custom params if not empty
    [[ -n "$custom_params" ]] && new_cmdline_array+=($custom_params) # Add as separate elements

    local new_cmdline; new_cmdline=$(echo "${new_cmdline_array[@]}") # Join with spaces

    print_color "$PURPLE" "\n--- Generated Config Line ---"
    print_color "$CYAN" "GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\""
    log_msg "INFO" "Custom GRUB CMDLINE generated: $new_cmdline"
    print_color "$PURPLE" "---------------------------"

    if ! prompt_confirm "Apply this custom config line to $grub_def?"; then
        log_msg "USER" "Cancelled custom GRUB apply."; return 1
    fi

    # Apply the changes
    local grub_bak="/etc/default/grub.custom_backup.$(date +%s)"
    print_color "$YELLOW" "Backing up current config to $grub_bak..."
    if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Custom"; then
        log_msg "ERROR" "Custom GRUB backup failed."; return 1
    fi

    print_color "$CYAN" "Applying custom config line using sed...";
    local escaped_cmdline; escaped_cmdline=$(sed 's/[&/\]/\\&/g' <<< "$new_cmdline") # Basic escaping for sed
    if run_command "sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$escaped_cmdline\"|' \"$grub_def\"" false "Apply Custom Grub Line"; then
        log_msg "INFO" "Applied custom GRUB config line ok.";
        print_color "$CYAN" "Running update-grub...";
        if run_command "update-grub" true "update-grub after custom config"; then
            print_color "$GREEN" "Custom GRUB config applied and updated."; log_msg "INFO" "Custom GRUB updated ok."; return 0;
        else
            log_msg "ERROR" "update-grub failed after custom config."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1;
        fi
    else
        log_msg "ERROR" "Failed to apply custom config line using sed."; return 1
    fi
}
# FINISH ### GRUB CUSTOM BUILDER FUNCTION ###

# START ### GRUB FIX FUNCTION ###
run_grub_fix() {
    print_color "$PURPLE" "\n--- Module: GRUB Configuration Fix ---"; log_msg "INFO" "Starting GRUB Fix."
    local grub_def="/etc/default/grub"; local grub_bak="/etc/default/grub.preset_backup.$(date +%s)"; local cfg=""; local cfg_name="";
    print_color "$YELLOW" "Select GRUB action:";
    echo " 1) Apply Standard Default (quiet splash)";
    echo " 2) Apply Verbose Boot (no quiet splash)";
    echo " 3) Apply Failsafe (nomodeset)";
    echo " 4) Apply Std + Nvidia DRM Modeset (quiet splash nvidia-drm.modeset=1)";
    echo " 5) Apply Verbose + Nvidia DRM Modeset (nvidia-drm.modeset=1)";
    echo " 6) Custom Parameter Builder (Experimental)";
    echo " 7) Reinstall GRUB (EFI)";
    echo " 8) Cancel";
    read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty;
    case "$choice" in
        1) cfg_name="Standard"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Standard
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
# Add other GRUB settings below if needed, ensuring they don't conflict
GRUBEOF
) ;; # END Standard Preset
        2) cfg_name="Verbose"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose Preset
        3) cfg_name="Failsafe (nomodeset)"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Failsafe
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Failsafe Preset
        4) cfg_name="Std + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Std+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUBEOF
) ;; # END Std+DRM Preset
        5) cfg_name="Verbose + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose+DRM Preset
        6) run_grub_custom_builder; return $? ;; # Call Custom Builder
        7) print_color "$CYAN" "Selected: Reinstall GRUB (EFI)."; log_msg "USER" "Selected GRUB Reinstall."
           if ! mount | grep -q /boot/efi; then
                print_color "$YELLOW" "Warning: /boot/efi does not seem to be mounted."
                if ! prompt_confirm "Attempt to mount EFI partition and continue? (Requires knowing EFI partition)"; then return 1; fi
                 efi_part=$(findmnt -n -o SOURCE --target /boot/efi || lsblk -o NAME,PARTLABEL | grep -i EFI | awk '{print "/dev/"$1}' | head -n1)
                 if [[ -z "$efi_part" ]]; then print_color "$RED" "Could not determine EFI partition automatically."; return 1; fi
                 if ! run_command "mount $efi_part /boot/efi" true "Mount EFI"; then print_color "$RED" "Failed to mount EFI partition."; return 1; fi
           fi
           if prompt_confirm "Run 'grub-install --recheck' (Assumes /boot/efi is correctly mounted)?"; then
               if run_command "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck" true "grub-install"; then
                   log_msg "INFO" "grub-install ok."; print_color "$CYAN" "Running update-grub...";
                   if run_command "update-grub" true "update-grub"; then log_msg "INFO" "update-grub ok."; return 0; else log_msg "ERROR" "update-grub failed."; return 1; fi
               else log_msg "ERROR" "grub-install failed."; return 1; fi
           else log_msg "USER" "Cancelled GRUB reinstall."; return 1; fi ;; # END GRUB Reinstall
        8) print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled GRUB fix."; return 1 ;; # END Cancel
        *) print_color "$RED" "Invalid."; return 1 ;;
    esac
    # Logic to apply the selected preset (if cfg is set)
    if [[ -n "$cfg" ]]; then
        print_color "$CYAN" "\nSelected Config Preset: $cfg_name"; print_color "$PURPLE" "--- Config ---"; print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$cfg"; print_color "$PURPLE" "--------------"; log_msg "INFO" "Applying GRUB preset: $cfg_name"
        if prompt_confirm "Apply this preset to $grub_def (OVERWRITES ENTIRE FILE)?"; then
            print_color "$YELLOW" "Backing up $grub_def to $grub_bak..."; if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Preset"; then log_msg "ERROR" "Backup failed."; return 1; fi
            print_color "$CYAN" "Writing preset config...";
            # Overwrite the file with the heredoc content
            if echo "$cfg" | sudo tee "$grub_def" > /dev/null; then # Ensure using sudo for tee
                 sudo chown root:root "$grub_def" && sudo chmod 644 "$grub_def"
                log_msg "INFO" "Wrote preset config ok."; print_color "$CYAN" "Running update-grub...";
                if run_command "update-grub" true "update-grub after preset"; then print_color "$GREEN" "GRUB updated successfully."; log_msg "INFO" "GRUB updated ok."; return 0;
                else log_msg "ERROR" "update-grub failed."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1; fi
            else log_msg "ERROR" "Write preset config failed."; return 1; fi
        else log_msg "USER" "Cancelled GRUB preset apply."; return 1; fi
    fi;
    return 0; # Should only be reached if choice was handled (e.g. custom builder)
}
# FINISH ### GRUB FIX FUNCTION ###

# START ### MODULE KERNEL FIX ###
run_kernel_fix() {
    print_color "$PURPLE" "\n--- Module: Kernel Reset ---"; log_msg "INFO" "Starting Kernel Reset."
    print_color "$YELLOW" "Removes & reinstalls a specific kernel version. USE CAUTION.";
    print_color "$YELLOW" "Ensure you are booted into a DIFFERENT, WORKING kernel.";
    local current_k; current_k=$(uname -r); log_msg "INFO" "Current kernel: $current_k"; print_color "$CYAN" "Currently running kernel: $current_k"

    print_color "$CYAN" "\nIdentifying installed kernel images..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
    # Get kernel versions from image packages
     while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1; fi

    print_color "$YELLOW" "\nSelect kernel version to reset:"
    for i in "${!kernel_map[@]}"; do
        local status_flag=""
        [[ "${kernel_map[$i]}" == "$current_k" ]] && status_flag=" (Currently Running - Cannot Reset)"
        echo " $i) ${kernel_map[$i]}$status_flag" >&2
    done
    echo " $((count))) Cancel" >&2

    local choice; local kernel_to_fix=""
    while [[ -z "$kernel_to_fix" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                if [[ "${kernel_map[$choice]}" == "$current_k" ]]; then
                     print_color "$RED" "Cannot reset the currently running kernel ($current_k)."; log_msg "WARN" "Attempted to reset running kernel.";
                else
                     kernel_to_fix="${kernel_map[$choice]}"
                fi
            elif [[ "$choice" -eq "$count" ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled kernel reset selection."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected kernel to reset: $kernel_to_fix"
    print_color "$RED" "\nWARNING: This will PURGE packages for kernel $kernel_to_fix"
    print_color "$RED" "         (image, headers, modules, modules-extra)"
    print_color "$RED" "         and then attempt to REINSTALL them."
    if ! prompt_confirm "Are you absolutely sure? You are booted from $current_k."; then log_msg "USER" "Cancelled kernel reset confirmation."; return 1; fi

    print_color "$CYAN" "\nStep 1: Purging packages for kernel $kernel_to_fix...";
    local purge_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix} linux-modules-${kernel_to_fix} linux-modules-extra-${kernel_to_fix}"
    if run_command "apt-get purge --autoremove -y $purge_pkgs" true "Purge Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix purged ok."; else log_msg "ERROR" "Kernel purge failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi

    print_color "$CYAN" "\nStep 2: Updating GRUB after purge..."; run_command "update-grub" true "Update GRUB after purge" || log_msg "ERROR" "update-grub failed after purge."

    print_color "$CYAN" "\nStep 3: Reinstalling kernel $kernel_to_fix packages...";
    local install_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix}"
    # Determine if HWE meta-package should be reinstalled (simple check)
    local install_cmd="apt-get update && apt-get install -y $install_pkgs"
    if [[ "$kernel_to_fix" == *-hwe-* ]]; then
        local os_release; os_release=$(lsb_release -sr) # Get release number e.g., 22.04
        if [[ -n "$os_release" ]]; then
            local hwe_pkg="linux-generic-hwe-${os_release}"
            print_color "$CYAN" "Attempting to reinstall HWE meta-package ($hwe_pkg) as well..."
            install_cmd+=" && apt-get install -y $hwe_pkg"
        else
             print_color "$YELLOW" "Could not determine OS release for HWE package."
        fi
    fi
    if run_command "$install_cmd" true "Reinstall Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix reinstall ok."; else log_msg "ERROR" "Kernel reinstall failed."; return 1; fi

    print_color "$GREEN" "\n--- Kernel Reset Complete for $kernel_to_fix ---";
    print_color "$YELLOW" "Reboot required to boot into the reinstalled kernel."; log_msg "INFO" "Kernel Reset finished."; return 0
}
# FINISH ### MODULE KERNEL FIX ###

# START ### MODULE CHROOT HELPER ###
run_chroot_helper() {
    print_color "$PURPLE" "\n--- Module: Chroot Helper (For booting from Live USB/ISO) ---"; log_msg "INFO" "Starting Chroot Helper.";
    print_color "$YELLOW" "This helps mount your installed system and chroot into it.";
    print_color "$YELLOW" "USE THIS ONLY WHEN BOOTED FROM A LIVE ENVIRONMENT.";

    # Basic check for live environment
    if mountpoint -q /cdrom || grep -q -E 'casper|toram|live' /proc/cmdline; then log_msg "INFO" "Live environment detected."; else print_color "$RED" "Warning: Doesn't look like a standard Live environment."; log_msg "WARN" "Not Live OS?"; if ! prompt_confirm "Are you sure you are booted from a Live USB/ISO?"; then return 1; fi; fi

    local root_part=""; local efi_part=""; local swap_part=""; local mount_p="/mnt/mybitch_chroot"; local binds=( "/dev" "/dev/pts" "/proc" "/sys" "/run" )
    print_color "$CYAN" "\nIdentifying partitions (lsblk)..."; lsblk -f >&2;
    print_color "$YELLOW" "\nEnter the device paths for your installed system:"
    while true; do read -r -p "$(print_color "$YELLOW" " -> ROOT partition (e.g., /dev/nvme0n1p2 or /dev/sda3): ")" root_part < /dev/tty; if [[ -b "$root_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    while true; do read -r -p "$(print_color "$YELLOW" " -> EFI partition (e.g., /dev/nvme0n1p1 or /dev/sda1): ")" efi_part < /dev/tty; if [[ -b "$efi_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    read -r -p "$(print_color "$YELLOW" " -> SWAP partition (optional, e.g., /dev/sda2 or blank): ")" swap_part < /dev/tty; if [[ -n "$swap_part" && ! -b "$swap_part" ]]; then print_color "$RED" "Invalid block device for swap, ignoring."; swap_part=""; fi

    log_msg "USER" "Chroot Target - Root: $root_part, EFI: $efi_part, Swap: ${swap_part:-none}."

    print_color "$CYAN" "\nUnmounting previous attempts at $mount_p..."; umount -R "$mount_p" &>/dev/null; sleep 1; rm -rf "$mount_p"; # Clean up dir too
    print_color "$CYAN" "Mounting target system..."
    mkdir -p "$mount_p" || { log_msg "ERROR" "mkdir $mount_p fail"; return 1; }
    mount "$root_part" "$mount_p" || { log_msg "ERROR" "mount root $root_part fail"; rm -rf "$mount_p"; return 1; };
    mkdir -p "$mount_p/boot/efi" || { log_msg "ERROR" "mkdir $mount_p/boot/efi fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    mount "$efi_part" "$mount_p/boot/efi" || { log_msg "ERROR" "mount efi $efi_part fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    if [[ -n "$swap_part" ]]; then
         print_color "$CYAN" "Activating swap partition $swap_part...";
         run_command "swapon $swap_part" false "Activate Swap" || print_color "$YELLOW" "Warning: Failed to activate swap.";
    fi

    print_color "$CYAN" "Binding system directories for chroot..."; local bind_f=0;
    for p in "${binds[@]}"; do
        # Ensure target directory exists within the mount point
        mkdir -p "$mount_p$p";
        if ! mount --bind "$p" "$mount_p$p"; then log_msg "ERROR" "Bind $p fail"; bind_f=1; print_color "$RED" " ERROR: Bind $p fail!"; fi;
    done;

    if [[ $bind_f -eq 1 ]]; then print_color "$YELLOW" "One or more binds failed. Chroot environment may be incomplete."; else print_color "$GREEN" "System binds successful."; fi

    print_color "$CYAN" "Copying DNS info (/etc/resolv.conf)...";
    # Handle cases where resolv.conf might be a broken symlink in the chroot target
    if [[ -L "$mount_p/etc/resolv.conf" ]]; then
        run_command "rm \"$mount_p/etc/resolv.conf\"" false "Remove resolv.conf symlink"
    fi
    if cp --dereference /etc/resolv.conf "$mount_p/etc/resolv.conf"; then print_color "$GREEN" "DNS info copied."; else log_msg "WARN" "DNS copy failed."; print_color "$YELLOW" "Warning: Failed to copy DNS info."; fi

    print_color "$GREEN" "\nTarget system mounted successfully at $mount_p.";
    print_color "$YELLOW" "Entering chroot environment. Type 'exit' or press Ctrl+D when finished.";
    print_color "$CYAN" "Inside chroot, you can run commands like 'apt update', 'update-grub', etc.";
    read -r -p "$(print_color "$YELLOW" "Press Enter to enter chroot...")" < /dev/tty

    log_msg "EXEC" "chroot $mount_p /bin/bash";
    # Use a more complete chroot environment setup
    chroot "$mount_p" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(chroot) \u@\h:\w\$ ' PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash --login +h
    local chroot_st=$?; log_msg "INFO" "Exited chroot status $chroot_st."

    print_color "$PURPLE" "\n--- Exited Chroot Environment ---";
    print_color "$YELLOW" "IMPORTANT: Filesystem is still mounted!";
    print_color "$YELLOW" "Unmount manually when finished using commands like:";
    print_color "$CYAN" "   sudo umount -R \"$mount_p\"";
    print_color "$YELLOW" "(If recursive unmount fails, unmount binds individually then base mounts)";
    print_color "$CYAN" "   (e.g., sudo umount \"$mount_p/dev/pts\" \"$mount_p/dev\" ...etc... )"
    print_color "$CYAN" "   (then sudo umount \"$mount_p/boot/efi\" \"$mount_p\" )"
    if [[ -n "$swap_part" ]]; then print_color "$CYAN" "   sudo swapoff $swap_part"; fi
    return 0
}
# FINISH ### MODULE CHROOT HELPER ###

# START ### MODULE VIEW LOGS ###
run_view_logs() {
    print_color "$PURPLE" "\n--- Module: Log Viewer ---"; log_msg "INFO" "Starting Log Viewer."
    while true; do
        # Clear screen for better readability
        if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
        print_color "$GREEN" "\nSelect log file or command to view:"
        echo " 1) Nvidia/CUDA Installer Log (/var/log/nvidia-installer.log or /var/log/cuda-installer.log)";
        echo " 2) DKMS Build Logs (Latest Nvidia Build)";
        echo " 3) APT History Log (/var/log/apt/history.log)";
        echo " 4) APT Terminal Log (/var/log/apt/term.log)";
        echo " 5) Xorg Log (/var/log/Xorg.0.log)";
        echo " 6) Xorg Log (Previous) (/var/log/Xorg.0.log.old)";
        echo " 7) Journalctl: Current Boot Errors (-b 0 -p err)";
        echo " 8) Journalctl: Previous Boot Errors (-b -1 -p err)";
        echo " 9) Journalctl: Kernel Messages (-k)";
        echo "10) This Script's Main Log ($MAIN_LOG_FILE)";
        echo "11) Back to Main Menu";
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-11]: ")" choice < /dev/tty

        case "$choice" in
            1) if [[ -f /var/log/cuda-installer.log ]]; then view_log_file "/var/log/cuda-installer.log" "CUDA Installer"; elif [[ -f /var/log/nvidia-installer.log ]]; then view_log_file "/var/log/nvidia-installer.log" "Nvidia Installer"; else print_color "$YELLOW" "No Nvidia/CUDA installer log found in /var/log."; log_msg "WARN" "No Nvidia/CUDA installer log found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty; fi ;;
            2) local latest_dkms; local k_v; k_v=$(uname -r);
               print_color "$CYAN" "Searching for latest Nvidia DKMS build log..."
               # Find the most recently modified make.log within any nvidia/*/KERNEL/ structure
               latest_dkms=$(find /var/lib/dkms/nvidia/ -name "make.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
               if [[ -n "$latest_dkms" ]]; then
                    view_log_file "$latest_dkms" "Latest DKMS Build ($(basename "$(dirname "$(dirname "$latest_dkms")")"))";
               else
                    print_color "$YELLOW" "No Nvidia DKMS make.log files found."; log_msg "WARN" "No Nvidia DKMS logs found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty;
               fi ;;
            3) view_log_file "/var/log/apt/history.log" "APT History";;
            4) view_log_file "/var/log/apt/term.log" "APT Terminal";;
            5) view_log_file "/var/log/Xorg.0.log" "Current Xorg Log";;
            6) view_log_file "/var/log/Xorg.0.log.old" "Previous Xorg Log";;
            7) print_color "$CYAN" "Showing current boot errors (journalctl -b 0 -p err)..."; journalctl --no-pager -b 0 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            8) print_color "$CYAN" "Showing previous boot errors (journalctl -b -1 -p err)..."; journalctl --no-pager -b -1 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            9) print_color "$CYAN" "Showing kernel messages for current boot (journalctl -k)..."; journalctl --no-pager -k < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
           10) view_log_file "$MAIN_LOG_FILE" "This Script Log";;
           11) log_msg "INFO" "Exiting Log Viewer."; break;;
            *) print_color "$RED" "Invalid selection." ;;
        esac;
        # No automatic pause needed here as view_log_file pauses, and journalctl commands have manual pause
    done; return 0;
}
# FINISH ### MODULE VIEW LOGS ###

# START ### UPDATE INITRAMFS FUNCTION ###
run_update_initramfs() {
    print_color "$PURPLE" "\n--- Module: Update Initramfs ---"; log_msg "INFO" "Starting Update Initramfs."
    print_color "$CYAN" "Identifying installed kernel versions..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;

    # Find installed kernel images and populate map
    while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then # Ensure k_ver is not empty
             kernels+=("$k_ver")
             kernel_map[$count]="$k_ver"
             ((count++))
        fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then
        print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1;
    fi

    print_color "$YELLOW" "Select kernel to update initramfs for:"
    for i in "${!kernel_map[@]}"; do
        echo " $i) ${kernel_map[$i]}" >&2
    done
    echo " $((count))) all (Update all installed kernels)" >&2
    echo " $((count+1))) Cancel" >&2

    local choice; local target_k=""
    while [[ -z "$target_k" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                target_k="${kernel_map[$choice]}"
            elif [[ "$choice" -eq "$count" ]]; then
                target_k="all"
            elif [[ "$choice" -eq $((count+1)) ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled initramfs update."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected initramfs update target: $target_k"
    print_color "$CYAN" "Running update-initramfs -u for kernel(s): $target_k...";

    if run_command "update-initramfs -u -k $target_k" true "Update Initramfs $target_k"; then
        print_color "$GREEN" "Initramfs update successful for $target_k."; log_msg "INFO" "Initramfs update ok: $target_k."
        return 0
    else
        print_color "$RED" "Initramfs update failed for $target_k."; log_msg "ERROR" "Initramfs update FAILED: $target_k.";
        return 1
    fi
}
# FINISH ### UPDATE INITRAMFS FUNCTION ###

# START ### NETWORK FIX FUNCTION ###
run_network_fix() {
    print_color "$PURPLE" "\n--- Module: Network Troubleshooting ---"; log_msg "INFO" "Starting Network Fix Module."
    print_color "$YELLOW" "This attempts common fixes for network issues, especially in CLI."

    while true; do
        print_color "$GREEN" "\nNetwork Troubleshooting Options:"
        echo " 1) Check NetworkManager Status"
        echo " 2) Restart NetworkManager Service"
        echo " 3) Show Network Devices (ip link/addr)"
        echo " 4) Show Recent Network Kernel Logs (dmesg/journalctl)"
        echo " 5) Apply Netplan Configuration"
        echo " 6) Check DNS Configuration (/etc/resolv.conf & systemd-resolved)"
        echo " 7) Check/Reinstall linux-firmware package"
        echo " 8) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty

        case "$choice" in
            1) print_color "$CYAN" "Checking NetworkManager status...";
               run_command "systemctl status NetworkManager.service --no-pager" false "NetworkManager Status";; # Added --no-pager
            2) print_color "$CYAN" "Attempting to restart NetworkManager...";
               if run_command "systemctl restart NetworkManager.service" false "Restart NetworkManager"; then
                   print_color "$GREEN" "NetworkManager restarted. Check status (Option 1) or test connection (e.g., ping 8.8.8.8).";
               else
                   print_color "$RED" "Failed to restart NetworkManager.";
               fi ;;
            3) print_color "$CYAN" "Showing network links (ip link show)...";
               run_command "ip link show" false "Show IP Links";
               print_color "$CYAN" "\nShowing network addresses (ip addr show)...";
               run_command "ip addr show" false "Show IP Addresses";;
            4) print_color "$CYAN" "Showing recent kernel messages related to network/firmware (last 50 lines)...";
               if command -v journalctl &> /dev/null; then
                    print_color "$CYAN" "(Using journalctl -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    journalctl --no-pager -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via journalctl."
               else
                    print_color "$CYAN" "(Using dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via dmesg."
               fi
               ;;
            5) if command -v netplan &> /dev/null; then
                   print_color "$CYAN" "Attempting to apply Netplan configuration (sudo netplan apply)...";
                   if run_command "netplan apply" true "Apply Netplan"; then # Log output in case of errors
                       print_color "$GREEN" "Netplan configuration applied. Check network status.";
                   else
                       print_color "$RED" "Failed to apply Netplan configuration. Check output/logs.";
                   fi
               else
                   print_color "$YELLOW" "netplan command not found. This system likely doesn't use Netplan. Skipping.";
                   log_msg "WARN" "netplan command not found.";
               fi ;;
            6) print_color "$CYAN" "Checking DNS settings (/etc/resolv.conf)...";
               if [[ -f "/etc/resolv.conf" ]]; then
                   run_command "cat /etc/resolv.conf" false "Show resolv.conf";
                   if [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink -f /etc/resolv.conf)" == */systemd/resolve/stub-resolv.conf ]]; then
                        print_color "$CYAN" "DNS appears managed by systemd-resolved. Checking service status...";
                        run_command "systemctl status systemd-resolved.service --no-pager" false "systemd-resolved status";
                   elif [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink /etc/resolv.conf)" == *run/NetworkManager/resolv.conf* ]]; then
                         print_color "$CYAN" "DNS appears managed by NetworkManager directly (using resolvconf?).";
                         print_color "$CYAN" "Check NetworkManager status (Option 1) and logs.";
                   elif [[ -L "/etc/resolv.conf" ]]; then
                        print_color "$CYAN" "DNS is a symlink to: $(readlink /etc/resolv.conf)";
                   else
                         print_color "$CYAN" "/etc/resolv.conf is a static file.";
                   fi
               else
                   print_color "$YELLOW" "/etc/resolv.conf not found.";
                   log_msg "WARN" "/etc/resolv.conf not found";
               fi ;;
            7) print_color "$CYAN" "Checking 'linux-firmware' package...";
                if dpkg-query -W -f='${Status}' linux-firmware 2>/dev/null | grep -q "ok installed"; then
                     print_color "$GREEN" "'linux-firmware' package is installed.";
                     log_msg "INFO" "linux-firmware package installed.";
                     if prompt_confirm "Reinstall 'linux-firmware' anyway (can take a while)?"; then
                        if run_command "apt-get update && apt-get install --reinstall -y linux-firmware" true "Reinstall linux-firmware"; then
                             print_color "$GREEN" "Reinstalled linux-firmware. A reboot might be needed."; log_msg "INFO" "Reinstalled linux-firmware.";
                        else
                             print_color "$RED" "Failed to reinstall linux-firmware."; log_msg "ERROR" "Failed reinstall linux-firmware";
                        fi
                     fi
                else
                     print_color "$YELLOW" "'linux-firmware' package NOT installed. This could cause hardware issues.";
                     log_msg "WARN" "linux-firmware package not installed.";
                      if prompt_confirm "Install 'linux-firmware' package (required for many devices)?"; then
                        if run_command "apt-get update && apt-get install -y linux-firmware" true "Install linux-firmware"; then
                             print_color "$GREEN" "Installed linux-firmware."; log_msg "INFO" "Installed linux-firmware.";
                             print_color "$YELLOW" "A reboot might be needed for firmware changes.";
                        else
                             print_color "$RED" "Failed to install linux-firmware."; log_msg "ERROR" "Failed install linux-firmware";
                        fi
                     fi
                fi ;;

            8) log_msg "INFO" "Exiting Network Fix module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         local last_status=$?
         # Pause only if an action was attempted (excluding exit/invalid)
         if [[ "$choice" =~ ^[1-7]$ ]]; then
             if [[ "$choice" =~ ^[1346]$ && $last_status -eq 0 ]]; then # Only show basic success for checks
                 print_color "$GREEN" "\nCheck complete.";
             elif [[ $last_status -ne 0 ]]; then
                  # Error message already printed by run_command
                  print_color "$YELLOW" "\nOperation finished with status $last_status.";
             else
                  # Successful operation (like restart, apply, install)
                  print_color "$GREEN" "\nOperation finished successfully.";
             fi
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Network menu...")" < /dev/tty
         fi
    done
    return 0
}
# FINISH ### NETWORK FIX FUNCTION ###

# START ### KERNEL PINNING FUNCTION ###
run_kernel_pinning() {
    print_color "$PURPLE" "\n--- Module: Kernel Package Pinning ---"; log_msg "INFO" "Starting Kernel Pinning Module."
    local pin_file="/etc/apt/preferences.d/99-mybitch-kernel-pin"

    while true; do
        print_color "$YELLOW" "\nKernel Pinning Options:";
        echo " 1) Pin to CURRENTLY RUNNING Kernel ($(uname -r))"
        echo " 2) Pin to a SPECIFIC Installed Kernel"
        echo " 3) View Current Pinning File ($pin_file)"
        echo " 4) Remove Pinning File ($pin_file)"
        echo " 5) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-5]: ")" choice < /dev/tty

        case "$choice" in
            1) target_k=$(uname -r);
               if [[ -z "$target_k" ]]; then print_color "$RED" "Could not determine current kernel."; continue; fi
               print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $target_k.";
               if prompt_confirm "Create/overwrite pinning file for $target_k?"; then
                  generate_and_apply_pin "$target_k" "$pin_file"
               fi
               ;;
            2) # List installed kernels for selection
               print_color "$CYAN" "Identifying installed kernel versions..."
               local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
               while IFS= read -r k_image; do local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//'); local found=0; for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done; if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi; done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)
               if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernels found!"; log_msg "ERROR" "No kernels found for pinning."; continue; fi

               print_color "$YELLOW" "Select kernel version to pin TO:"
               for i in "${!kernel_map[@]}"; do echo " $i) ${kernel_map[$i]}" >&2; done; echo " $((count))) Cancel" >&2;
               local pin_choice; local selected_k=""
               while [[ -z "$selected_k" ]]; do read -r -p "$(print_color "$YELLOW" "Choice: ")" pin_choice < /dev/tty; if [[ "$pin_choice" =~ ^[0-9]+$ ]]; then if [[ "$pin_choice" -ge 1 && "$pin_choice" -lt "$count" ]]; then selected_k="${kernel_map[$pin_choice]}"; elif [[ "$pin_choice" -eq "$count" ]]; then print_color "$YELLOW" "Cancelled."; selected_k="cancel"; else print_color "$RED" "Invalid."; fi; else print_color "$RED" "Invalid."; fi; done
               if [[ "$selected_k" != "cancel" ]]; then
                    print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $selected_k.";
                    if prompt_confirm "Create/overwrite pinning file for $selected_k?"; then
                        generate_and_apply_pin "$selected_k" "$pin_file"
                    fi
               fi
               ;;
            3) print_color "$CYAN" "Contents of $pin_file:";
               if [[ -f "$pin_file" ]]; then run_command "cat $pin_file" false "View Pin File"; else print_color "$YELLOW" "Pin file does not exist."; fi
               ;;
            4) print_color "$YELLOW" "Removing kernel pinning file: $pin_file";
               if [[ ! -f "$pin_file" ]]; then print_color "$YELLOW" "Pin file does not exist."; continue; fi;
               if prompt_confirm "Remove the pinning file? (Allows kernel upgrades)"; then
                   if run_command "rm -vf $pin_file" false "Remove Pin File"; then
                       print_color "$GREEN" "Pin file removed. Run 'sudo apt update' for changes to take effect."; log_msg "INFO" "Removed pin file $pin_file."
                       run_command "apt-get update" false "Update APT after pin removal"
                   else
                       log_msg "ERROR" "Failed to remove pin file.";
                   fi
               fi
               ;;
            5) log_msg "INFO" "Exiting Kernel Pinning module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         # Add pause after actions
         if [[ "$choice" =~ ^[1-4]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Pinning menu...")" < /dev/tty
         fi
    done
    return 0
}

generate_and_apply_pin() {
    local pin_k="$1"
    local pin_f="$2"
    log_msg "INFO" "Generating pin file $pin_f for kernel $pin_k"

    # Extract base version number (e.g., 6.8.0-40) for wildcard matching
    local pin_base_ver; pin_base_ver=$(echo "$pin_k" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+')
    if [[ -z "$pin_base_ver" ]]; then
        print_color "$RED" "Could not extract base version from $pin_k for pinning."; log_msg "ERROR" "Could not extract base version from $pin_k"; return 1;
    fi

    local pin_content; cat << PIN_EOF > /tmp/kernel_pin_content
# Kernel Pinning Configuration generated by nvidia-mybitch.sh
# Prevents upgrades beyond kernel version containing '$pin_base_ver'

# Pin generic meta-packages and specific version packages
Package: linux-image-generic linux-headers-generic linux-generic* linux-image-*-generic linux-headers-*-generic linux-modules-*-generic linux-modules-extra-*-generic
Pin: version ${pin_base_ver}.*
Pin-Priority: 1001

# Example: Explicitly block a known bad version (Uncomment and edit if needed)
# Package: linux-image-6.8.0-57-generic linux-headers-6.8.0-57-generic linux-modules-6.8.0-57-generic linux-modules-extra-6.8.0-57-generic
# Pin: version 6.8.0-57.*
# Pin-Priority: -1

PIN_EOF

    pin_content=$(cat /tmp/kernel_pin_content)
    rm /tmp/kernel_pin_content

    print_color "$PURPLE" "--- Pinning File Content ---"
    print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$pin_content"; print_color "$PURPLE" "--------------------------" # Use type_effect here

    if ! prompt_confirm "Write this content to $pin_f?"; then log_msg "USER" "Cancelled writing pin file."; return 1; fi

    # Use sudo tee to write the file as root
    if echo "$pin_content" | sudo tee "$pin_f" > /dev/null; then
        sudo chown root:root "$pin_f" && sudo chmod 644 "$pin_f"
        print_color "$GREEN" "Pinning file $pin_f created/updated."; log_msg "INFO" "Wrote pin file $pin_f for $pin_k."
        print_color "$CYAN" "Running 'sudo apt update' to apply changes..."
        if run_command "apt-get update" false "Update APT after pinning"; then
             print_color "$GREEN" "APT cache updated. Kernel packages are now pinned.";
        else
             print_color "$RED" "APT update failed after pinning.";
        fi
        return 0
    else
        print_color "$RED" "Failed to write pinning file!"; log_msg "ERROR" "Failed to write pin file $pin_f."
        return 1
    fi
}
# FINISH ### KERNEL PINNING FUNCTION ###

# START ### GUIDED INSTALL FUNCTION ###
run_guided_install() {
    print_color "$PURPLE" "\n--- Guided Install: Nvidia Driver + CUDA (Method B Recommended) ---"; log_msg "INFO" "Starting Guided Install."
    print_color "$YELLOW" "This will run the recommended sequence based on successful logs:";
    print_color "$CYAN" "  1. Enhanced Deep Clean";
    print_color "$CYAN" "  2. Install Driver via Nvidia Repo (cuda-drivers)";
    print_color "$CYAN" "  3. Install CUDA Toolkit via APT (from Nvidia Repo)";
    print_color "$CYAN" "  4. Update Initramfs";
    print_color "$CYAN" "  5. Recommend Kernel Pinning";
    print_color "$RED" "Ensure you are booted into your desired WORKING kernel first!";
    local current_k; current_k=$(uname -r); print_color "$YELLOW" "(Currently running: $current_k)";

    if ! prompt_confirm "Proceed with Guided Install on kernel $current_k?"; then return 1; fi

    print_color "$PURPLE" "\n--- Step 1: Enhanced Deep Clean ---";
    if ! run_nvidia_cleanup; then
        log_msg "ERROR" "Guided Install: Deep Clean failed."; return 1;
    fi
    print_color "$GREEN" "Deep Clean Completed. Reboot highly recommended before proceeding.";
    if ! prompt_confirm "Continue install without rebooting (NOT RECOMMENDED)?"; then
        print_color "$YELLOW" "Exiting Guided Install. Please reboot into your desired kernel ($current_k) and run again."; log_msg "USER" "Aborted Guided Install for reboot."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 2: Install Driver via Nvidia Repo (cuda-drivers) ---";
    # Ensure repo is setup AND install the driver
    if ! install_nvidia_apt_official_repo "false"; then # Pass "false" to ensure it installs
        log_msg "ERROR" "Guided Install: Nvidia Repo Driver install failed."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 3: Install CUDA Toolkit via APT (from Nvidia Repo) ---";
    if ! install_cuda_toolkit_apt_core; then # This helper function installs the toolkit
        log_msg "ERROR" "Guided Install: CUDA Toolkit install failed."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 4: Update Initramfs ---";
    print_color "$CYAN" "Updating initramfs for all kernels...";
    if ! run_command "update-initramfs -u -k all" true "Guided Install Initramfs Update"; then
         log_msg "ERROR" "Guided Install: Initramfs update failed."; # Continue but warn
    fi

    print_color "$GREEN" "\n--- Guided Install Steps Completed Successfully ---";
    log_msg "INFO" "Guided Install finished successfully.";
    print_color "$YELLOW" "Reboot REQUIRED to activate drivers/toolkit.";
    print_color "$CYAN" "After rebooting into the working kernel ($current_k), verify with 'nvidia-smi' and 'nvcc --version'.";

    # Recommend Pinning
    print_color "$PURPLE" "\n--- Step 5: Recommendation - Kernel Pinning ---";
    print_color "$YELLOW" "To prevent problematic kernel updates from breaking this setup,";
    print_color "$YELLOW" "it's strongly recommended to PIN your current working kernel ($current_k).";
    if prompt_confirm "Go to Kernel Pinning module now?"; then
        run_kernel_pinning
    else
        print_color "$CYAN" "You can access Kernel Pinning later via Menu 9 -> 6.";
    fi
    return 0
}
# FINISH ### GUIDED INSTALL FUNCTION ###

# START ### SYSTEM PREP UTILS SUBMENU ###
run_system_prep_utils_submenu() {
     while true; do
         if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
         print_color "$PURPLE" "\n=== System Prep & Utils Submenu ===";
         echo "  $(print_color "$CYAN" "1)") Manage Display Manager (Stop/Start/Status)";
         echo "  $(print_color "$CYAN" "2)") Prepare Build Environment (DKMS, Headers, Tools)";
         echo "  $(print_color "$CYAN" "3)") Manage GCC Version (Check, Install 12, Show Switch Cmds)";
         echo "  $(print_color "$CYAN" "4)") Update Initramfs (For specific kernel or all)";
         echo "  $(print_color "$CYAN" "5)") Network Troubleshooting Tools";
         echo "  $(print_color "$CYAN" "6)") Kernel Package Pinning (Hold/Unhold)"; # Added pinning
         echo "  $(print_color "$CYAN" "7)") Return to Main Menu";
         local choice;
         read -r -p "$(print_color "$YELLOW" "Enter choice [1-7]: ")" choice < /dev/tty;
         case "$choice" in
             1) run_manage_display_manager ;;
             2) run_prepare_build_env ;;
             3) run_manage_gcc ;;
             4) run_update_initramfs ;;
             5) run_network_fix ;;
             6) run_kernel_pinning ;; # Added pinning call
             7) break;; # Exit submenu loop
             *) print_color "$RED" "Invalid selection.";;
         esac;
         local last_status=$?;
         # Only pause if an action ran (choice 1-6)
         if [[ "$choice" =~ ^[1-6]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to submenu...")" < /dev/tty;
         fi;
    done;
    return 0;
}
# FINISH ### SYSTEM PREP UTILS SUBMENU ###

# START ### MAIN MENU FUNCTION ###
main_menu() {
    print_color "$PURPLE" "\n=== $(print_color "$GREEN" "NVIDIA") $(print_color "$CYAN" "MyBitch") $(print_color "$PURPLE" "Manager") v$SCRIPT_VERSION ===";
    print_color "$GREEN" "Select an operation:";
    echo "  $(print_color "$CYAN" " 1)") Guided Install (Recommended: Clean -> Nvidia Repo Driver+CUDA)";
    echo "  $(print_color "$CYAN" " 2)") NVIDIA Deep Clean (Manual Step)";
    echo "  $(print_color "$CYAN" " 3)") NVIDIA Driver Install (Manual Step - APT Std, APT Nvidia, Runfile)";
    echo "  $(print_color "$CYAN" " 4)") Install CUDA Toolkit (Manual Step - APT or Runfile)";
    echo "  $(print_color "$CYAN" " 5)") Blacklist Nouveau Driver";
    echo "  $(print_color "$CYAN" " 6)") GRUB Fix / Reinstall / Params (Presets & Custom)";
    echo "  $(print_color "$CYAN" " 7)") Kernel Reset (Remove & Reinstall)";
    echo "  $(print_color "$CYAN" " 8)") Update Initramfs (Target specific kernel)";
    echo "  $(print_color "$CYAN" " 9)") System Prep & Utilities (DM, BuildEnv, GCC, Initramfs, Network, Pinning)"; # Updated desc
    echo "  $(print_color "$CYAN" "10)") Chroot Helper (Live OS ONLY)";
    echo "  $(print_color "$CYAN" "11)") View Logs (System, Nvidia, APT, etc.)";
    echo "  $(print_color "$CYAN" "12)") Exit";

    local choice;
    read -r -p "$(print_color "$YELLOW" "Enter choice [1-12]: ")" choice < /dev/tty;

    case "$choice" in
        1) run_guided_install ;;          # NEW
        2) run_nvidia_cleanup ;;           # Was 1
        3) run_nvidia_install ;;           # Was 2
        4) run_cuda_install ;;             # Was 3
        5) run_nouveau_blacklist ;;        # Was 4
        6) run_grub_fix ;;                 # Was 5
        7) run_kernel_fix ;;               # Was 6
        8) run_update_initramfs ;;         # Was 7
        9) run_system_prep_utils_submenu ;; # Was 8, now includes Pinning
       10) run_chroot_helper ;;            # Was 9
       11) run_view_logs ;;                # Was 10
       12) print_color "$GREEN" "Keep hustlin'. Exiting..."; log_msg "INFO" "Exiting script."; exit 0 ;; # Was 11
        *) print_color "$RED" "Invalid selection." ;;
    esac

    local last_status=$?;
    # Don't pause after invalid choice or exit
    if [[ "$choice" -ge 1 && "$choice" -le 11 ]]; then # Pause for options 1-11
        # Let sub-modules handle their own success/fail messages
        read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to main menu...")" < /dev/tty;
    fi;
}
# FINISH ### MAIN MENU FUNCTION ###

# START ### SCRIPT RUNNER ###
# Check sudo FIRST - it sets up USER_HOME and LOG paths
check_sudo

# Append to log file for history across runs
log_msg "INFO" "====== GPU Manager Started. Version $SCRIPT_VERSION ======"
log_msg "INFO" "Running as EUID=$EUID, User=$SUDO_USER, Home=$USER_HOME"

# Main loop
while true; do
    # Clear screen at the start of each main menu loop
    if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
    main_menu
done
# FINISH ### SCRIPT RUNNER ####!/usr/bin/env bash

# NVIDIA Management Script - "nvidia-mybitch.sh" v1.11
# Built for the streets, respects the hustle. No more bullshit placeholders.

# START ### CONFIGURATION ###
SCRIPT_VERSION="1.11" # Guided Install, Kernel Pinning, Enhanced Clean
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
    # Check if log file path is set, exit if not (should be set by check_sudo)
    if [[ -z "$MAIN_LOG_FILE" ]]; then echo "FATAL: Main log file path not initialized!" >&2; exit 1; fi
    # Check if log file is writable, attempt to fix if not
    if [[ ! -w "$MAIN_LOG_FILE" && -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE not writable. Attempting chown..." >&2
         # Need sudo user context here, should be available
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "FATAL: Failed to chown log file. Cannot log." >&2; exit 1; }
         if [[ ! -w "$MAIN_LOG_FILE" ]]; then echo "FATAL: Log file still not writable after chown. Cannot log." >&2; exit 1; fi
    elif [[ ! -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE does not exist. Attempting touch..." >&2
         touch "$MAIN_LOG_FILE" || { echo "FATAL: Failed to touch log file. Cannot log." >&2; exit 1; }
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "Warning: Failed to chown new log file." >&2; }
    fi

    local level="$1"; local message="$2"; local log_line;
    log_line="$(date +'%Y-%m-%d %H:%M:%S') [$level] - $message"
    # Append to the log file
    echo "$log_line" >> "$MAIN_LOG_FILE"
    # Print ERROR and WARN messages to stderr as well, with color
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        local color="$YELLOW"; [[ "$level" == "ERROR" ]] && color="$RED"
        print_color "$color" "[$level] $message"
    fi
}


prompt_confirm() {
    local message="$1"; local default_choice="${2:-N}"; local psfx="[y/N]";
    [[ "$default_choice" =~ ^[Yy]$ ]] && psfx="[Y/n]"
    while true; do
        # Redirect stdin from /dev/tty to ensure it reads from keyboard even if script input is piped
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

type_effect() {
    local text="$1"; local delay="${2:-0.03}";
    # Check if NO_TYPE_EFFECT variable is set
    if [[ -z "$NO_TYPE_EFFECT" ]]; then
        local i;
        for (( i=0; i<${#text}; i++ )); do
             printf "%c" "${text:$i:1}" >&2;
             # Use awk for potentially more random sleep interval within bounds
             sleep "$(awk -v min=0.01 -v max="$delay" 'BEGIN{srand(); print min+rand()*(max-min)}')";
         done
    else
         # If NO_TYPE_EFFECT is set, just print the text without delay
         printf "%s" "$text" >&2;
    fi;
    # Always print a newline after the effect/text
    echo >&2;
}


check_sudo() {
    # Ensures script is run with sudo and determines the original user's home directory
    if [[ -z "$SUDO_USER" || "$EUID" -ne 0 ]]; then print_color "$RED" "Error: This script must be run using sudo."; exit 1; fi

    # Attempt to get the user's home directory reliably
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        # Log initial failure before fallback
        echo -e "${YELLOW}Warn: Could not reliably determine user home via getent for $SUDO_USER. Falling back...${NC}" >&2
        USER_HOME=$(eval echo ~"$SUDO_USER") # Fallback method
        if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
             print_color "$RED" "FATAL: Could not determine home directory for user '$SUDO_USER'. Exiting."
             # No log_msg here as logging isn't set up yet
             exit 1
        fi
    fi
    # Check if the determined home is /root, which might be wrong unless root logged in directly
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
        print_color "$YELLOW" "Warning: Determined user home is /root, but sudo user is $SUDO_USER. This might be incorrect."
        # Log this warning once logging is initialized below
     fi

    LOG_DIR="$USER_HOME/gpu_manager_logs"; MAIN_LOG_FILE="$LOG_DIR/nvidia-mybitch_main_$(date +%Y%m%d_%H%M%S).log";
    # Ensure log directory exists
    mkdir -p "$LOG_DIR" || { print_color "$RED" "FATAL: Could not create log directory '$LOG_DIR'"; exit 1; };
    # Create log file
    touch "$MAIN_LOG_FILE" || { print_color "$RED" "FATAL: Could not create main log file '$MAIN_LOG_FILE'"; exit 1; };
    # Change ownership to the original user so they can access logs without sudo later
    chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR" "$MAIN_LOG_FILE" || print_color "$YELLOW" "Warn: Could not chown log directory/file to $SUDO_USER."

    # Now that logging is set up, log the earlier warning if needed
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
         log_msg "WARN" "Determined user home is /root, but sudo user is $SUDO_USER."
     fi
    log_msg "INFO" "Sudo check passed. Original User: $SUDO_USER. User Home: $USER_HOME. Logging to: $MAIN_LOG_FILE."
}

check_tty() {
    # Check if running in a TTY and not under X/Wayland (DISPLAY is set)
    # Allow override if user confirms
    if ! tty -s; then
        log_msg "WARN" "Script not running in a TTY (stdin is not a terminal)."
        print_color "$YELLOW" "Warning: Not running in a TTY. Interactive prompts might behave unexpectedly."
        if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Not TTY."; return 1; fi
    elif [[ -n "$DISPLAY" ]]; then
         log_msg "WARN" "DISPLAY environment variable is set ($DISPLAY). Running under X/Wayland?"
         print_color "$YELLOW" "Warning: Running inside a graphical session? Some operations (like stopping DM) work best from a TTY."
         if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Running under GUI."; return 1; fi
    fi
    return 0;
}


get_display_manager() {
  local detected_dm=""; local final_dm=""; local user_input; log_msg "INFO" "Detecting DM...";
  # Check for common DMs via systemctl active state
  if systemctl list-units --type=service --state=active | grep -q -E 'gdm[0-9]*\.service|gdm\.service'; then detected_dm="gdm3.service";
  elif systemctl list-units --type=service --state=active | grep -q 'sddm\.service'; then detected_dm="sddm.service";
  elif systemctl list-units --type=service --state=active | grep -q 'lightdm\.service'; then detected_dm="lightdm.service";
  # Add other DMs here if needed (e.g., lxdm)
  fi;

  if [[ -n "$detected_dm" ]]; then
      log_msg "INFO" "Detected active DM: $detected_dm";
      read -r -p "$(print_color "$YELLOW" "Detected active Display Manager '$detected_dm'. Is this correct? [Y/n]: ")" confirm < /dev/tty; confirm="${confirm:-Y}";
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
           final_dm="$detected_dm"; log_msg "USER" "Confirmed DM: $final_dm";
      else
           log_msg "USER" "Rejected detected DM."; detected_dm=""; # Clear detected if rejected
      fi;
  fi;

  # If no DM confirmed or detected
  if [[ -z "$final_dm" ]]; then
       print_color "$YELLOW" "Could not detect/confirm Display Manager.";
       read -r -p "$(print_color "$YELLOW" "Enter your Display Manager service name (e.g., gdm3.service, sddm.service, lightdm.service) or leave blank to skip DM operations: ")" user_input < /dev/tty;
       if [[ -n "$user_input" ]]; then
            # Append .service if missing
            if [[ ! "$user_input" == *".service" ]]; then final_dm="${user_input}.service"; else final_dm="$user_input"; fi;
            log_msg "USER" "Manual DM entry: $final_dm";
            # Optional: Add a basic check if the service name seems valid?
            # if ! systemctl list-unit-files | grep -q "^${final_dm}"; then print_color "$YELLOW" "Warning: Service '$final_dm' not found by systemctl."; fi
       else
           print_color "$YELLOW" "Skipping Display Manager operations."; log_msg "USER" "Skipped DM entry."; final_dm="";
       fi;
  fi;

  echo "$final_dm"; # Return the determined DM name (or empty string)
  if [[ -n "$final_dm" ]]; then return 0; else return 1; fi; # Return status indicates if a DM was identified
}

run_command() {
    local cmd_string="$1"
    local log_output_to_file="${2:-false}" # Controls logging command's stdout/stderr to SEPARATE file (true/false)
    local cmd_desc="${3:-Command}"
    local tee_to_tty="${4:-true}" # Controls whether output is ALSO shown on screen (TTY)

    log_msg "EXEC" "($cmd_desc): $cmd_string"
    if [[ "$tee_to_tty" == true ]]; then
        print_color "$CYAN" "Running: $cmd_string"
    else
        # Avoid printing the command if output is hidden, just log it was executed
        log_msg "INFO" "Executing (output to log only): ($cmd_desc)"
    fi

    local output_log_file="${LOG_DIR}/cmd_output_$(date +%s)_$(echo "$cmd_desc" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c -50).log"
    local status
    # Base tee command always appends to main log file
    local tee_cmd_main="tee -a \"$MAIN_LOG_FILE\""
    local final_exec_cmd

    # Build the command execution string based on logging/display options
    # Pipe stderr to stdout using 2>&1 so both streams are processed by tee
    final_exec_cmd="(eval $cmd_string) 2>&1" # Start with the actual command + stderr redirection

    # Pipe through tee for main log file always
    final_exec_cmd+=" | $tee_cmd_main"

    # Optionally pipe through tee for separate log file
    if [[ "$log_output_to_file" == true ]]; then
        touch "$output_log_file" && chown "$SUDO_USER:$SUDO_USER" "$output_log_file" || log_msg "WARN" "Could not touch/chown output log $output_log_file"
        final_exec_cmd+=" | tee \"$output_log_file\""
        if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Logging output to $output_log_file AND main log AND screen)"
        else
             print_color "$CYAN" "(Logging output to $output_log_file AND main log ONLY)"
        fi
    else
         if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Command output will appear below and in main log)"
         else
              print_color "$CYAN" "(Command output to main log ONLY)"
          fi
    fi

    # Optionally redirect the final output to /dev/tty if requested
    if [[ "$tee_to_tty" == true ]]; then
        final_exec_cmd+=" > /dev/tty"
    else
        # If not teeing to tty, send final output to /dev/null to suppress it
        final_exec_cmd+=" > /dev/null"
    fi


    # Execute using bash -c to handle complex commands and pipes properly
    bash -c "$final_exec_cmd"
    # Get the exit status of the original 'eval' command using PIPESTATUS[0]
    # This requires the command to be the first element in the pipe handled by bash -c
    # We need to rethink how to capture the status correctly with all the tees.
    # A subshell approach might be better.

    # --- Alternative Status Capture (More reliable with complex pipes) ---
    local temp_status_file; temp_status_file=$(mktemp)
    final_exec_cmd="(eval $cmd_string; echo \$? > $temp_status_file) 2>&1 | $tee_cmd_main"
    if [[ "$log_output_to_file" == true ]]; then
        final_exec_cmd+=" | tee \"$output_log_file\""
    fi
    if [[ "$tee_to_tty" == true ]]; then
        final_exec_cmd+=" > /dev/tty"
    else
        final_exec_cmd+=" > /dev/null"
    fi

    bash -c "$final_exec_cmd"
    status=$(cat "$temp_status_file")
    rm "$temp_status_file"
    # --- End Alternative Status Capture ---


    log_msg "INFO" "($cmd_desc) finished status: $status"

    if [[ "$status" -ne 0 ]]; then
        # Ensure error message is visible even if tee_to_tty was false for the command itself
        print_color "$RED" "Command ($cmd_desc) failed! Status: $status"
        print_color "$YELLOW" "Check main log file: $MAIN_LOG_FILE"
        if [[ "$log_output_to_file" == true ]]; then print_color "$YELLOW" "Also check separate log: $output_log_file"; fi
        return "$status" # Use numeric return status
    fi

    # Clean up empty separate log file if it was created but not needed
    if [[ "$log_output_to_file" == true && -f "$output_log_file" && ! -s "$output_log_file" ]]; then
        log_msg "INFO" "Removing empty separate log file: $output_log_file"
        rm "$output_log_file" &> /dev/null
    fi
    return 0
}


view_log_file() {
    local log_path="$1"; local log_desc="$2";
    print_color "$CYAN" "Viewing: $log_desc ($log_path)"; log_msg "INFO" "Viewing log: $log_desc ($log_path)"
    if [[ ! -f "$log_path" ]]; then print_color "$YELLOW" "Not found: $log_path"; log_msg "WARN" "Log not found: $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Check read permissions for the effective user (root)
    if [[ ! -r "$log_path" ]]; then print_color "$RED" "Cannot read (check permissions): $log_path"; log_msg "ERROR" "Cannot read log (permissions?): $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Use less with flags for better viewing, ensuring it reads from TTY
    less -Rf "$log_path" < /dev/tty
}
# FINISH ### HELPER FUNCTIONS ###

# START ### MODULE DISPLAY MANAGER ###
run_manage_display_manager() {
    print_color "$PURPLE" "\n--- Module: Display Manager Control ---"; log_msg "INFO" "Starting DM Control.";
    local dm; dm=$(get_display_manager); if [[ $? -ne 0 || -z "$dm" ]]; then print_color "$YELLOW" "Cannot manage Display Manager (not found or skipped)."; return 1; fi;
    print_color "$YELLOW" "Action for Display Manager '$dm':"; echo " 1) Stop"; echo " 2) Start"; echo " 3) Status"; echo " 4) Cancel"; local choice;
    read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;
    case "$choice" in
        1) if ! check_tty; then return 1; fi; # Extra check before stopping DM
           run_command "systemctl stop $dm" false "Stop DM";;
        2) run_command "systemctl start $dm" false "Start DM";;
        3) run_command "systemctl status $dm --no-pager" false "DM Status";; # Added no-pager
        4) log_msg "USER" "Cancelled DM action."; return 1;; *) print_color "$RED" "Invalid."; return 1;;
    esac; return $?;
}
# FINISH ### MODULE DISPLAY MANAGER ###

# START ### MODULE PREPARE BUILD ENV ###
run_prepare_build_env() {
    print_color "$PURPLE" "\n--- Module: Prepare Build Environment ---"; log_msg "INFO" "Starting Build Env Prep.";
    print_color "$CYAN" "Ensures DKMS, build-essential, and headers for CURRENT kernel are installed.";
    local k; k=$(uname -r); local hdr="linux-headers-${k}"; local req="dkms build-essential ${hdr}";
    print_color "$CYAN" "Checking required packages (dkms, build-essential, $hdr)..."; log_msg "INFO" "Checking build env packages: $req"; local missing="";
    for pkg in dkms build-essential "$hdr"; do if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then missing+="$pkg "; fi; done;
    if [[ -n "$missing" ]]; then log_msg "WARN" "Missing build env packages: ${missing% }"; print_color "$YELLOW" "Missing packages: ${missing% }"; if ! prompt_confirm "Install/reinstall required packages?"; then log_msg "USER" "Skipped build env pkg install."; return 1; fi;
        print_color "$CYAN" "Running apt-get update & install..."; if ! run_command "apt-get update" false "Update build env"; then log_msg "WARN" "apt-get update failed."; fi; if ! run_command "apt-get install --reinstall -y $req" true "Install build env"; then log_msg "ERROR" "Build env install failed."; return 1; fi; log_msg "INFO" "Build env pkgs installed/reinstalled."; print_color "$GREEN" "Build env packages installed/reinstalled.";
    else log_msg "INFO" "Build env packages already present."; print_color "$GREEN" "Required build environment packages seem installed."; if prompt_confirm "Reinstall them anyway?"; then print_color "$CYAN" "Running apt-get update & reinstall..."; if ! run_command "apt-get update && apt-get install --reinstall -y $req" true "Reinstall build env"; then log_msg "ERROR" "Build env reinstall failed."; return 1; fi; log_msg "INFO" "Build env packages reinstalled."; print_color "$GREEN" "Build env packages reinstalled."; fi; fi;
    print_color "$CYAN" "Checking DKMS status..."; run_command "dkms status" false "DKMS Status Check"; print_color "$GREEN" "\n--- Build Env Prep Finished ---"; log_msg "INFO" "Build Env Prep finished."; return 0;
}
# FINISH ### MODULE PREPARE BUILD ENV ###

# START ### MODULE MANAGE GCC ###
run_manage_gcc() {
    print_color "$PURPLE" "\n--- Module: Manage GCC Version ---"; log_msg "INFO" "Starting GCC Mgmt.";
    local gcc; gcc=$(gcc --version | head -n1); local gpp; gpp=$(g++ --version | head -n1); print_color "$CYAN" "Current Default GCC: $gcc"; print_color "$CYAN" "Current Default G++: $gpp"; log_msg "INFO" "Current GCC: $gcc / G++: $gpp";
    print_color "$YELLOW" "\nNote: Nvidia drivers usually build with the default GCC for your Ubuntu release (e.g., 11 or 12 for 22.04).";
    print_color "$YELLOW" "Switching is generally only needed if a specific driver build fails and explicitly requires a different version.";
    echo "\nOptions:"; echo " 1) Check alternatives (installed versions)"; echo " 2) Install GCC/G++ 12 (if not present)"; echo " 3) Show manual switch commands (update-alternatives)"; echo " 4) Back"; local choice;
    read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;
    case "$choice" in
        1) print_color "$CYAN" "Checking gcc alternatives..."; run_command "update-alternatives --display gcc" false "GCC Alts"; print_color "$CYAN" "Checking g++ alternatives..."; run_command "update-alternatives --display g++" false "G++ Alts";;
        2) print_color "$CYAN" "Checking gcc-12/g++-12..."; if dpkg-query -W -f='${Status}' gcc-12 2>/dev/null | grep -q "ok installed" && dpkg-query -W -f='${Status}' g++-12 2>/dev/null | grep -q "ok installed"; then print_color "$GREEN" "gcc-12 & g++-12 already installed."; log_msg "INFO" "gcc-12/g++-12 already installed."; else print_color "$YELLOW" "gcc-12/g++-12 not found."; if prompt_confirm "Install gcc-12 and g++-12?"; then if run_command "apt-get update && apt-get install -y gcc-12 g++-12" true "Install GCC 12"; then log_msg "INFO" "Installed gcc-12/g++-12."; print_color "$YELLOW" "You may need to configure alternatives manually (Option 3) if needed."; else log_msg "ERROR" "Install GCC 12 failed."; fi; fi; fi;;
        3) print_color "$YELLOW" "MANUAL switch commands (run as needed):"; print_color "$CYAN" "# 1. Install versions if needed (see Option 2)"; print_color "$CYAN" "# 2. Add versions to alternatives system (adjust paths/priorities as needed):"; print_color "$CYAN" "sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 --slave /usr/bin/g++ g++ /usr/bin/g++-11"; print_color "$CYAN" "sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 --slave /usr/bin/g++ g++ /usr/bin/g++-12"; print_color "$CYAN" "# 3. Choose the default version interactively:"; print_color "$CYAN" "sudo update-alternatives --config gcc"; log_msg "INFO" "Showed manual GCC switch cmds.";;
        4) return 0;; *) print_color "$RED" "Invalid."; return 1;;
    esac; return 0;
}
# FINISH ### MODULE MANAGE GCC ###

# START ### MODULE NOUVEAU BLACKLIST ###
run_nouveau_blacklist() {
    print_color "$PURPLE" "\n--- Module: Blacklist Nouveau Driver ---"; log_msg "INFO" "Starting Nouveau Blacklist.";
    local conf="/etc/modprobe.d/blacklist-nvidia-nouveau-mybitch.conf"; # Use unique name
    local content="blacklist nouveau\noptions nouveau modeset=0";
    if [[ -f "$conf" ]]; then
         print_color "$YELLOW" "Blacklist file '$conf' already exists.";
         if ! prompt_confirm "Overwrite existing file?"; then log_msg "USER" "Skipped blacklist overwrite."; return 1; fi
    elif ! prompt_confirm "Create modprobe config '$conf' to blacklist Nouveau?"; then
         log_msg "USER" "Cancelled blacklist creation."; return 1;
    fi;
    print_color "$CYAN" "Creating/Overwriting $conf...";
    # Use run_command to create the file safely with sudo
    if run_command "echo -e \"$content\" | tee \"$conf\" > /dev/null" false "Write Nouveau Blacklist"; then
        print_color "$CYAN" "Running update-initramfs for all kernels...";
        if run_command "update-initramfs -u -k all" true "Update initramfs for blacklist"; then
            print_color "$GREEN" "Nouveau blacklisted successfully."; print_color "$YELLOW" "A reboot is required for changes to take effect."; log_msg "INFO" "Nouveau blacklisted ok."; return 0;
        else log_msg "ERROR" "update-initramfs failed after blacklist."; return 1; fi
    else log_msg "ERROR" "Write blacklist file failed."; return 1; fi
}
# FINISH ### MODULE NOUVEAU BLACKLIST ###

# START ### MODULE NVIDIA CLEANUP ###
run_nvidia_cleanup() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Deep Clean (Enhanced v1.11) ---"; log_msg "INFO" "Starting Enhanced Deep Clean.";
    print_color "$YELLOW" "This attempts to COMPLETELY remove Nvidia drivers, CUDA, configs, and DKMS entries.";
    if ! prompt_confirm "Proceed with Enhanced Deep Clean?"; then return 1; fi;
    # No TTY check here, user knows the risks
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then print_color "$CYAN" "Stopping Display Manager ($dm)..."; run_command "systemctl stop $dm" false "Stop DM Clean" || print_color "$YELLOW" "Warn: Stop DM failed, continuing anyway."; fi

    print_color "$CYAN" "\nStep 1: Removing DKMS modules..."; local dkms_mods; dkms_mods=$(dkms status | grep -Ei 'nvidia|nvidia-fs' | awk -F',|/' '{print $1"/"$2}' | sort -u); if [[ -n "$dkms_mods" ]]; then local fail=0; for mod in $dkms_mods; do print_color "$YELLOW" " Removing DKMS module: $mod"; run_command "dkms remove $mod --all" false "Remove DKMS $mod" || fail=1; done; if [[ $fail -eq 1 ]]; then log_msg "ERROR" "One or more DKMS remove commands failed."; fi; print_color "$CYAN" " Verifying DKMS status..."; sleep 1; if dkms status | grep -qEi 'nvidia|nvidia-fs'; then log_msg "WARN" "Nvidia DKMS modules may still remain!"; print_color "$YELLOW" "Warning: Nvidia DKMS modules may still remain! Check 'dkms status'."; else print_color "$GREEN" " All Nvidia DKMS modules removed."; log_msg "INFO" "Nvidia DKMS modules removed."; fi; else print_color "$GREEN" " No Nvidia DKMS modules found to remove."; log_msg "INFO" "No Nvidia DKMS modules found."; fi
    print_color "$CYAN" " Manually removing DKMS source tree (extra precaution)...";
    run_command "rm -rf /var/lib/dkms/nvidia*" false "Remove DKMS source"

    print_color "$CYAN" "\nStep 2: Finding & Purging related packages (Aggressive)...";
    # Expanded list with more potential packages
    local pkgs_pattern='nvidia|cuda|libnvidia|cublas|cufft|cufile|curand|cusolver|cusparse|npp|nvjpeg|libnvjitlink|nsight';
    local pkgs; pkgs=$(dpkg -l | grep -Ei "$pkgs_pattern" | grep -E '^ii' | awk '{print $2}' | tr '\n' ' ');
    if [[ -z "$pkgs" ]]; then print_color "$GREEN" " No related packages found via dpkg."; log_msg "INFO" "No packages found for purge."; else print_color "$YELLOW" " Found potentially related packages:"; echo "$pkgs" | fold -s -w 80 | sed 's/^/    /' >&2; log_msg "INFO" "Aggressive Purge list: $pkgs"; if ! prompt_confirm "Purge these packages?"; then log_msg "USER" "Cancelled package purge."; return 1; fi; print_color "$CYAN" " Purging packages (apt-get purge)..."; if ! run_command "apt-get purge --autoremove -y $pkgs" true "APT Purge Nvidia CUDA Aggressive"; then log_msg "ERROR" "apt purge failed."; print_color "$YELLOW" " Attempting fixes..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; print_color "$RED" "Purge failed, even after fixes."; return 1; else print_color "$GREEN" " Package purge complete."; log_msg "INFO" "APT purge done."; fi; fi

    print_color "$CYAN" "\nStep 3: Cleaning configuration & leftover files (Aggressive)...";
    local files_to_remove=(
        "/etc/modprobe.d/blacklist-nvidia*.conf"
        "/etc/modprobe.d/nvidia*.conf"
        "/etc/X11/xorg.conf*"
        "/etc/X11/xorg.conf.d/20-nvidia.conf" # Common location for generated config
        "/lib/udev/rules.d/*nvidia*.rules"
        "/etc/udev/rules.d/*nvidia*.rules"
        "/usr/share/X11/xorg.conf.d/*nvidia*.conf"
        "/usr/lib/nvidia" # Directories where drivers might install files
        "/usr/share/nvidia"
        "/etc/nvidia"     # Nvidia settings/profiles
        # Add more potentially problematic locations if known
    )
    print_color "$YELLOW" "Removing known config/rule/directory patterns:"
    for item in "${files_to_remove[@]}"; do
        # Handle directories, wildcards, and specific files
        if [[ "$item" == */ && -d "$item" ]]; then # Explicit directory check (though rm -rf handles it)
             run_command "rm -rfv $item" false "Remove Dir $item"
        elif [[ "$item" == *\* ]]; then # Pattern matching
             # Use find within the parent directory of the pattern
             local parent_dir; parent_dir=$(dirname "$item")
             local base_pattern; base_pattern=$(basename "$item")
             if [[ -d "$parent_dir" ]]; then
                  run_command "find \"$parent_dir\" -maxdepth 1 -name \"$base_pattern\" -print -delete" false "Remove Pattern $item"
             else
                  log_msg "INFO" "Parent directory $parent_dir for pattern $item not found, skipping."
             fi
        elif [[ -e "$item" || -L "$item" ]]; then # Specific file or symlink
             run_command "rm -vf $item" false "Remove File $item"
        else
             log_msg "INFO" "Item $item not found, skipping."
        fi
    done
    # Extra check for kernel modules that might be left
    print_color "$CYAN" " Searching for leftover Nvidia modules in current kernel dir (/lib/modules/$(uname -r)/)...";
    run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -ls" false "Find Leftover Modules"
    if prompt_confirm "Attempt to delete found leftover modules (Use with caution)?"; then
        run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -delete" false "Delete Leftover Modules"
    fi
    print_color "$GREEN" " Config/Leftover file cleanup attempted."

    print_color "$CYAN" "\nStep 4: Cleaning APT cache & fixing system...";
    run_command "apt-get clean" false "Clean APT Cache";
    run_command "apt-get --fix-broken install -y" true "Fix Broken Install";
    run_command "apt-get autoremove -y" true "Autoremove Orphans";
    run_command "dpkg --configure -a" false "Reconfigure dpkg";
    print_color "$GREEN" " System cleanup/fix steps done."

    print_color "$CYAN" "\nStep 5: Rebuilding initramfs for all kernels..."; if run_command "update-initramfs -u -k all" true "Update Initramfs After Clean"; then print_color "$GREEN" " Initramfs updated."; else log_msg "ERROR" "initramfs rebuild failed!"; fi

    print_color "$GREEN" "\n--- NVIDIA Enhanced Deep Clean Complete ---";
    print_color "$YELLOW" "Reboot strongly recommended before attempting reinstall."; log_msg "INFO" "Enhanced Deep Clean module finished.";
    if [[ -n "$dm" ]]; then if prompt_confirm "Attempt to restart Display Manager ($dm) now (might fail if X configs were removed)?" "N"; then run_command "systemctl start $dm" false "Restart DM after Clean"; fi; fi
    return 0
}
# FINISH ### MODULE NVIDIA CLEANUP ###

# START ### NVIDIA INSTALL FUNCTION ###
run_nvidia_install() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install ---"; log_msg "INFO" "Starting Driver Install.";
    print_color "$CYAN" "Pre-flight checks..."; if ! run_prepare_build_env; then log_msg "ERROR" "Aborting: Build env prep failed."; return 1; fi;
    local sb_stat; sb_stat=$(mokutil --sb-state 2>/dev/null || echo "Unknown"); log_msg "INFO" "Secure Boot: $sb_stat"; print_color "$CYAN" " Secure Boot: $sb_stat"; if [[ "$sb_stat" == "SecureBoot enabled" ]]; then print_color "$RED" " ERROR: Secure Boot ENABLED."; log_msg "ERROR" "Secure Boot enabled."; if ! prompt_confirm "Disable Secure Boot in BIOS/UEFI first? (Y=Exit now / n=Continue - INSTALL WILL LIKELY FAIL)"; then log_msg "WARN" "Continuing with Secure Boot enabled - Expect failure."; else return 1; fi; fi

    local driver_ver=""; local method=""
    # Select method first
    while true; do
        print_color "$YELLOW" "\nSelect install method:";
        echo " 1) APT (Ubuntu Repo - nvidia-driver-XXX)";
        echo " 2) Runfile ($USER_HOME - Offers download for specific versions)";
        echo " 3) APT (Nvidia Repo - cuda-drivers meta-package)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt_ubuntu"; break;;
            2) method="runfile"; break;;
            3) method="apt_nvidia"; break;;
            *) print_color "$RED" "Invalid.";;
        esac;
    done;
    log_msg "USER" "Selected method: $method"

    local status=1;
    if [[ "$method" == "apt_ubuntu" ]]; then
        # Ask for version specifically for this method
        while true; do print_color "$YELLOW" "\nSelect driver version for nvidia-driver-XXX package:"; echo " 1) 535"; echo " 2) 550"; echo " 3) 570"; read -r -p "$(print_color "$YELLOW" "Choice: ")" ver_choice < /dev/tty; case "$ver_choice" in 1) driver_ver="535"; break;; 2) driver_ver="550"; break;; 3) driver_ver="570"; break;; *) print_color "$RED" "Invalid.";; esac; done; log_msg "USER" "Selected driver version for APT Ubuntu: $driver_ver"
        install_nvidia_apt "$driver_ver"; status=$?;
    elif [[ "$method" == "apt_nvidia" ]]; then
        install_nvidia_apt_official_repo; status=$?; # Version is handled by cuda-drivers package
    elif [[ "$method" == "runfile" ]]; then
        install_nvidia_runfile; status=$?; # Runfile selection/download handles version inside
    else
        log_msg "ERROR" "Invalid method stored: $method"; status=1; # Should not happen
    fi

    if [[ $status -eq 0 ]]; then
         print_color "$GREEN" "\n--- Driver Install Complete ---";
         # Update initramfs after successful install is good practice
         if prompt_confirm "Run 'update-initramfs -u -k all' now?" "Y"; then
             run_command "update-initramfs -u -k all" true "Post-Install Initramfs Update"
         fi
         print_color "$YELLOW" "Reboot REQUIRED.";
         print_color "$CYAN" "Verify with 'nvidia-smi' after reboot.";
         log_msg "INFO" "Driver install success.";
    else
         print_color "$RED" "\n--- Driver Install Failed ---";
         log_msg "ERROR" "Driver install failed.";
    fi
    return $status
}
# FINISH ### NVIDIA INSTALL FUNCTION ###

# START ### NVIDIA INSTALL APT UBUNTU ###
install_nvidia_apt() {
    local ver="$1"; local pkg="nvidia-driver-$ver"
    print_color "$CYAN" "\nStarting Standard APT install (Ubuntu Repo): $pkg"; log_msg "INFO" "Starting APT Ubuntu install: $pkg"
    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for APT Ubuntu" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    run_command "apt-get update" false "Update before driver" || print_color "$YELLOW" "Warn: apt update failed."
    print_color "$CYAN" "Installing $pkg...";
    # Use 'apt-get' for better scriptability / consistency with purge
    if run_command "apt-get install $pkg -y" true "Install $pkg"; then # Log full output to separate file
        log_msg "INFO" "APT install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        # Check for the specific version installed via DKMS
        if echo "$dkms_out" | grep -q "nvidia/${ver}"; then print_color "$GREEN" "DKMS built ok for $ver."; log_msg "INFO" "DKMS PASSED for nvidia/${ver}."; return 0;
        # Fallback check in case version string has minor diffs (e.g. 535.183.01)
        elif echo "$dkms_out" | grep -q "nvidia/" | grep -q "${ver}\."; then print_color "$GREEN" "DKMS built ok (found ${ver}.x)."; log_msg "INFO" "DKMS PASSED (found nvidia/${ver}.x)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found for $ver!"; log_msg "ERROR" "DKMS FAILED for $ver."; print_color "$YELLOW" "Check logs (Option 11 -> 2)."; return 1; fi
    else log_msg "ERROR" "apt-get install $pkg failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi
}
# FINISH ### NVIDIA INSTALL APT UBUNTU ###

# START ### NVIDIA INSTALL APT NVIDIA REPO ###
# Installs driver using cuda-drivers from Nvidia repo, also sets up repo if needed.
install_nvidia_apt_official_repo() {
    # No version argument needed here.
    local setup_only="${1:-false}" # Optional arg to only setup repo without install

    if [[ "$setup_only" == true ]]; then
        print_color "$CYAN" "\nEnsuring Nvidia Repo is configured (Setup Only)..."; log_msg "INFO" "Starting Nvidia Repo setup check/config.";
    else
        print_color "$CYAN" "\nStarting Nvidia Repo APT install (using 'cuda-drivers')..."; log_msg "INFO" "Starting Nvidia Repo APT install.";
        if ! check_tty; then return 1; fi
        local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Nvidia Repo" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    fi

    print_color "$CYAN" "Checking/Installing prerequisite tools (wget, gnupg)...";
    run_command "apt-get update" false "Pre-update for repo tools" || print_color "$YELLOW" "Warn: apt update failed.";
    run_command "apt-get install -y software-properties-common gnupg wget" true "Install common tools" || { log_msg "ERROR" "Failed to install prerequisite tools"; return 1; }

    print_color "$CYAN" "Checking/Installing Nvidia repo keyring...";
    local os_codename; os_codename=$(lsb_release -cs);
    if [[ -z "$os_codename" ]]; then print_color "$RED" "Cannot determine OS codename."; log_msg "ERROR" "Cannot get OS codename."; return 1; fi
    local repo_base_url="https://developer.download.nvidia.com/compute/cuda/repos"
    local keyring_url="${repo_base_url}/${os_codename}/x86_64/cuda-keyring_1.1-1_all.deb"
    local keyring_installed=false
    if dpkg-query -W -f='${Status}' cuda-keyring 2>/dev/null | grep -q "ok installed"; then
        log_msg "INFO" "cuda-keyring already installed."; keyring_installed=true;
    else
        print_color "$YELLOW" "'cuda-keyring' not found. Attempting download and install...";
        if ! run_command "wget $keyring_url -O /tmp/cuda-keyring.deb" false "Download Keyring"; then log_msg "ERROR" "Keyring download failed."; return 1; fi
        if ! run_command "dpkg -i /tmp/cuda-keyring.deb" true "Install Keyring"; then log_msg "ERROR" "Keyring install failed."; rm -f /tmp/cuda-keyring.deb; return 1; fi
        rm -f /tmp/cuda-keyring.deb; log_msg "INFO" "cuda-keyring installed."; keyring_installed=true;
    fi
    if [[ "$keyring_installed" != true ]]; then print_color "$RED" "Failed to ensure cuda-keyring is installed."; return 1; fi

    print_color "$CYAN" "Checking/Adding Nvidia CUDA repository file...";
    local repo_file="/etc/apt/sources.list.d/cuda-${os_codename}-x86_64.list"
    local repo_line="deb ${repo_base_url}/${os_codename}/x86_64/ /"
    local repo_changed=false
    if [[ ! -f "$repo_file" ]]; then
         print_color "$CYAN" "Adding Nvidia CUDA repository file: $repo_file...";
         if run_command "echo \"$repo_line\" | tee \"$repo_file\" > /dev/null" false "Create Repo File"; then
             log_msg "INFO" "Nvidia CUDA repository file created."; repo_changed=true;
         else
             log_msg "ERROR" "Failed to create CUDA repository file: $repo_file."; return 1;
         fi
    else
        log_msg "INFO" "Nvidia CUDA repository file already exists: $repo_file"
        # Optional: Check content? Add if repo_line is missing?
        if ! grep -qxF "$repo_line" "$repo_file"; then
            print_color "$YELLOW" "Repo file exists but content might differ. Ensuring line is present..."
            # Check if line exists commented out, if so, uncomment? Or just append? Append is safest.
            if ! grep -qF "$repo_line" "$repo_file"; then
                 if run_command "echo \"$repo_line\" | tee -a \"$repo_file\" > /dev/null" false "Append Repo Line"; then
                     log_msg "INFO" "Appended Nvidia repo line to $repo_file"; repo_changed=true;
                 else
                      log_msg "ERROR" "Failed to append repo line to $repo_file"; return 1;
                 fi
            fi
        fi
    fi

    # Only run apt update if repo was added/changed or if installing
    if [[ "$repo_changed" == true || "$setup_only" == false ]]; then
        print_color "$CYAN" "Updating APT cache after repo configuration...";
        run_command "apt-get update" false "Update after repo setup" || print_color "$YELLOW" "Warn: apt update failed."
    fi

    if [[ "$setup_only" == true ]]; then
        print_color "$GREEN" "Nvidia repository setup complete."; return 0;
    fi

    # Proceed with driver install if not setup_only
    print_color "$CYAN" "Installing 'cuda-drivers' meta-package from Nvidia repo..."; log_msg "EXEC" "apt-get install cuda-drivers -y"
    if run_command "apt-get install cuda-drivers -y" true "Install cuda-drivers"; then
        log_msg "INFO" "APT cuda-drivers install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        if echo "$dkms_out" | grep -q "nvidia/"; then print_color "$GREEN" "DKMS module seems built."; log_msg "INFO" "DKMS check PASSED (found nvidia module)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found after cuda-drivers install!"; log_msg "ERROR" "DKMS check FAILED (no nvidia module found)."; return 1; fi
    else
        log_msg "ERROR" "apt-get install cuda-drivers failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1;
    fi
}
# FINISH ### NVIDIA INSTALL APT NVIDIA REPO ###

# START ### NVIDIA INSTALL RUNFILE ###
install_nvidia_runfile() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install via Runfile ---"; log_msg "INFO" "Starting Runfile Install Module.";

    # Check for wget
    if ! command -v wget &> /dev/null; then
        print_color "$YELLOW" "wget command not found, needed for downloads.";
        if prompt_confirm "Attempt to install wget (apt install wget)?"; then
            if ! run_command "apt-get update && apt-get install -y wget" true "Install wget"; then
                log_msg "ERROR" "Failed to install wget. Download unavailable."; return 1;
            fi
        else
            log_msg "WARN" "wget not installed. Download option disabled.";
            print_color "$RED" "Exiting runfile install as download might be required."; return 1;
        fi
    fi

    # --- Define known runfiles and URLs ---
    local runfile_535_name="NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_535_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/535.154.05/NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_570_name="NVIDIA-Linux-x86_64-570.133.07.run"
    local runfile_570_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/570.133.07/NVIDIA-Linux-x86_64-570.133.07.run"

    local runfile_path=""; local chosen_rn="";

    while [[ -z "$runfile_path" ]]; do
        print_color "$YELLOW" "\nSelect Runfile source:";
        echo " 1) Use $runfile_535_name (Check $USER_HOME, download if missing)";
        echo " 2) Use $runfile_570_name (Check $USER_HOME, download if missing)";
        echo " 3) Search $USER_HOME for other NVIDIA-*.run files";
        echo " 4) Cancel";
        read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;

        case "$choice" in
            1) # Specific 535
               chosen_rn="$runfile_535_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       # Use run_command to log wget output
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_535_url\"" true "Download $chosen_rn"; then
                            # Set ownership to user after download
                            run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                            print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                            log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                    print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 1
            2) # Specific 570
               chosen_rn="$runfile_570_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_570_url\"" true "Download $chosen_rn"; then
                           run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                           print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                           log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                   print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 2
            3) # Manual Search
               local runfile_opts=(); declare -A runfile_map; local count=1;
               print_color "$CYAN" "\nSearching driver .run files in $USER_HOME..."; log_msg "INFO" "Searching runfiles in $USER_HOME."
               # Use find directly, handle potential errors
               local find_output; find_output=$(find "$USER_HOME" -maxdepth 1 -name 'NVIDIA-Linux-x86_64-*.run' -print0 2>/dev/null)
               if [[ -z "$find_output" ]]; then
                    print_color "$RED" "No driver .run files found in $USER_HOME search."; log_msg "WARN" "No other driver runfiles found in search.";
                    runfile_path=""; # Stay in loop
               else
                   while IFS= read -r -d $'\0' f; do
                       local bn; bn=$(basename "$f");
                       # Exclude CUDA runfiles from this list
                       if [[ "$bn" != "cuda_"* ]]; then
                           runfile_opts+=("$bn"); runfile_map[$count]="$bn"; ((count++));
                       fi;
                   done <<< "$find_output" # Process the find output

                   if [[ ${#runfile_opts[@]} -eq 0 ]]; then
                        print_color "$RED" "No non-CUDA driver .run files found in $USER_HOME search."; log_msg "WARN" "No non-CUDA driver runfiles found in search.";
                        runfile_path=""; # Stay in loop
                   else
                       print_color "$YELLOW" "Select driver runfile:";
                       for i in "${!runfile_map[@]}"; do echo " $i) ${runfile_map[$i]}" >&2; done;
                       local search_choice;
                       while [[ -z "$runfile_path" ]]; do
                           read -r -p "$(print_color "$YELLOW" "Choice: ")" search_choice < /dev/tty;
                           if [[ "$search_choice" =~ ^[0-9]+$ && -v "runfile_map[$search_choice]" ]]; then
                               chosen_rn="${runfile_map[$search_choice]}";
                               runfile_path="$USER_HOME/$chosen_rn";
                               log_msg "USER" "Selected Runfile from search: $runfile_path";
                           else
                               print_color "$RED" "Invalid selection from search.";
                           fi;
                       done;
                   fi
               fi
               ;; # End case 3
            4) # Cancel
               log_msg "USER" "Cancelled Runfile install."; return 1;;
            *) # Invalid
               print_color "$RED" "Invalid choice.";;
        esac
    done # End while loop for selecting runfile

    # --- Proceed with installation using selected runfile_path ---
    if [[ -z "$runfile_path" || ! -f "$runfile_path" ]]; then
         print_color "$RED" "ERROR: Invalid or missing runfile selected. Exiting.";
         log_msg "ERROR" "Runfile path invalid or file missing before install: $runfile_path";
         return 1;
    fi

    print_color "$CYAN" "\nStarting Runfile install using: $chosen_rn";
    chmod +x "$runfile_path" || { log_msg "ERROR" "chmod failed on $runfile_path"; return 1; }

    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

    print_color "$YELLOW" "Ensure Build Env (Menu 9 -> 2) & Nouveau blacklist (Menu 5) are done.";
    print_color "$YELLOW" "Also ensure correct GCC is default (Menu 9 -> 3).";
    print_color "$CYAN" "Running installer '$chosen_rn' with --dkms flag (INTERACTIVE)..."
    log_msg "EXEC" "$runfile_path --dkms"

    # Run interactively - run_command cannot handle interactive installers easily
    print_color "$PURPLE" "--- Starting Interactive Installer ---";
    # Ensure installer runs with correct permissions and reads from TTY
    if "$runfile_path" --dkms < /dev/tty ; then
        local run_status=$?; # Capture status immediately
        print_color "$PURPLE" "--- Interactive Installer Finished (Status: $run_status) ---";
        log_msg "INFO" "Runfile '$chosen_rn' finished status: $run_status.";

        if [[ $run_status -eq 0 ]]; then
            print_color "$CYAN" "Verifying DKMS status after successful install..."; log_msg "INFO" "Verifying DKMS after runfile install..."; sleep 2;
            local ver; ver=$(echo "$chosen_rn" | grep -oP '[0-9]+(\.[0-9]+){1,2}' | head -n1);
            local dkms_out; dkms_out=$(dkms status);
            log_msg "INFO" "DKMS Status after install: $dkms_out";
            local major_ver; major_ver=$(echo "$ver" | cut -d. -f1);
            if echo "$dkms_out" | grep -q "nvidia/${major_ver}"; then
                print_color "$GREEN" "DKMS module seems built for version ${major_ver}.x."; log_msg "INFO" "DKMS check PASSED (found nvidia/${major_ver}).";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else
                print_color "$RED" "ERROR: DKMS module for version $ver (or ${major_ver}.x) NOT found after supposedly successful install!";
                log_msg "ERROR" "DKMS check FAILED after runfile install (looking for $ver or ${major_ver}.x).";
                print_color "$YELLOW" "Check 'dkms status' and /var/log/nvidia-installer.log.";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 1; # Return failure even if installer reported 0, because DKMS check failed
            fi
        else
             print_color "$RED" "ERROR: Runfile installer '$chosen_rn' reported failure! Status: $run_status";
             print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
             if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
             return $run_status;
        fi
    else
        local run_status=$?; # Capture status
        print_color "$PURPLE" "--- Interactive Installer Failed to Execute Properly (Status: $run_status) ---";
        log_msg "ERROR" "Runfile installer '$chosen_rn' execution failed. Status: $run_status."; print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
        if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
        return $run_status;
    fi
}
# FINISH ### NVIDIA INSTALL RUNFILE ###

# START ### HELPER INSTALL CUDA TOOLKIT APT CORE ###
# This function assumes Nvidia repo might already be configured.
# It only installs the toolkit package.
install_cuda_toolkit_apt_core() {
    local toolkit_pkg="cuda-toolkit" # Default, could be version specific like cuda-toolkit-12-2 if needed
    print_color "$CYAN" "\nInstalling CUDA Toolkit via APT ($toolkit_pkg)..."; log_msg "INFO" "Starting core CUDA APT install."

    # Ensure repo is configured before proceeding
    # Check if nvidia.com provides the package
    if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
         print_color "$YELLOW" "Nvidia repo doesn't seem to provide '$toolkit_pkg' or isn't configured/updated."
         if prompt_confirm "Attempt to configure Nvidia repo and update APT cache first?"; then
             # Run setup only, capture status
             local repo_setup_status=1
             install_nvidia_apt_official_repo "true"; repo_setup_status=$?
             if [[ $repo_setup_status -ne 0 ]]; then
                 print_color "$RED" "Nvidia repo setup failed. Cannot proceed reliably."; return 1;
             fi
             run_command "apt-get update" false "Update before CUDA core install" || { print_color "$RED" "APT update failed."; return 1; }
             # Re-check policy after update
             if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
                  print_color "$YELLOW" "Warning: Nvidia repo still doesn't seem to provide '$toolkit_pkg' after setup/update.";
                  log_msg "WARN" "Nvidia repo doesn't provide $toolkit_pkg after setup attempt."
                  if ! prompt_confirm "Continue anyway (may install older Ubuntu version)?"; then return 1; fi
             fi
         else
             print_color "$YELLOW" "Proceeding without confirmed Nvidia repo. May install older version from Ubuntu repos.";
             log_msg "WARN" "Proceeding with CUDA toolkit install without confirmed Nvidia repo."
         fi
    else
         log_msg "INFO" "Confirmed $toolkit_pkg available from Nvidia repo."
    fi

    print_color "$CYAN" "Running: apt-get install $toolkit_pkg -y";
    if run_command "apt-get install $toolkit_pkg -y" true "Install CUDA Toolkit APT Core"; then
        log_msg "INFO" "CUDA APT install ($toolkit_pkg) finished."; print_color "$GREEN" "CUDA APT install finished."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
        local nvcc_path; nvcc_path=$(command -v nvcc || echo "/usr/local/cuda/bin/nvcc");
        if [[ -x "$nvcc_path" ]]; then
             local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
        else
             print_color "$YELLOW" "nvcc not found in PATH or default location. Update PATH/LD_LIBRARY_PATH."; log_msg "WARN" "nvcc check FAILED.";
        fi;
        print_color "$YELLOW" "Ensure PATH includes /usr/local/cuda/bin and LD_LIBRARY_PATH includes /usr/local/cuda/lib64 if needed.";
        return 0;
    else
        log_msg "ERROR" "apt-get install $toolkit_pkg failed."; return 1;
    fi
}
# FINISH ### HELPER INSTALL CUDA TOOLKIT APT CORE ###


# START ### MODULE CUDA INSTALL ###
run_cuda_install() {
    print_color "$PURPLE" "\n--- Module: CUDA Toolkit Install ---"; log_msg "INFO" "Starting CUDA Install.";
    # Simplified pre-check
    if ! nvidia-smi &> /dev/null; then
        log_msg "WARN" "nvidia-smi command failed. Is driver installed and running?";
        print_color "$RED" "WARN: nvidia-smi failed. Driver may be inactive.";
        if ! prompt_confirm "Continue CUDA install anyway (NOT Recommended)?"; then return 1; fi;
    else
        print_color "$GREEN" "nvidia-smi check passed."; log_msg "INFO" "nvidia-smi check passed.";
    fi
    local method="";
    local specific_cuda_runfile_name="cuda_12.2.2_535.104.05_linux.run"

    while true; do
        print_color "$YELLOW" "\nSelect CUDA install method:"
        echo "  1) APT ('cuda-toolkit' - Best if Nvidia Repo is configured)";
        echo "  2) Runfile (Check for '$specific_cuda_runfile_name' or search $USER_HOME)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt"; break;;
            2) method="runfile"; break;;
            *) print_color "$RED" "Invalid.";;
        esac
    done;
    log_msg "USER" "Selected CUDA method: $method"

    if [[ "$method" == "apt" ]]; then
        # Call the simplified core install function
        install_cuda_toolkit_apt_core; return $?;

    elif [[ "$method" == "runfile" ]]; then
        # (Keep existing runfile logic from v1.10 - it's already complex and functional)
        local chosen_cuda_runfile_path=""; local chosen_cuda_rn="";
        while [[ -z "$chosen_cuda_runfile_path" ]]; do
            print_color "$YELLOW" "\nSelect CUDA Runfile source:";
            echo " 1) Use $specific_cuda_runfile_name (Check $USER_HOME)";
            echo " 2) Search $USER_HOME for other cuda_*.run files";
            echo " 3) Cancel";
            read -r -p "$(print_color "$YELLOW" "Choice [1-3]: ")" cuda_choice < /dev/tty;
            case "$cuda_choice" in
                1) chosen_cuda_rn="$specific_cuda_runfile_name";
                   if [[ -f "$USER_HOME/$chosen_cuda_rn" ]]; then
                       chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; print_color "$GREEN" "Found locally: $chosen_cuda_runfile_path"; log_msg "INFO" "Found specific CUDA runfile: $chosen_cuda_runfile_path";
                   else print_color "$RED" "Specific file not found: $USER_HOME/$chosen_cuda_rn"; log_msg "WARN" "Specific CUDA runfile missing."; print_color "$YELLOW" "Please download manually or choose search."; fi ;; # Stay in loop
                2) local cuda_runfile_opts=(); declare -A cuda_runfile_map; local ccount=1;
                   print_color "$CYAN" "\nSearching CUDA .run files in $USER_HOME..."; log_msg "INFO" "Searching CUDA runfiles in $USER_HOME."
                   local cuda_find_output; cuda_find_output=$(find "$USER_HOME" -maxdepth 1 -name 'cuda_*_linux.run' -print0 2>/dev/null)
                   if [[ -z "$cuda_find_output" ]]; then print_color "$RED" "No CUDA .run files found in search."; log_msg "WARN" "No CUDA runfiles found in search.";
                   else
                        while IFS= read -r -d $'\0' f; do local bn; bn=$(basename "$f"); cuda_runfile_opts+=("$bn"); cuda_runfile_map[$ccount]="$bn"; ((ccount++)); done <<< "$cuda_find_output"
                       if [[ ${#cuda_runfile_opts[@]} -eq 0 ]]; then print_color "$RED" "Error processing found CUDA files."; log_msg "ERROR" "Processing find results for CUDA failed.";
                       else
                           print_color "$YELLOW" "Select CUDA runfile:";
                           for i in "${!cuda_runfile_map[@]}"; do echo " $i) ${cuda_runfile_map[$i]}" >&2; done;
                           local csearch_choice;
                           while [[ -z "$chosen_cuda_runfile_path" ]]; do
                               read -r -p "$(print_color "$YELLOW" "Choice: ")" csearch_choice < /dev/tty;
                               if [[ "$csearch_choice" =~ ^[0-9]+$ && -v "cuda_runfile_map[$csearch_choice]" ]]; then
                                   chosen_cuda_rn="${cuda_runfile_map[$csearch_choice]}"; chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; log_msg "USER" "Selected CUDA Runfile from search: $chosen_cuda_runfile_path";
                               else print_color "$RED" "Invalid selection."; fi;
                           done;
                        fi
                   fi ;; # End search logic
                3) log_msg "USER" "Cancelled CUDA Runfile install."; return 1;; *) print_color "$RED" "Invalid choice.";;
            esac
        done # End CUDA runfile selection loop

        # --- Proceed with CUDA Runfile Install ---
        if [[ -z "$chosen_cuda_runfile_path" || ! -f "$chosen_cuda_runfile_path" ]]; then print_color "$RED" "ERROR: Invalid CUDA runfile. Exiting."; log_msg "ERROR" "CUDA Runfile path invalid."; return 1; fi

        print_color "$CYAN" "\nInstalling CUDA via Runfile ($chosen_cuda_rn)..."; log_msg "INFO" "Starting CUDA Runfile install: $chosen_cuda_runfile_path"
        chmod +x "$chosen_cuda_runfile_path" || { log_msg "ERROR" "chmod CUDA runfile failed"; return 1; }
        if ! check_tty; then return 1; fi; local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for CUDA runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

        print_color "$YELLOW" "Runfile Install Options (IMPORTANT!)";
        print_color "$YELLOW" " -> Answer 'accept' to EULA.";
        print_color "$RED"    " -> DESELECT the 'Driver' component if you already installed drivers separately.";
        print_color "$YELLOW" " -> Keep 'CUDA Toolkit' selected.";
        log_msg "INFO" "Instructed user on runfile options (deselect driver).";

        print_color "$CYAN" "Running CUDA Runfile '$chosen_cuda_rn' INTERACTIVELY..."; log_msg "EXEC" "$chosen_cuda_runfile_path";
        print_color "$PURPLE" "--- Starting Interactive CUDA Installer ---";
        if "$chosen_cuda_runfile_path" < /dev/tty ; then
            local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Finished (Status: $cuda_run_status) ---"; log_msg "INFO" "CUDA Runfile finished status $cuda_run_status.";
            if [[ $cuda_run_status -eq 0 ]]; then
                print_color "$GREEN" "CUDA Runfile finished successfully."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
                local cuda_base_path="/usr/local"; local latest_cuda_link="$cuda_base_path/cuda"; local nvcc_path="";
                if [[ -L "$latest_cuda_link" ]] && [[ -x "$latest_cuda_link/bin/nvcc" ]]; then nvcc_path="$latest_cuda_link/bin/nvcc";
                else local newest_cuda_dir; newest_cuda_dir=$(find "$cuda_base_path" -maxdepth 1 -name 'cuda-*' -type d -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-); if [[ -n "$newest_cuda_dir" ]] && [[ -x "$newest_cuda_dir/bin/nvcc" ]]; then nvcc_path="$newest_cuda_dir/bin/nvcc"; else nvcc_path="/usr/local/cuda/bin/nvcc"; fi; fi
                if [[ -x "$nvcc_path" ]]; then local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
                else print_color "$YELLOW" "nvcc not found. Update PATH/LD_LIB."; log_msg "WARN" "nvcc FAILED check."; fi;
                print_color "$YELLOW" "Ensure PATH/LD_LIBRARY_PATH are set if needed.";
                 if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else log_msg "ERROR" "CUDA Runfile failed status $cuda_run_status."; print_color "$RED" "CUDA Runfile Failed!"; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return 1; fi
        else local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Failed Execution (Status: $cuda_run_status) ---"; log_msg "ERROR" "CUDA Runfile execution failed. Status: $cuda_run_status."; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return $cuda_run_status; fi
    fi # End method if/elif
}
# FINISH ### MODULE CUDA INSTALL ###

# START ### GRUB CUSTOM BUILDER FUNCTION ###
run_grub_custom_builder() {
    local grub_def="/etc/default/grub"; local current_cmdline=""
    print_color "$PURPLE" "\n--- GRUB Custom Parameter Builder (Experimental) ---"; log_msg "INFO" "Starting GRUB Custom Builder."

    # Read current setting
    if [[ -f "$grub_def" ]]; then
        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_def" | cut -d'=' -f2 | sed 's/"//g')
        print_color "$CYAN" "Current GRUB_CMDLINE_LINUX_DEFAULT: \"$current_cmdline\""
        log_msg "INFO" "Current GRUB CMDLINE: $current_cmdline"
    else
        print_color "$RED" "Cannot read $grub_def!"; log_msg "ERROR" "Cannot read $grub_def in custom builder."; return 1;
    fi

    # Initialize parameters based on current settings or defaults
    local params; params=($current_cmdline) # Convert string to array
    local use_quiet="N"; [[ " ${params[@]} " =~ " quiet " ]] && use_quiet="Y"
    local use_splash="N"; [[ " ${params[@]} " =~ " splash " ]] && use_splash="Y"
    local use_nomodeset="N"; [[ " ${params[@]} " =~ " nomodeset " ]] && use_nomodeset="Y"
    local use_nvidiadrm="N"; [[ " ${params[@]} " =~ " nvidia-drm.modeset=1 " ]] && use_nvidiadrm="Y"
    local custom_params=""

    # Filter out the params we will toggle, keep others
    local other_params=()
    for p in "${params[@]}"; do
        if [[ "$p" != "quiet" && "$p" != "splash" && "$p" != "nomodeset" && "$p" != "nvidia-drm.modeset=1" ]]; then
            other_params+=("$p")
        fi
    done
    custom_params=$(echo "${other_params[@]}") # Join remaining params back into a string

    print_color "$YELLOW" "\nConfigure parameters (Current state shown):"
    prompt_confirm "Include 'quiet' parameter?" "$use_quiet"; [[ $? -eq 0 ]] && use_quiet="Y" || use_quiet="N"
    prompt_confirm "Include 'splash' parameter?" "$use_splash"; [[ $? -eq 0 ]] && use_splash="Y" || use_splash="N"
    prompt_confirm "Include 'nomodeset' parameter? (Disables most KMS drivers)" "$use_nomodeset"; [[ $? -eq 0 ]] && use_nomodeset="Y" || use_nomodeset="N"
    prompt_confirm "Include 'nvidia-drm.modeset=1' parameter? (Recommended for Nvidia)" "$use_nvidiadrm"; [[ $? -eq 0 ]] && use_nvidiadrm="Y" || use_nvidiadrm="N"

    print_color "$YELLOW" "\nCurrent other/custom parameters: $custom_params"
    read -r -p "$(print_color "$YELLOW" "Enter any ADDITIONAL custom parameters (space-separated, or leave blank): ")" additional_params < /dev/tty
    custom_params="$custom_params $additional_params"
    # Clean up potential double spaces and leading/trailing whitespace
    custom_params=$(echo "$custom_params" | tr -s ' ' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Build the new command line
    local new_cmdline_array=()
    [[ "$use_quiet" == "Y" ]] && new_cmdline_array+=("quiet")
    [[ "$use_splash" == "Y" ]] && new_cmdline_array+=("splash")
    [[ "$use_nomodeset" == "Y" ]] && new_cmdline_array+=("nomodeset")
    [[ "$use_nvidiadrm" == "Y" ]] && new_cmdline_array+=("nvidia-drm.modeset=1")
    # Add custom params if not empty
    [[ -n "$custom_params" ]] && new_cmdline_array+=($custom_params) # Add as separate elements

    local new_cmdline; new_cmdline=$(echo "${new_cmdline_array[@]}") # Join with spaces

    print_color "$PURPLE" "\n--- Generated Config Line ---"
    print_color "$CYAN" "GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\""
    log_msg "INFO" "Custom GRUB CMDLINE generated: $new_cmdline"
    print_color "$PURPLE" "---------------------------"

    if ! prompt_confirm "Apply this custom config line to $grub_def?"; then
        log_msg "USER" "Cancelled custom GRUB apply."; return 1
    fi

    # Apply the changes
    local grub_bak="/etc/default/grub.custom_backup.$(date +%s)"
    print_color "$YELLOW" "Backing up current config to $grub_bak..."
    if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Custom"; then
        log_msg "ERROR" "Custom GRUB backup failed."; return 1
    fi

    print_color "$CYAN" "Applying custom config line using sed...";
    local escaped_cmdline; escaped_cmdline=$(sed 's/[&/\]/\\&/g' <<< "$new_cmdline") # Basic escaping for sed
    if run_command "sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$escaped_cmdline\"|' \"$grub_def\"" false "Apply Custom Grub Line"; then
        log_msg "INFO" "Applied custom GRUB config line ok.";
        print_color "$CYAN" "Running update-grub...";
        if run_command "update-grub" true "update-grub after custom config"; then
            print_color "$GREEN" "Custom GRUB config applied and updated."; log_msg "INFO" "Custom GRUB updated ok."; return 0;
        else
            log_msg "ERROR" "update-grub failed after custom config."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1;
        fi
    else
        log_msg "ERROR" "Failed to apply custom config line using sed."; return 1
    fi
}
# FINISH ### GRUB CUSTOM BUILDER FUNCTION ###

# START ### GRUB FIX FUNCTION ###
run_grub_fix() {
    print_color "$PURPLE" "\n--- Module: GRUB Configuration Fix ---"; log_msg "INFO" "Starting GRUB Fix."
    local grub_def="/etc/default/grub"; local grub_bak="/etc/default/grub.preset_backup.$(date +%s)"; local cfg=""; local cfg_name="";
    print_color "$YELLOW" "Select GRUB action:";
    echo " 1) Apply Standard Default (quiet splash)";
    echo " 2) Apply Verbose Boot (no quiet splash)";
    echo " 3) Apply Failsafe (nomodeset)";
    echo " 4) Apply Std + Nvidia DRM Modeset (quiet splash nvidia-drm.modeset=1)";
    echo " 5) Apply Verbose + Nvidia DRM Modeset (nvidia-drm.modeset=1)";
    echo " 6) Custom Parameter Builder (Experimental)";
    echo " 7) Reinstall GRUB (EFI)";
    echo " 8) Cancel";
    read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty;
    case "$choice" in
        1) cfg_name="Standard"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Standard
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
# Add other GRUB settings below if needed, ensuring they don't conflict
GRUBEOF
) ;; # END Standard Preset
        2) cfg_name="Verbose"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose Preset
        3) cfg_name="Failsafe (nomodeset)"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Failsafe
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Failsafe Preset
        4) cfg_name="Std + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Std+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUBEOF
) ;; # END Std+DRM Preset
        5) cfg_name="Verbose + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose+DRM Preset
        6) run_grub_custom_builder; return $? ;; # Call Custom Builder
        7) print_color "$CYAN" "Selected: Reinstall GRUB (EFI)."; log_msg "USER" "Selected GRUB Reinstall."
           if ! mount | grep -q /boot/efi; then
                print_color "$YELLOW" "Warning: /boot/efi does not seem to be mounted."
                if ! prompt_confirm "Attempt to mount EFI partition and continue? (Requires knowing EFI partition)"; then return 1; fi
                 efi_part=$(findmnt -n -o SOURCE --target /boot/efi || lsblk -o NAME,PARTLABEL | grep -i EFI | awk '{print "/dev/"$1}' | head -n1)
                 if [[ -z "$efi_part" ]]; then print_color "$RED" "Could not determine EFI partition automatically."; return 1; fi
                 if ! run_command "mount $efi_part /boot/efi" true "Mount EFI"; then print_color "$RED" "Failed to mount EFI partition."; return 1; fi
           fi
           if prompt_confirm "Run 'grub-install --recheck' (Assumes /boot/efi is correctly mounted)?"; then
               if run_command "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck" true "grub-install"; then
                   log_msg "INFO" "grub-install ok."; print_color "$CYAN" "Running update-grub...";
                   if run_command "update-grub" true "update-grub"; then log_msg "INFO" "update-grub ok."; return 0; else log_msg "ERROR" "update-grub failed."; return 1; fi
               else log_msg "ERROR" "grub-install failed."; return 1; fi
           else log_msg "USER" "Cancelled GRUB reinstall."; return 1; fi ;; # END GRUB Reinstall
        8) print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled GRUB fix."; return 1 ;; # END Cancel
        *) print_color "$RED" "Invalid."; return 1 ;;
    esac
    # Logic to apply the selected preset (if cfg is set)
    if [[ -n "$cfg" ]]; then
        print_color "$CYAN" "\nSelected Config Preset: $cfg_name"; print_color "$PURPLE" "--- Config ---"; print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$cfg"; print_color "$PURPLE" "--------------"; log_msg "INFO" "Applying GRUB preset: $cfg_name"
        if prompt_confirm "Apply this preset to $grub_def (OVERWRITES ENTIRE FILE)?"; then
            print_color "$YELLOW" "Backing up $grub_def to $grub_bak..."; if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Preset"; then log_msg "ERROR" "Backup failed."; return 1; fi
            print_color "$CYAN" "Writing preset config...";
            # Overwrite the file with the heredoc content
            if echo "$cfg" | sudo tee "$grub_def" > /dev/null; then # Ensure using sudo for tee
                 sudo chown root:root "$grub_def" && sudo chmod 644 "$grub_def"
                log_msg "INFO" "Wrote preset config ok."; print_color "$CYAN" "Running update-grub...";
                if run_command "update-grub" true "update-grub after preset"; then print_color "$GREEN" "GRUB updated successfully."; log_msg "INFO" "GRUB updated ok."; return 0;
                else log_msg "ERROR" "update-grub failed."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1; fi
            else log_msg "ERROR" "Write preset config failed."; return 1; fi
        else log_msg "USER" "Cancelled GRUB preset apply."; return 1; fi
    fi;
    return 0; # Should only be reached if choice was handled (e.g. custom builder)
}
# FINISH ### GRUB FIX FUNCTION ###

# START ### MODULE KERNEL FIX ###
run_kernel_fix() {
    print_color "$PURPLE" "\n--- Module: Kernel Reset ---"; log_msg "INFO" "Starting Kernel Reset."
    print_color "$YELLOW" "Removes & reinstalls a specific kernel version. USE CAUTION.";
    print_color "$YELLOW" "Ensure you are booted into a DIFFERENT, WORKING kernel.";
    local current_k; current_k=$(uname -r); log_msg "INFO" "Current kernel: $current_k"; print_color "$CYAN" "Currently running kernel: $current_k"

    print_color "$CYAN" "\nIdentifying installed kernel images..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
    # Get kernel versions from image packages
     while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1; fi

    print_color "$YELLOW" "\nSelect kernel version to reset:"
    for i in "${!kernel_map[@]}"; do
        local status_flag=""
        [[ "${kernel_map[$i]}" == "$current_k" ]] && status_flag=" (Currently Running - Cannot Reset)"
        echo " $i) ${kernel_map[$i]}$status_flag" >&2
    done
    echo " $((count))) Cancel" >&2

    local choice; local kernel_to_fix=""
    while [[ -z "$kernel_to_fix" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                if [[ "${kernel_map[$choice]}" == "$current_k" ]]; then
                     print_color "$RED" "Cannot reset the currently running kernel ($current_k)."; log_msg "WARN" "Attempted to reset running kernel.";
                else
                     kernel_to_fix="${kernel_map[$choice]}"
                fi
            elif [[ "$choice" -eq "$count" ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled kernel reset selection."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected kernel to reset: $kernel_to_fix"
    print_color "$RED" "\nWARNING: This will PURGE packages for kernel $kernel_to_fix"
    print_color "$RED" "         (image, headers, modules, modules-extra)"
    print_color "$RED" "         and then attempt to REINSTALL them."
    if ! prompt_confirm "Are you absolutely sure? You are booted from $current_k."; then log_msg "USER" "Cancelled kernel reset confirmation."; return 1; fi

    print_color "$CYAN" "\nStep 1: Purging packages for kernel $kernel_to_fix...";
    local purge_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix} linux-modules-${kernel_to_fix} linux-modules-extra-${kernel_to_fix}"
    if run_command "apt-get purge --autoremove -y $purge_pkgs" true "Purge Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix purged ok."; else log_msg "ERROR" "Kernel purge failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi

    print_color "$CYAN" "\nStep 2: Updating GRUB after purge..."; run_command "update-grub" true "Update GRUB after purge" || log_msg "ERROR" "update-grub failed after purge."

    print_color "$CYAN" "\nStep 3: Reinstalling kernel $kernel_to_fix packages...";
    local install_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix}"
    # Determine if HWE meta-package should be reinstalled (simple check)
    local install_cmd="apt-get update && apt-get install -y $install_pkgs"
    if [[ "$kernel_to_fix" == *-hwe-* ]]; then
        local os_release; os_release=$(lsb_release -sr) # Get release number e.g., 22.04
        if [[ -n "$os_release" ]]; then
            local hwe_pkg="linux-generic-hwe-${os_release}"
            print_color "$CYAN" "Attempting to reinstall HWE meta-package ($hwe_pkg) as well..."
            install_cmd+=" && apt-get install -y $hwe_pkg"
        else
             print_color "$YELLOW" "Could not determine OS release for HWE package."
        fi
    fi
    if run_command "$install_cmd" true "Reinstall Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix reinstall ok."; else log_msg "ERROR" "Kernel reinstall failed."; return 1; fi

    print_color "$GREEN" "\n--- Kernel Reset Complete for $kernel_to_fix ---";
    print_color "$YELLOW" "Reboot required to boot into the reinstalled kernel."; log_msg "INFO" "Kernel Reset finished."; return 0
}
# FINISH ### MODULE KERNEL FIX ###

# START ### MODULE CHROOT HELPER ###
run_chroot_helper() {
    print_color "$PURPLE" "\n--- Module: Chroot Helper (For booting from Live USB/ISO) ---"; log_msg "INFO" "Starting Chroot Helper.";
    print_color "$YELLOW" "This helps mount your installed system and chroot into it.";
    print_color "$YELLOW" "USE THIS ONLY WHEN BOOTED FROM A LIVE ENVIRONMENT.";

    # Basic check for live environment
    if mountpoint -q /cdrom || grep -q -E 'casper|toram|live' /proc/cmdline; then log_msg "INFO" "Live environment detected."; else print_color "$RED" "Warning: Doesn't look like a standard Live environment."; log_msg "WARN" "Not Live OS?"; if ! prompt_confirm "Are you sure you are booted from a Live USB/ISO?"; then return 1; fi; fi

    local root_part=""; local efi_part=""; local swap_part=""; local mount_p="/mnt/mybitch_chroot"; local binds=( "/dev" "/dev/pts" "/proc" "/sys" "/run" )
    print_color "$CYAN" "\nIdentifying partitions (lsblk)..."; lsblk -f >&2;
    print_color "$YELLOW" "\nEnter the device paths for your installed system:"
    while true; do read -r -p "$(print_color "$YELLOW" " -> ROOT partition (e.g., /dev/nvme0n1p2 or /dev/sda3): ")" root_part < /dev/tty; if [[ -b "$root_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    while true; do read -r -p "$(print_color "$YELLOW" " -> EFI partition (e.g., /dev/nvme0n1p1 or /dev/sda1): ")" efi_part < /dev/tty; if [[ -b "$efi_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    read -r -p "$(print_color "$YELLOW" " -> SWAP partition (optional, e.g., /dev/sda2 or blank): ")" swap_part < /dev/tty; if [[ -n "$swap_part" && ! -b "$swap_part" ]]; then print_color "$RED" "Invalid block device for swap, ignoring."; swap_part=""; fi

    log_msg "USER" "Chroot Target - Root: $root_part, EFI: $efi_part, Swap: ${swap_part:-none}."

    print_color "$CYAN" "\nUnmounting previous attempts at $mount_p..."; umount -R "$mount_p" &>/dev/null; sleep 1; rm -rf "$mount_p"; # Clean up dir too
    print_color "$CYAN" "Mounting target system..."
    mkdir -p "$mount_p" || { log_msg "ERROR" "mkdir $mount_p fail"; return 1; }
    mount "$root_part" "$mount_p" || { log_msg "ERROR" "mount root $root_part fail"; rm -rf "$mount_p"; return 1; };
    mkdir -p "$mount_p/boot/efi" || { log_msg "ERROR" "mkdir $mount_p/boot/efi fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    mount "$efi_part" "$mount_p/boot/efi" || { log_msg "ERROR" "mount efi $efi_part fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    if [[ -n "$swap_part" ]]; then
         print_color "$CYAN" "Activating swap partition $swap_part...";
         run_command "swapon $swap_part" false "Activate Swap" || print_color "$YELLOW" "Warning: Failed to activate swap.";
    fi

    print_color "$CYAN" "Binding system directories for chroot..."; local bind_f=0;
    for p in "${binds[@]}"; do
        # Ensure target directory exists within the mount point
        mkdir -p "$mount_p$p";
        if ! mount --bind "$p" "$mount_p$p"; then log_msg "ERROR" "Bind $p fail"; bind_f=1; print_color "$RED" " ERROR: Bind $p fail!"; fi;
    done;

    if [[ $bind_f -eq 1 ]]; then print_color "$YELLOW" "One or more binds failed. Chroot environment may be incomplete."; else print_color "$GREEN" "System binds successful."; fi

    print_color "$CYAN" "Copying DNS info (/etc/resolv.conf)...";
    # Handle cases where resolv.conf might be a broken symlink in the chroot target
    if [[ -L "$mount_p/etc/resolv.conf" ]]; then
        run_command "rm \"$mount_p/etc/resolv.conf\"" false "Remove resolv.conf symlink"
    fi
    if cp --dereference /etc/resolv.conf "$mount_p/etc/resolv.conf"; then print_color "$GREEN" "DNS info copied."; else log_msg "WARN" "DNS copy failed."; print_color "$YELLOW" "Warning: Failed to copy DNS info."; fi

    print_color "$GREEN" "\nTarget system mounted successfully at $mount_p.";
    print_color "$YELLOW" "Entering chroot environment. Type 'exit' or press Ctrl+D when finished.";
    print_color "$CYAN" "Inside chroot, you can run commands like 'apt update', 'update-grub', etc.";
    read -r -p "$(print_color "$YELLOW" "Press Enter to enter chroot...")" < /dev/tty

    log_msg "EXEC" "chroot $mount_p /bin/bash";
    # Use a more complete chroot environment setup
    chroot "$mount_p" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(chroot) \u@\h:\w\$ ' PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash --login +h
    local chroot_st=$?; log_msg "INFO" "Exited chroot status $chroot_st."

    print_color "$PURPLE" "\n--- Exited Chroot Environment ---";
    print_color "$YELLOW" "IMPORTANT: Filesystem is still mounted!";
    print_color "$YELLOW" "Unmount manually when finished using commands like:";
    print_color "$CYAN" "   sudo umount -R \"$mount_p\"";
    print_color "$YELLOW" "(If recursive unmount fails, unmount binds individually then base mounts)";
    print_color "$CYAN" "   (e.g., sudo umount \"$mount_p/dev/pts\" \"$mount_p/dev\" ...etc... )"
    print_color "$CYAN" "   (then sudo umount \"$mount_p/boot/efi\" \"$mount_p\" )"
    if [[ -n "$swap_part" ]]; then print_color "$CYAN" "   sudo swapoff $swap_part"; fi
    return 0
}
# FINISH ### MODULE CHROOT HELPER ###

# START ### MODULE VIEW LOGS ###
run_view_logs() {
    print_color "$PURPLE" "\n--- Module: Log Viewer ---"; log_msg "INFO" "Starting Log Viewer."
    while true; do
        # Clear screen for better readability
        if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
        print_color "$GREEN" "\nSelect log file or command to view:"
        echo " 1) Nvidia/CUDA Installer Log (/var/log/nvidia-installer.log or /var/log/cuda-installer.log)";
        echo " 2) DKMS Build Logs (Latest Nvidia Build)";
        echo " 3) APT History Log (/var/log/apt/history.log)";
        echo " 4) APT Terminal Log (/var/log/apt/term.log)";
        echo " 5) Xorg Log (/var/log/Xorg.0.log)";
        echo " 6) Xorg Log (Previous) (/var/log/Xorg.0.log.old)";
        echo " 7) Journalctl: Current Boot Errors (-b 0 -p err)";
        echo " 8) Journalctl: Previous Boot Errors (-b -1 -p err)";
        echo " 9) Journalctl: Kernel Messages (-k)";
        echo "10) This Script's Main Log ($MAIN_LOG_FILE)";
        echo "11) Back to Main Menu";
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-11]: ")" choice < /dev/tty

        case "$choice" in
            1) if [[ -f /var/log/cuda-installer.log ]]; then view_log_file "/var/log/cuda-installer.log" "CUDA Installer"; elif [[ -f /var/log/nvidia-installer.log ]]; then view_log_file "/var/log/nvidia-installer.log" "Nvidia Installer"; else print_color "$YELLOW" "No Nvidia/CUDA installer log found in /var/log."; log_msg "WARN" "No Nvidia/CUDA installer log found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty; fi ;;
            2) local latest_dkms; local k_v; k_v=$(uname -r);
               print_color "$CYAN" "Searching for latest Nvidia DKMS build log..."
               # Find the most recently modified make.log within any nvidia/*/KERNEL/ structure
               latest_dkms=$(find /var/lib/dkms/nvidia/ -name "make.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
               if [[ -n "$latest_dkms" ]]; then
                    view_log_file "$latest_dkms" "Latest DKMS Build ($(basename "$(dirname "$(dirname "$latest_dkms")")"))";
               else
                    print_color "$YELLOW" "No Nvidia DKMS make.log files found."; log_msg "WARN" "No Nvidia DKMS logs found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty;
               fi ;;
            3) view_log_file "/var/log/apt/history.log" "APT History";;
            4) view_log_file "/var/log/apt/term.log" "APT Terminal";;
            5) view_log_file "/var/log/Xorg.0.log" "Current Xorg Log";;
            6) view_log_file "/var/log/Xorg.0.log.old" "Previous Xorg Log";;
            7) print_color "$CYAN" "Showing current boot errors (journalctl -b 0 -p err)..."; journalctl --no-pager -b 0 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            8) print_color "$CYAN" "Showing previous boot errors (journalctl -b -1 -p err)..."; journalctl --no-pager -b -1 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            9) print_color "$CYAN" "Showing kernel messages for current boot (journalctl -k)..."; journalctl --no-pager -k < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
           10) view_log_file "$MAIN_LOG_FILE" "This Script Log";;
           11) log_msg "INFO" "Exiting Log Viewer."; break;;
            *) print_color "$RED" "Invalid selection." ;;
        esac;
        # No automatic pause needed here as view_log_file pauses, and journalctl commands have manual pause
    done; return 0;
}
# FINISH ### MODULE VIEW LOGS ###

# START ### UPDATE INITRAMFS FUNCTION ###
run_update_initramfs() {
    print_color "$PURPLE" "\n--- Module: Update Initramfs ---"; log_msg "INFO" "Starting Update Initramfs."
    print_color "$CYAN" "Identifying installed kernel versions..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;

    # Find installed kernel images and populate map
    while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then # Ensure k_ver is not empty
             kernels+=("$k_ver")
             kernel_map[$count]="$k_ver"
             ((count++))
        fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then
        print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1;
    fi

    print_color "$YELLOW" "Select kernel to update initramfs for:"
    for i in "${!kernel_map[@]}"; do
        echo " $i) ${kernel_map[$i]}" >&2
    done
    echo " $((count))) all (Update all installed kernels)" >&2
    echo " $((count+1))) Cancel" >&2

    local choice; local target_k=""
    while [[ -z "$target_k" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                target_k="${kernel_map[$choice]}"
            elif [[ "$choice" -eq "$count" ]]; then
                target_k="all"
            elif [[ "$choice" -eq $((count+1)) ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled initramfs update."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected initramfs update target: $target_k"
    print_color "$CYAN" "Running update-initramfs -u for kernel(s): $target_k...";

    if run_command "update-initramfs -u -k $target_k" true "Update Initramfs $target_k"; then
        print_color "$GREEN" "Initramfs update successful for $target_k."; log_msg "INFO" "Initramfs update ok: $target_k."
        return 0
    else
        print_color "$RED" "Initramfs update failed for $target_k."; log_msg "ERROR" "Initramfs update FAILED: $target_k.";
        return 1
    fi
}
# FINISH ### UPDATE INITRAMFS FUNCTION ###

# START ### NETWORK FIX FUNCTION ###
run_network_fix() {
    print_color "$PURPLE" "\n--- Module: Network Troubleshooting ---"; log_msg "INFO" "Starting Network Fix Module."
    print_color "$YELLOW" "This attempts common fixes for network issues, especially in CLI."

    while true; do
        print_color "$GREEN" "\nNetwork Troubleshooting Options:"
        echo " 1) Check NetworkManager Status"
        echo " 2) Restart NetworkManager Service"
        echo " 3) Show Network Devices (ip link/addr)"
        echo " 4) Show Recent Network Kernel Logs (dmesg/journalctl)"
        echo " 5) Apply Netplan Configuration"
        echo " 6) Check DNS Configuration (/etc/resolv.conf & systemd-resolved)"
        echo " 7) Check/Reinstall linux-firmware package"
        echo " 8) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty

        case "$choice" in
            1) print_color "$CYAN" "Checking NetworkManager status...";
               run_command "systemctl status NetworkManager.service --no-pager" false "NetworkManager Status";; # Added --no-pager
            2) print_color "$CYAN" "Attempting to restart NetworkManager...";
               if run_command "systemctl restart NetworkManager.service" false "Restart NetworkManager"; then
                   print_color "$GREEN" "NetworkManager restarted. Check status (Option 1) or test connection (e.g., ping 8.8.8.8).";
               else
                   print_color "$RED" "Failed to restart NetworkManager.";
               fi ;;
            3) print_color "$CYAN" "Showing network links (ip link show)...";
               run_command "ip link show" false "Show IP Links";
               print_color "$CYAN" "\nShowing network addresses (ip addr show)...";
               run_command "ip addr show" false "Show IP Addresses";;
            4) print_color "$CYAN" "Showing recent kernel messages related to network/firmware (last 50 lines)...";
               if command -v journalctl &> /dev/null; then
                    print_color "$CYAN" "(Using journalctl -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    journalctl --no-pager -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via journalctl."
               else
                    print_color "$CYAN" "(Using dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via dmesg."
               fi
               ;;
            5) if command -v netplan &> /dev/null; then
                   print_color "$CYAN" "Attempting to apply Netplan configuration (sudo netplan apply)...";
                   if run_command "netplan apply" true "Apply Netplan"; then # Log output in case of errors
                       print_color "$GREEN" "Netplan configuration applied. Check network status.";
                   else
                       print_color "$RED" "Failed to apply Netplan configuration. Check output/logs.";
                   fi
               else
                   print_color "$YELLOW" "netplan command not found. This system likely doesn't use Netplan. Skipping.";
                   log_msg "WARN" "netplan command not found.";
               fi ;;
            6) print_color "$CYAN" "Checking DNS settings (/etc/resolv.conf)...";
               if [[ -f "/etc/resolv.conf" ]]; then
                   run_command "cat /etc/resolv.conf" false "Show resolv.conf";
                   if [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink -f /etc/resolv.conf)" == */systemd/resolve/stub-resolv.conf ]]; then
                        print_color "$CYAN" "DNS appears managed by systemd-resolved. Checking service status...";
                        run_command "systemctl status systemd-resolved.service --no-pager" false "systemd-resolved status";
                   elif [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink /etc/resolv.conf)" == *run/NetworkManager/resolv.conf* ]]; then
                         print_color "$CYAN" "DNS appears managed by NetworkManager directly (using resolvconf?).";
                         print_color "$CYAN" "Check NetworkManager status (Option 1) and logs.";
                   elif [[ -L "/etc/resolv.conf" ]]; then
                        print_color "$CYAN" "DNS is a symlink to: $(readlink /etc/resolv.conf)";
                   else
                         print_color "$CYAN" "/etc/resolv.conf is a static file.";
                   fi
               else
                   print_color "$YELLOW" "/etc/resolv.conf not found.";
                   log_msg "WARN" "/etc/resolv.conf not found";
               fi ;;
            7) print_color "$CYAN" "Checking 'linux-firmware' package...";
                if dpkg-query -W -f='${Status}' linux-firmware 2>/dev/null | grep -q "ok installed"; then
                     print_color "$GREEN" "'linux-firmware' package is installed.";
                     log_msg "INFO" "linux-firmware package installed.";
                     if prompt_confirm "Reinstall 'linux-firmware' anyway (can take a while)?"; then
                        if run_command "apt-get update && apt-get install --reinstall -y linux-firmware" true "Reinstall linux-firmware"; then
                             print_color "$GREEN" "Reinstalled linux-firmware. A reboot might be needed."; log_msg "INFO" "Reinstalled linux-firmware.";
                        else
                             print_color "$RED" "Failed to reinstall linux-firmware."; log_msg "ERROR" "Failed reinstall linux-firmware";
                        fi
                     fi
                else
                     print_color "$YELLOW" "'linux-firmware' package NOT installed. This could cause hardware issues.";
                     log_msg "WARN" "linux-firmware package not installed.";
                      if prompt_confirm "Install 'linux-firmware' package (required for many devices)?"; then
                        if run_command "apt-get update && apt-get install -y linux-firmware" true "Install linux-firmware"; then
                             print_color "$GREEN" "Installed linux-firmware."; log_msg "INFO" "Installed linux-firmware.";
                             print_color "$YELLOW" "A reboot might be needed for firmware changes.";
                        else
                             print_color "$RED" "Failed to install linux-firmware."; log_msg "ERROR" "Failed install linux-firmware";
                        fi
                     fi
                fi ;;

            8) log_msg "INFO" "Exiting Network Fix module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         local last_status=$?
         # Pause only if an action was attempted (excluding exit/invalid)
         if [[ "$choice" =~ ^[1-7]$ ]]; then
             if [[ "$choice" =~ ^[1346]$ && $last_status -eq 0 ]]; then # Only show basic success for checks
                 print_color "$GREEN" "\nCheck complete.";
             elif [[ $last_status -ne 0 ]]; then
                  # Error message already printed by run_command
                  print_color "$YELLOW" "\nOperation finished with status $last_status.";
             else
                  # Successful operation (like restart, apply, install)
                  print_color "$GREEN" "\nOperation finished successfully.";
             fi
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Network menu...")" < /dev/tty
         fi
    done
    return 0
}
# FINISH ### NETWORK FIX FUNCTION ###

# START ### KERNEL PINNING FUNCTION ###
run_kernel_pinning() {
    print_color "$PURPLE" "\n--- Module: Kernel Package Pinning ---"; log_msg "INFO" "Starting Kernel Pinning Module."
    local pin_file="/etc/apt/preferences.d/99-mybitch-kernel-pin"

    while true; do
        print_color "$YELLOW" "\nKernel Pinning Options:";
        echo " 1) Pin to CURRENTLY RUNNING Kernel ($(uname -r))"
        echo " 2) Pin to a SPECIFIC Installed Kernel"
        echo " 3) View Current Pinning File ($pin_file)"
        echo " 4) Remove Pinning File ($pin_file)"
        echo " 5) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-5]: ")" choice < /dev/tty

        case "$choice" in
            1) target_k=$(uname -r);
               if [[ -z "$target_k" ]]; then print_color "$RED" "Could not determine current kernel."; continue; fi
               print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $target_k.";
               if prompt_confirm "Create/overwrite pinning file for $target_k?"; then
                  generate_and_apply_pin "$target_k" "$pin_file"
               fi
               ;;
            2) # List installed kernels for selection
               print_color "$CYAN" "Identifying installed kernel versions..."
               local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
               while IFS= read -r k_image; do local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//'); local found=0; for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done; if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi; done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)
               if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernels found!"; log_msg "ERROR" "No kernels found for pinning."; continue; fi

               print_color "$YELLOW" "Select kernel version to pin TO:"
               for i in "${!kernel_map[@]}"; do echo " $i) ${kernel_map[$i]}" >&2; done; echo " $((count))) Cancel" >&2;
               local pin_choice; local selected_k=""
               while [[ -z "$selected_k" ]]; do read -r -p "$(print_color "$YELLOW" "Choice: ")" pin_choice < /dev/tty; if [[ "$pin_choice" =~ ^[0-9]+$ ]]; then if [[ "$pin_choice" -ge 1 && "$pin_choice" -lt "$count" ]]; then selected_k="${kernel_map[$pin_choice]}"; elif [[ "$pin_choice" -eq "$count" ]]; then print_color "$YELLOW" "Cancelled."; selected_k="cancel"; else print_color "$RED" "Invalid."; fi; else print_color "$RED" "Invalid."; fi; done
               if [[ "$selected_k" != "cancel" ]]; then
                    print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $selected_k.";
                    if prompt_confirm "Create/overwrite pinning file for $selected_k?"; then
                        generate_and_apply_pin "$selected_k" "$pin_file"
                    fi
               fi
               ;;
            3) print_color "$CYAN" "Contents of $pin_file:";
               if [[ -f "$pin_file" ]]; then run_command "cat $pin_file" false "View Pin File"; else print_color "$YELLOW" "Pin file does not exist."; fi
               ;;
            4) print_color "$YELLOW" "Removing kernel pinning file: $pin_file";
               if [[ ! -f "$pin_file" ]]; then print_color "$YELLOW" "Pin file does not exist."; continue; fi;
               if prompt_confirm "Remove the pinning file? (Allows kernel upgrades)"; then
                   if run_command "rm -vf $pin_file" false "Remove Pin File"; then
                       print_color "$GREEN" "Pin file removed. Run 'sudo apt update' for changes to take effect."; log_msg "INFO" "Removed pin file $pin_file."
                       run_command "apt-get update" false "Update APT after pin removal"
                   else
                       log_msg "ERROR" "Failed to remove pin file.";
                   fi
               fi
               ;;
            5) log_msg "INFO" "Exiting Kernel Pinning module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         # Add pause after actions
         if [[ "$choice" =~ ^[1-4]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Pinning menu...")" < /dev/tty
         fi
    done
    return 0
}

generate_and_apply_pin() {
    local pin_k="$1"
    local pin_f="$2"
    log_msg "INFO" "Generating pin file $pin_f for kernel $pin_k"

    # Extract base version number (e.g., 6.8.0-40) for wildcard matching
    local pin_base_ver; pin_base_ver=$(echo "$pin_k" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+')
    if [[ -z "$pin_base_ver" ]]; then
        print_color "$RED" "Could not extract base version from $pin_k for pinning."; log_msg "ERROR" "Could not extract base version from $pin_k"; return 1;
    fi

    local pin_content; cat << PIN_EOF > /tmp/kernel_pin_content
# Kernel Pinning Configuration generated by nvidia-mybitch.sh
# Prevents upgrades beyond kernel version containing '$pin_base_ver'

# Pin generic meta-packages and specific version packages
Package: linux-image-generic linux-headers-generic linux-generic* linux-image-*-generic linux-headers-*-generic linux-modules-*-generic linux-modules-extra-*-generic
Pin: version ${pin_base_ver}.*
Pin-Priority: 1001

# Example: Explicitly block a known bad version (Uncomment and edit if needed)
# Package: linux-image-6.8.0-57-generic linux-headers-6.8.0-57-generic linux-modules-6.8.0-57-generic linux-modules-extra-6.8.0-57-generic
# Pin: version 6.8.0-57.*
# Pin-Priority: -1

PIN_EOF

    pin_content=$(cat /tmp/kernel_pin_content)
    rm /tmp/kernel_pin_content

    print_color "$PURPLE" "--- Pinning File Content ---"
    print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$pin_content"; print_color "$PURPLE" "--------------------------" # Use type_effect here

    if ! prompt_confirm "Write this content to $pin_f?"; then log_msg "USER" "Cancelled writing pin file."; return 1; fi

    # Use sudo tee to write the file as root
    if echo "$pin_content" | sudo tee "$pin_f" > /dev/null; then
        sudo chown root:root "$pin_f" && sudo chmod 644 "$pin_f"
        print_color "$GREEN" "Pinning file $pin_f created/updated."; log_msg "INFO" "Wrote pin file $pin_f for $pin_k."
        print_color "$CYAN" "Running 'sudo apt update' to apply changes..."
        if run_command "apt-get update" false "Update APT after pinning"; then
             print_color "$GREEN" "APT cache updated. Kernel packages are now pinned.";
        else
             print_color "$RED" "APT update failed after pinning.";
        fi
        return 0
    else
        print_color "$RED" "Failed to write pinning file!"; log_msg "ERROR" "Failed to write pin file $pin_f."
        return 1
    fi
}
# FINISH ### KERNEL PINNING FUNCTION ###

# START ### GUIDED INSTALL FUNCTION ###
run_guided_install() {
    print_color "$PURPLE" "\n--- Guided Install: Nvidia Driver + CUDA (Method B Recommended) ---"; log_msg "INFO" "Starting Guided Install."
    print_color "$YELLOW" "This will run the recommended sequence based on successful logs:";
    print_color "$CYAN" "  1. Enhanced Deep Clean";
    print_color "$CYAN" "  2. Install Driver via Nvidia Repo (cuda-drivers)";
    print_color "$CYAN" "  3. Install CUDA Toolkit via APT (from Nvidia Repo)";
    print_color "$CYAN" "  4. Update Initramfs";
    print_color "$CYAN" "  5. Recommend Kernel Pinning";
    print_color "$RED" "Ensure you are booted into your desired WORKING kernel first!";
    local current_k; current_k=$(uname -r); print_color "$YELLOW" "(Currently running: $current_k)";

    if ! prompt_confirm "Proceed with Guided Install on kernel $current_k?"; then return 1; fi

    print_color "$PURPLE" "\n--- Step 1: Enhanced Deep Clean ---";
    if ! run_nvidia_cleanup; then
        log_msg "ERROR" "Guided Install: Deep Clean failed."; return 1;
    fi
    print_color "$GREEN" "Deep Clean Completed. Reboot highly recommended before proceeding.";
    if ! prompt_confirm "Continue install without rebooting (NOT RECOMMENDED)?"; then
        print_color "$YELLOW" "Exiting Guided Install. Please reboot into your desired kernel ($current_k) and run again."; log_msg "USER" "Aborted Guided Install for reboot."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 2: Install Driver via Nvidia Repo (cuda-drivers) ---";
    # Ensure repo is setup AND install the driver
    if ! install_nvidia_apt_official_repo "false"; then # Pass "false" to ensure it installs
        log_msg "ERROR" "Guided Install: Nvidia Repo Driver install failed."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 3: Install CUDA Toolkit via APT (from Nvidia Repo) ---";
    if ! install_cuda_toolkit_apt_core; then # This helper function installs the toolkit
        log_msg "ERROR" "Guided Install: CUDA Toolkit install failed."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 4: Update Initramfs ---";
    print_color "$CYAN" "Updating initramfs for all kernels...";
    if ! run_command "update-initramfs -u -k all" true "Guided Install Initramfs Update"; then
         log_msg "ERROR" "Guided Install: Initramfs update failed."; # Continue but warn
    fi

    print_color "$GREEN" "\n--- Guided Install Steps Completed Successfully ---";
    log_msg "INFO" "Guided Install finished successfully.";
    print_color "$YELLOW" "Reboot REQUIRED to activate drivers/toolkit.";
    print_color "$CYAN" "After rebooting into the working kernel ($current_k), verify with 'nvidia-smi' and 'nvcc --version'.";

    # Recommend Pinning
    print_color "$PURPLE" "\n--- Step 5: Recommendation - Kernel Pinning ---";
    print_color "$YELLOW" "To prevent problematic kernel updates from breaking this setup,";
    print_color "$YELLOW" "it's strongly recommended to PIN your current working kernel ($current_k).";
    if prompt_confirm "Go to Kernel Pinning module now?"; then
        run_kernel_pinning
    else
        print_color "$CYAN" "You can access Kernel Pinning later via Menu 9 -> 6.";
    fi
    return 0
}
# FINISH ### GUIDED INSTALL FUNCTION ###

# START ### SYSTEM PREP UTILS SUBMENU ###
run_system_prep_utils_submenu() {
     while true; do
         if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
         print_color "$PURPLE" "\n=== System Prep & Utils Submenu ===";
         echo "  $(print_color "$CYAN" "1)") Manage Display Manager (Stop/Start/Status)";
         echo "  $(print_color "$CYAN" "2)") Prepare Build Environment (DKMS, Headers, Tools)";
         echo "  $(print_color "$CYAN" "3)") Manage GCC Version (Check, Install 12, Show Switch Cmds)";
         echo "  $(print_color "$CYAN" "4)") Update Initramfs (For specific kernel or all)";
         echo "  $(print_color "$CYAN" "5)") Network Troubleshooting Tools";
         echo "  $(print_color "$CYAN" "6)") Kernel Package Pinning (Hold/Unhold)"; # Added pinning
         echo "  $(print_color "$CYAN" "7)") Return to Main Menu";
         local choice;
         read -r -p "$(print_color "$YELLOW" "Enter choice [1-7]: ")" choice < /dev/tty;
         case "$choice" in
             1) run_manage_display_manager ;;
             2) run_prepare_build_env ;;
             3) run_manage_gcc ;;
             4) run_update_initramfs ;;
             5) run_network_fix ;;
             6) run_kernel_pinning ;; # Added pinning call
             7) break;; # Exit submenu loop
             *) print_color "$RED" "Invalid selection.";;
         esac;
         local last_status=$?;
         # Only pause if an action ran (choice 1-6)
         if [[ "$choice" =~ ^[1-6]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to submenu...")" < /dev/tty;
         fi;
    done;
    return 0;
}
# FINISH ### SYSTEM PREP UTILS SUBMENU ###

# START ### MAIN MENU FUNCTION ###
main_menu() {
    print_color "$PURPLE" "\n=== $(print_color "$GREEN" "NVIDIA") $(print_color "$CYAN" "MyBitch") $(print_color "$PURPLE" "Manager") v$SCRIPT_VERSION ===";
    print_color "$GREEN" "Select an operation:";
    echo "  $(print_color "$CYAN" " 1)") Guided Install (Recommended: Clean -> Nvidia Repo Driver+CUDA)";
    echo "  $(print_color "$CYAN" " 2)") NVIDIA Deep Clean (Manual Step)";
    echo "  $(print_color "$CYAN" " 3)") NVIDIA Driver Install (Manual Step - APT Std, APT Nvidia, Runfile)";
    echo "  $(print_color "$CYAN" " 4)") Install CUDA Toolkit (Manual Step - APT or Runfile)";
    echo "  $(print_color "$CYAN" " 5)") Blacklist Nouveau Driver";
    echo "  $(print_color "$CYAN" " 6)") GRUB Fix / Reinstall / Params (Presets & Custom)";
    echo "  $(print_color "$CYAN" " 7)") Kernel Reset (Remove & Reinstall)";
    echo "  $(print_color "$CYAN" " 8)") Update Initramfs (Target specific kernel)";
    echo "  $(print_color "$CYAN" " 9)") System Prep & Utilities (DM, BuildEnv, GCC, Initramfs, Network, Pinning)"; # Updated desc
    echo "  $(print_color "$CYAN" "10)") Chroot Helper (Live OS ONLY)";
    echo "  $(print_color "$CYAN" "11)") View Logs (System, Nvidia, APT, etc.)";
    echo "  $(print_color "$CYAN" "12)") Exit";

    local choice;
    read -r -p "$(print_color "$YELLOW" "Enter choice [1-12]: ")" choice < /dev/tty;

    case "$choice" in
        1) run_guided_install ;;          # NEW
        2) run_nvidia_cleanup ;;           # Was 1
        3) run_nvidia_install ;;           # Was 2
        4) run_cuda_install ;;             # Was 3
        5) run_nouveau_blacklist ;;        # Was 4
        6) run_grub_fix ;;                 # Was 5
        7) run_kernel_fix ;;               # Was 6
        8) run_update_initramfs ;;         # Was 7
        9) run_system_prep_utils_submenu ;; # Was 8, now includes Pinning
       10) run_chroot_helper ;;            # Was 9
       11) run_view_logs ;;                # Was 10
       12) print_color "$GREEN" "Keep hustlin'. Exiting..."; log_msg "INFO" "Exiting script."; exit 0 ;; # Was 11
        *) print_color "$RED" "Invalid selection." ;;
    esac

    local last_status=$?;
    # Don't pause after invalid choice or exit
    if [[ "$choice" -ge 1 && "$choice" -le 11 ]]; then # Pause for options 1-11
        # Let sub-modules handle their own success/fail messages
        read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to main menu...")" < /dev/tty;
    fi;
}
# FINISH ### MAIN MENU FUNCTION ###

# START ### SCRIPT RUNNER ###
# Check sudo FIRST - it sets up USER_HOME and LOG paths
check_sudo

# Append to log file for history across runs
log_msg "INFO" "====== GPU Manager Started. Version $SCRIPT_VERSION ======"
log_msg "INFO" "Running as EUID=$EUID, User=$SUDO_USER, Home=$USER_HOME"

# Main loop
while true; do
    # Clear screen at the start of each main menu loop
    if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
    main_menu
done
# FINISH ### SCRIPT RUNNER ####!/usr/bin/env bash

# NVIDIA Management Script - "nvidia-mybitch.sh" v1.12
# Built for the streets, respects the hustle. No more bullshit placeholders.

# START ### CONFIGURATION ###
SCRIPT_VERSION="1.12" # Fixed Guided Install flow, GCC Alts, Clean flags
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
    # Check if log file path is set, exit if not (should be set by check_sudo)
    if [[ -z "$MAIN_LOG_FILE" ]]; then echo "FATAL: Main log file path not initialized!" >&2; exit 1; fi
    # Check if log file is writable, attempt to fix if not
    if [[ ! -w "$MAIN_LOG_FILE" && -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE not writable. Attempting chown..." >&2
         # Need sudo user context here, should be available
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "FATAL: Failed to chown log file. Cannot log." >&2; exit 1; }
         if [[ ! -w "$MAIN_LOG_FILE" ]]; then echo "FATAL: Log file still not writable after chown. Cannot log." >&2; exit 1; fi
    elif [[ ! -f "$MAIN_LOG_FILE" ]]; then
         echo "Warning: Log file $MAIN_LOG_FILE does not exist. Attempting touch..." >&2
         touch "$MAIN_LOG_FILE" || { echo "FATAL: Failed to touch log file. Cannot log." >&2; exit 1; }
         chown "$SUDO_USER:$SUDO_USER" "$MAIN_LOG_FILE" || { echo "Warning: Failed to chown new log file." >&2; }
    fi

    local level="$1"; local message="$2"; local log_line;
    log_line="$(date +'%Y-%m-%d %H:%M:%S') [$level] - $message"
    # Append to the log file
    echo "$log_line" >> "$MAIN_LOG_FILE"
    # Print ERROR and WARN messages to stderr as well, with color
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        local color="$YELLOW"; [[ "$level" == "ERROR" ]] && color="$RED"
        print_color "$color" "[$level] $message"
    fi
}


prompt_confirm() {
    local message="$1"; local default_choice="${2:-N}"; local psfx="[y/N]";
    [[ "$default_choice" =~ ^[Yy]$ ]] && psfx="[Y/n]"
    while true; do
        # Redirect stdin from /dev/tty to ensure it reads from keyboard even if script input is piped
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

type_effect() {
    local text="$1"; local delay="${2:-0.03}";
    # Check if NO_TYPE_EFFECT variable is set
    if [[ -z "$NO_TYPE_EFFECT" ]]; then
        local i;
        for (( i=0; i<${#text}; i++ )); do
             printf "%c" "${text:$i:1}" >&2;
             # Use awk for potentially more random sleep interval within bounds
             sleep "$(awk -v min=0.01 -v max="$delay" 'BEGIN{srand(); print min+rand()*(max-min)}')";
         done
    else
         # If NO_TYPE_EFFECT is set, just print the text without delay
         printf "%s" "$text" >&2;
    fi;
    # Always print a newline after the effect/text
    echo >&2;
}


check_sudo() {
    # Ensures script is run with sudo and determines the original user's home directory
    if [[ -z "$SUDO_USER" || "$EUID" -ne 0 ]]; then print_color "$RED" "Error: This script must be run using sudo."; exit 1; fi

    # Attempt to get the user's home directory reliably
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
        # Log initial failure before fallback
        echo -e "${YELLOW}Warn: Could not reliably determine user home via getent for $SUDO_USER. Falling back...${NC}" >&2
        USER_HOME=$(eval echo ~"$SUDO_USER") # Fallback method
        if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
             print_color "$RED" "FATAL: Could not determine home directory for user '$SUDO_USER'. Exiting."
             # No log_msg here as logging isn't set up yet
             exit 1
        fi
    fi
    # Check if the determined home is /root, which might be wrong unless root logged in directly
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
        print_color "$YELLOW" "Warning: Determined user home is /root, but sudo user is $SUDO_USER. This might be incorrect."
        # Log this warning once logging is initialized below
     fi

    LOG_DIR="$USER_HOME/gpu_manager_logs"; MAIN_LOG_FILE="$LOG_DIR/nvidia-mybitch_main_$(date +%Y%m%d_%H%M%S).log";
    # Ensure log directory exists
    mkdir -p "$LOG_DIR" || { print_color "$RED" "FATAL: Could not create log directory '$LOG_DIR'"; exit 1; };
    # Create log file
    touch "$MAIN_LOG_FILE" || { print_color "$RED" "FATAL: Could not create main log file '$MAIN_LOG_FILE'"; exit 1; };
    # Change ownership to the original user so they can access logs without sudo later
    chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR" "$MAIN_LOG_FILE" || print_color "$YELLOW" "Warn: Could not chown log directory/file to $SUDO_USER."

    # Now that logging is set up, log the earlier warning if needed
     if [[ "$USER_HOME" == "/root" && "$SUDO_USER" != "root" ]]; then
         log_msg "WARN" "Determined user home is /root, but sudo user is $SUDO_USER."
     fi
    log_msg "INFO" "Sudo check passed. Original User: $SUDO_USER. User Home: $USER_HOME. Logging to: $MAIN_LOG_FILE."
}

check_tty() {
    # Check if running in a TTY and not under X/Wayland (DISPLAY is set)
    # Allow override if user confirms
    if ! tty -s; then
        log_msg "WARN" "Script not running in a TTY (stdin is not a terminal)."
        print_color "$YELLOW" "Warning: Not running in a TTY. Interactive prompts might behave unexpectedly."
        if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Not TTY."; return 1; fi
    elif [[ -n "$DISPLAY" ]]; then
         log_msg "WARN" "DISPLAY environment variable is set ($DISPLAY). Running under X/Wayland?"
         print_color "$YELLOW" "Warning: Running inside a graphical session? Some operations (like stopping DM) work best from a TTY."
         if ! prompt_confirm "Continue anyway?"; then log_msg "USER" "Aborted: Running under GUI."; return 1; fi
    fi
    return 0;
}


get_display_manager() {
  local detected_dm=""; local final_dm=""; local user_input; log_msg "INFO" "Detecting DM...";
  # Check for common DMs via systemctl active state
  if systemctl list-units --type=service --state=active | grep -q -E 'gdm[0-9]*\.service|gdm\.service'; then detected_dm="gdm3.service";
  elif systemctl list-units --type=service --state=active | grep -q 'sddm\.service'; then detected_dm="sddm.service";
  elif systemctl list-units --type=service --state=active | grep -q 'lightdm\.service'; then detected_dm="lightdm.service";
  # Add other DMs here if needed (e.g., lxdm)
  fi;

  if [[ -n "$detected_dm" ]]; then
      log_msg "INFO" "Detected active DM: $detected_dm";
      read -r -p "$(print_color "$YELLOW" "Detected active Display Manager '$detected_dm'. Is this correct? [Y/n]: ")" confirm < /dev/tty; confirm="${confirm:-Y}";
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
           final_dm="$detected_dm"; log_msg "USER" "Confirmed DM: $final_dm";
      else
           log_msg "USER" "Rejected detected DM."; detected_dm=""; # Clear detected if rejected
      fi;
  fi;

  # If no DM confirmed or detected
  if [[ -z "$final_dm" ]]; then
       print_color "$YELLOW" "Could not detect/confirm Display Manager.";
       read -r -p "$(print_color "$YELLOW" "Enter your Display Manager service name (e.g., gdm3.service, sddm.service, lightdm.service) or leave blank to skip DM operations: ")" user_input < /dev/tty;
       if [[ -n "$user_input" ]]; then
            # Append .service if missing
            if [[ ! "$user_input" == *".service" ]]; then final_dm="${user_input}.service"; else final_dm="$user_input"; fi;
            log_msg "USER" "Manual DM entry: $final_dm";
            # Optional: Add a basic check if the service name seems valid?
            # if ! systemctl list-unit-files | grep -q "^${final_dm}"; then print_color "$YELLOW" "Warning: Service '$final_dm' not found by systemctl."; fi
       else
           print_color "$YELLOW" "Skipping Display Manager operations."; log_msg "USER" "Skipped DM entry."; final_dm="";
       fi;
  fi;

  echo "$final_dm"; # Return the determined DM name (or empty string)
  if [[ -n "$final_dm" ]]; then return 0; else return 1; fi; # Return status indicates if a DM was identified
}

run_command() {
    local cmd_string="$1"
    local log_output_to_file="${2:-false}" # Controls logging command's stdout/stderr to SEPARATE file (true/false)
    local cmd_desc="${3:-Command}"
    local tee_to_tty="${4:-true}" # Controls whether output is ALSO shown on screen (TTY)

    log_msg "EXEC" "($cmd_desc): $cmd_string"
    if [[ "$tee_to_tty" == true ]]; then
        print_color "$CYAN" "Running: $cmd_string"
    else
        # Avoid printing the command if output is hidden, just log it was executed
        log_msg "INFO" "Executing (output to log only): ($cmd_desc)"
    fi

    local output_log_file="${LOG_DIR}/cmd_output_$(date +%s)_$(echo "$cmd_desc" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c -50).log"
    local status
    # Base tee command always appends to main log file
    local tee_cmd_main="tee -a \"$MAIN_LOG_FILE\""
    local final_exec_cmd

    # --- Status Capture using temporary file (more reliable with pipes) ---
    local temp_status_file; temp_status_file=$(mktemp)
    # Command to be executed within bash -c. Needs careful quoting.
    # We want the exit status of the 'eval $cmd_string' part.
    # Ensure cmd_string with quotes inside works with eval
    # Using printf %q for robust quoting of the command string within eval
    local escaped_cmd_string; escaped_cmd_string=$(printf '%q ' $cmd_string) # Corrected quoting
    # The inner command executes the potentially complex command string and captures its exit status
    local inner_cmd="(eval $escaped_cmd_string; echo \$? > \"$temp_status_file\")"

    # Build the piping chain
    # Pipe stderr to stdout (2>&1), then pipe combined output to tee for main log
    local pipe_chain="$inner_cmd 2>&1 | $tee_cmd_main"

    if [[ "$log_output_to_file" == true ]]; then
        touch "$output_log_file" && chown "$SUDO_USER:$SUDO_USER" "$output_log_file" || log_msg "WARN" "Could not touch/chown output log $output_log_file"
        pipe_chain+=" | tee \"$output_log_file\"" # Pipe to separate log tee
        if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Logging output to $output_log_file AND main log AND screen)"
        else
             print_color "$CYAN" "(Logging output to $output_log_file AND main log ONLY)"
        fi
    else
         if [[ "$tee_to_tty" == true ]]; then
             print_color "$CYAN" "(Command output will appear below and in main log)"
         else
              print_color "$CYAN" "(Command output to main log ONLY)"
          fi
    fi

    # Final redirection based on tee_to_tty
    if [[ "$tee_to_tty" == true ]]; then
        pipe_chain+=" > /dev/tty" # Redirect final output to TTY
    else
        pipe_chain+=" > /dev/null" # Suppress final output
    fi

    # Execute the whole chain using bash -c
    bash -c "$pipe_chain"
    # Read status reliably, handle potential empty file
    status=$(cat "$temp_status_file" 2>/dev/null)
    # Fallback if temp file is empty or read failed (should not happen often)
    [[ -z "$status" ]] && status=1
    rm "$temp_status_file"
    # --- End Status Capture ---


    log_msg "INFO" "($cmd_desc) finished status: $status"

    # Check the captured status
    if [[ "$status" -ne 0 ]]; then
        # Ensure error message is visible even if tee_to_tty was false for the command itself
        print_color "$RED" "Command ($cmd_desc) failed! Status: $status"
        print_color "$YELLOW" "Check main log file: $MAIN_LOG_FILE"
        if [[ "$log_output_to_file" == true ]]; then print_color "$YELLOW" "Also check separate log: $output_log_file"; fi
        return "$status" # Use numeric return status
    fi

    # Clean up empty separate log file if it was created but not needed
    if [[ "$log_output_to_file" == true && -f "$output_log_file" && ! -s "$output_log_file" ]]; then
        log_msg "INFO" "Removing empty separate log file: $output_log_file"
        rm "$output_log_file" &> /dev/null
    fi
    return 0
}


view_log_file() {
    local log_path="$1"; local log_desc="$2";
    print_color "$CYAN" "Viewing: $log_desc ($log_path)"; log_msg "INFO" "Viewing log: $log_desc ($log_path)"
    if [[ ! -f "$log_path" ]]; then print_color "$YELLOW" "Not found: $log_path"; log_msg "WARN" "Log not found: $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Check read permissions for the effective user (root)
    if [[ ! -r "$log_path" ]]; then print_color "$RED" "Cannot read (check permissions): $log_path"; log_msg "ERROR" "Cannot read log (permissions?): $log_path"; read -r -p "$(print_color "$YELLOW" "Press Enter to continue...")" < /dev/tty; return 1; fi
    # Use less with flags for better viewing, ensuring it reads from TTY
    less -Rf "$log_path" < /dev/tty
}
# FINISH ### HELPER FUNCTIONS ###

# START ### MODULE DISPLAY MANAGER ###
run_manage_display_manager() {
    print_color "$PURPLE" "\n--- Module: Display Manager Control ---"; log_msg "INFO" "Starting DM Control.";
    local dm; dm=$(get_display_manager); if [[ $? -ne 0 || -z "$dm" ]]; then print_color "$YELLOW" "Cannot manage Display Manager (not found or skipped)."; return 1; fi;
    print_color "$YELLOW" "Action for Display Manager '$dm':"; echo " 1) Stop"; echo " 2) Start"; echo " 3) Status"; echo " 4) Cancel"; local choice;
    read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;
    case "$choice" in
        1) if ! check_tty; then return 1; fi; # Extra check before stopping DM
           run_command "systemctl stop $dm" false "Stop DM";;
        2) run_command "systemctl start $dm" false "Start DM";;
        3) run_command "systemctl status $dm --no-pager" false "DM Status";; # Added no-pager
        4) log_msg "USER" "Cancelled DM action."; return 1;; *) print_color "$RED" "Invalid."; return 1;;
    esac; return $?;
}
# FINISH ### MODULE DISPLAY MANAGER ###

# START ### MODULE PREPARE BUILD ENV ###
run_prepare_build_env() {
    print_color "$PURPLE" "\n--- Module: Prepare Build Environment ---"; log_msg "INFO" "Starting Build Env Prep.";
    print_color "$CYAN" "Ensures DKMS, build-essential, and headers for CURRENT kernel are installed.";
    local k; k=$(uname -r); local hdr="linux-headers-${k}"; local req="dkms build-essential ${hdr}";
    print_color "$CYAN" "Checking required packages (dkms, build-essential, $hdr)..."; log_msg "INFO" "Checking build env packages: $req"; local missing="";
    for pkg in dkms build-essential "$hdr"; do
        # Use dpkg-query with a check for return status
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            # If check fails, add to missing list
            missing+="$pkg ";
        fi
    done
    if [[ -n "$missing" ]]; then log_msg "WARN" "Missing build env packages: ${missing% }"; print_color "$YELLOW" "Missing packages: ${missing% }"; if ! prompt_confirm "Install/reinstall required packages?"; then log_msg "USER" "Skipped build env pkg install."; return 1; fi;
        print_color "$CYAN" "Running apt-get update & install..."; if ! run_command "apt-get update" false "Update build env"; then log_msg "WARN" "apt-get update failed."; fi; if ! run_command "apt-get install --reinstall -y $req" true "Install build env"; then log_msg "ERROR" "Build env install failed."; return 1; fi; log_msg "INFO" "Build env pkgs installed/reinstalled."; print_color "$GREEN" "Build env packages installed/reinstalled.";
    else log_msg "INFO" "Build env packages already present."; print_color "$GREEN" "Required build environment packages seem installed."; if prompt_confirm "Reinstall them anyway?"; then print_color "$CYAN" "Running apt-get update & reinstall..."; if ! run_command "apt-get update && apt-get install --reinstall -y $req" true "Reinstall build env"; then log_msg "ERROR" "Build env reinstall failed."; return 1; fi; log_msg "INFO" "Build env packages reinstalled."; print_color "$GREEN" "Build env packages reinstalled."; fi; fi;
    print_color "$CYAN" "Checking DKMS status..."; run_command "dkms status" false "DKMS Status Check"; print_color "$GREEN" "\n--- Build Env Prep Finished ---"; log_msg "INFO" "Build Env Prep finished."; return 0;
}
# FINISH ### MODULE PREPARE BUILD ENV ###

# START ### MODULE MANAGE GCC ###
run_manage_gcc() {
    print_color "$PURPLE" "\n--- Module: Manage GCC Version ---"; log_msg "INFO" "Starting GCC Mgmt.";
    local gcc; gcc=$(gcc --version | head -n1); local gpp; gpp=$(g++ --version | head -n1); print_color "$CYAN" "Current Default GCC: $gcc"; print_color "$CYAN" "Current Default G++: $gpp"; log_msg "INFO" "Current GCC: $gcc / G++: $gpp";
    print_color "$YELLOW" "\nNote: Nvidia drivers usually build with the default GCC for your Ubuntu release.";
    print_color "$YELLOW" "Use these options only if you encounter build issues related to GCC.";
    echo "\nOptions:";
    echo " 1) Check alternatives (see installed/configured versions)";
    echo " 2) Install GCC/G++ 12 (if not present)";
    echo " 3) Setup GCC 11/12 Alternatives (Runs update-alternatives --install)"; # Fixed
    echo " 4) Interactively Choose Default GCC (Runs update-alternatives --config)"; # Fixed
    echo " 5) Back"; local choice; # Renumbered
    read -r -p "$(print_color "$YELLOW" "Choice [1-5]: ")" choice < /dev/tty;
    case "$choice" in
        1) print_color "$CYAN" "Checking gcc alternatives..."; run_command "update-alternatives --display gcc" false "GCC Alts"; print_color "$CYAN" "Checking g++ alternatives..."; run_command "update-alternatives --display g++" false "G++ Alts";;
        2) print_color "$CYAN" "Checking gcc-12/g++-12..."; if dpkg-query -W -f='${Status}' gcc-12 2>/dev/null | grep -q "ok installed" && dpkg-query -W -f='${Status}' g++-12 2>/dev/null | grep -q "ok installed"; then print_color "$GREEN" "gcc-12 & g++-12 already installed."; log_msg "INFO" "gcc-12/g++-12 already installed."; else print_color "$YELLOW" "gcc-12/g++-12 not found."; if prompt_confirm "Install gcc-12 and g++-12?"; then if run_command "apt-get update && apt-get install -y gcc-12 g++-12" true "Install GCC 12"; then log_msg "INFO" "Installed gcc-12/g++-12."; print_color "$YELLOW" "Run Option 3 to set up alternatives if needed."; else log_msg "ERROR" "Install GCC 12 failed."; fi; fi; fi;;
        3) # Setup Alternatives - Fixed
           print_color "$CYAN" "Setting up alternatives for GCC 11 & 12...";
           # Check if both are installed first
           local gcc11_ok=false; local gcc12_ok=false;
           if command -v gcc-11 &> /dev/null && command -v g++-11 &> /dev/null; then gcc11_ok=true; fi;
           if command -v gcc-12 &> /dev/null && command -v g++-12 &> /dev/null; then gcc12_ok=true; fi;
           if [[ "$gcc11_ok" != true ]]; then
                print_color "$YELLOW" "Warning: gcc-11 / g++-11 not found. Please install first.";
                log_msg "WARN" "Attempted setup alternatives without GCC 11 installed."; return 1;
           fi
             if [[ "$gcc12_ok" != true ]]; then
                print_color "$YELLOW" "Warning: gcc-12 / g++-12 not found. Install using Option 2 first.";
                log_msg "WARN" "Attempted setup alternatives without GCC 12 installed."; return 1;
           fi
           local cmd1="update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 110 --slave /usr/bin/g++ g++ /usr/bin/g++-11"
           local cmd2="update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 120 --slave /usr/bin/g++ g++ /usr/bin/g++-12"
           print_color "$YELLOW" "This will run the following commands:";
           print_color "$CYAN" " sudo $cmd1";
           print_color "$CYAN" " sudo $cmd2";
           if prompt_confirm "Run these commands to set up alternatives?"; then
                local success=true
                run_command "$cmd1" false "Setup GCC 11 Alt" || success=false
                run_command "$cmd2" false "Setup GCC 12 Alt" || success=false
                if [[ "$success" == true ]]; then
                    print_color "$GREEN" "Alternatives set up. Use Option 4 to choose the default."; log_msg "INFO" "Ran update-alternatives install cmds.";
                else
                    print_color "$RED" "One or more commands failed. Check logs."; log_msg "ERROR" "update-alternatives install cmds failed.";
                fi
           else
                log_msg "USER" "Cancelled setup alternatives.";
           fi
           ;;
        4) # Configure Default - Fixed
           print_color "$CYAN" "Running interactive config to choose default GCC...";
           log_msg "EXEC" "update-alternatives --config gcc"
           # Need to run sudo directly as run_command isn't interactive
           # Redirect stderr to /dev/null to avoid clutter if user cancels with Ctrl+C
           if sudo update-alternatives --config gcc < /dev/tty 2>/dev/null; then
               log_msg "INFO" "User configured default GCC.";
               gcc=$(gcc --version | head -n1); print_color "$GREEN" "Default GCC is now: $gcc";
           else
                # Check status code? Difficult without direct execution. Assume user cancelled or error occurred.
                log_msg "WARN" "update-alternatives config command failed or was cancelled by user.";
                print_color "$YELLOW" "Interactive configuration failed or cancelled."
           fi
           ;;
        5) return 0;; *) print_color "$RED" "Invalid."; return 1;;
    esac;
    return 0;
}
# FINISH ### MODULE MANAGE GCC ###

# -------------------------------------------------------------
# END OF PART 1 - READY FOR PART 2
# -------------------------------------------------------------
# START ### MODULE NOUVEAU BLACKLIST ###
run_nouveau_blacklist() {
    print_color "$PURPLE" "\n--- Module: Blacklist Nouveau Driver ---"; log_msg "INFO" "Starting Nouveau Blacklist.";
    local conf="/etc/modprobe.d/blacklist-nvidia-nouveau-mybitch.conf"; # Use unique name
    local content="blacklist nouveau\noptions nouveau modeset=0";
    if [[ -f "$conf" ]]; then
         print_color "$YELLOW" "Blacklist file '$conf' already exists.";
         if ! prompt_confirm "Overwrite existing file?"; then log_msg "USER" "Skipped blacklist overwrite."; return 1; fi
    elif ! prompt_confirm "Create modprobe config '$conf' to blacklist Nouveau?"; then
         log_msg "USER" "Cancelled blacklist creation."; return 1;
    fi;
    print_color "$CYAN" "Creating/Overwriting $conf...";
    # Use run_command to create the file safely with sudo
    if run_command "echo -e \"$content\" | tee \"$conf\" > /dev/null" false "Write Nouveau Blacklist"; then
        print_color "$CYAN" "Running update-initramfs for all kernels...";
        if run_command "update-initramfs -u -k all" true "Update initramfs for blacklist"; then
            print_color "$GREEN" "Nouveau blacklisted successfully."; print_color "$YELLOW" "A reboot is required for changes to take effect."; log_msg "INFO" "Nouveau blacklisted ok."; return 0;
        else log_msg "ERROR" "update-initramfs failed after blacklist."; return 1; fi
    else log_msg "ERROR" "Write blacklist file failed."; return 1; fi
}
# FINISH ### MODULE NOUVEAU BLACKLIST ###

# START ### MODULE NVIDIA CLEANUP ###
run_nvidia_cleanup() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Deep Clean (Enhanced v1.12) ---"; log_msg "INFO" "Starting Enhanced Deep Clean.";
    print_color "$YELLOW" "This attempts to COMPLETELY remove Nvidia drivers, CUDA, configs, and DKMS entries.";
    if ! prompt_confirm "Proceed with Enhanced Deep Clean?"; then return 1; fi;
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then print_color "$CYAN" "Stopping Display Manager ($dm)..."; run_command "systemctl stop $dm" false "Stop DM Clean" || print_color "$YELLOW" "Warn: Stop DM failed, continuing anyway."; fi

    print_color "$CYAN" "\nStep 1: Removing DKMS modules..."; local dkms_mods; dkms_mods=$(dkms status | grep -Ei 'nvidia|nvidia-fs' | awk -F',|/' '{print $1"/"$2}' | sort -u); if [[ -n "$dkms_mods" ]]; then local fail=0; for mod in $dkms_mods; do print_color "$YELLOW" " Removing DKMS module: $mod"; run_command "dkms remove $mod --all" false "Remove DKMS $mod" || fail=1; done; if [[ $fail -eq 1 ]]; then log_msg "ERROR" "One or more DKMS remove commands failed."; fi; print_color "$CYAN" " Verifying DKMS status..."; sleep 1; if dkms status | grep -qEi 'nvidia|nvidia-fs'; then log_msg "WARN" "Nvidia DKMS modules may still remain!"; print_color "$YELLOW" "Warning: Nvidia DKMS modules may still remain! Check 'dkms status'."; else print_color "$GREEN" " All Nvidia DKMS modules removed."; log_msg "INFO" "Nvidia DKMS modules removed."; fi; else print_color "$GREEN" " No Nvidia DKMS modules found to remove."; log_msg "INFO" "No Nvidia DKMS modules found."; fi
    print_color "$CYAN" " Manually removing DKMS source tree (extra precaution)...";
    run_command "rm -rf /var/lib/dkms/nvidia*" false "Remove DKMS source"

    print_color "$CYAN" "\nStep 2: Finding & Purging related packages (Aggressive)...";
    local pkgs_pattern='nvidia|cuda|libnvidia|cublas|cufft|cufile|curand|cusolver|cusparse|npp|nvjpeg|libnvjitlink|nsight';
    local pkgs; pkgs=$(dpkg -l | grep -Ei "$pkgs_pattern" | grep -E '^ii' | awk '{print $2}' | tr '\n' ' ');
    if [[ -z "$pkgs" ]]; then print_color "$GREEN" " No related packages found via dpkg."; log_msg "INFO" "No packages found for purge."; else print_color "$YELLOW" " Found potentially related packages:"; echo "$pkgs" | fold -s -w 80 | sed 's/^/    /' >&2; log_msg "INFO" "Aggressive Purge list: $pkgs"; if ! prompt_confirm "Purge these packages?"; then log_msg "USER" "Cancelled package purge."; return 1; fi; print_color "$CYAN" " Purging packages (apt-get purge)..."; if ! run_command "apt-get purge --autoremove -y $pkgs" true "APT Purge Nvidia CUDA Aggressive"; then log_msg "ERROR" "apt purge failed."; print_color "$YELLOW" " Attempting fixes..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; print_color "$RED" "Purge failed, even after fixes."; return 1; else print_color "$GREEN" " Package purge complete."; log_msg "INFO" "APT purge done."; fi; fi

    print_color "$CYAN" "\nStep 3: Cleaning configuration & leftover files (Aggressive)...";
    local files_to_remove=(
        "/etc/modprobe.d/blacklist-nvidia*.conf"
        "/etc/modprobe.d/nvidia*.conf"
        "/etc/X11/xorg.conf*"
        "/etc/X11/xorg.conf.d/20-nvidia.conf" # Common location for generated config
        "/lib/udev/rules.d/*nvidia*.rules"
        "/etc/udev/rules.d/*nvidia*.rules"
        "/usr/share/X11/xorg.conf.d/*nvidia*.conf"
        "/usr/lib/nvidia/" # Check if dir exists, use rm -rf
        "/usr/share/nvidia/" # Check if dir exists, use rm -rf
        "/etc/nvidia/"     # Check if dir exists, use rm -rf
    )
    print_color "$YELLOW" "Removing known config/rule/directory patterns:"
    for item in "${files_to_remove[@]}"; do
        # Use -e check first for files/dirs/links
        # Use find for wildcard patterns for safety
        if [[ "$item" == *\* ]]; then
            local parent_dir; parent_dir=$(dirname "$item")
            local base_pattern; base_pattern=$(basename "$item")
            if [[ -d "$parent_dir" ]]; then
                # Use find + exec rm -rf for patterns
                run_command "find \"$parent_dir\" -maxdepth 1 -name \"$base_pattern\" -print -exec rm -rf {} +" false "Remove Pattern $item"
            else
                 log_msg "INFO" "Parent directory $parent_dir for pattern $item not found, skipping."
            fi
        # Use -e check for specific files/dirs/links AFTER handling wildcard
        elif [[ -e "$item" || -L "$item" ]]; then
            if [[ -d "$item" && ! -L "$item" ]]; then # It's a directory, not a symlink
                 run_command "rm -rf \"$item\"" false "Remove Dir $item"
            else # Specific file or symlink
                 run_command "rm -vf \"$item\"" false "Remove File $item"
            fi
        else
             log_msg "INFO" "Item $item not found, skipping."
        fi
    done
    print_color "$CYAN" " Searching for leftover Nvidia modules in current kernel dir...";
    run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -ls" false "Find Leftover Modules"
    if prompt_confirm "Attempt to delete found leftover modules (Use with caution)?"; then
        run_command "find /lib/modules/$(uname -r)/ -name '*nvidia*' -delete" false "Delete Leftover Modules"
    fi
    print_color "$GREEN" " Config/Leftover file cleanup attempted."

    print_color "$CYAN" "\nStep 4: Cleaning APT cache & fixing system...";
    run_command "apt-get clean" false "Clean APT Cache";
    run_command "apt-get --fix-broken install -y" true "Fix Broken Install";
    run_command "apt-get autoremove -y" true "Autoremove Orphans";
    run_command "dpkg --configure -a" false "Reconfigure dpkg";
    print_color "$GREEN" " System cleanup/fix steps done."

    print_color "$CYAN" "\nStep 5: Rebuilding initramfs for all kernels..."; if run_command "update-initramfs -u -k all" true "Update Initramfs After Clean"; then print_color "$GREEN" " Initramfs updated."; else log_msg "ERROR" "initramfs rebuild failed!"; fi

    print_color "$GREEN" "\n--- NVIDIA Enhanced Deep Clean Complete ---";
    print_color "$YELLOW" "Reboot strongly recommended before attempting reinstall."; log_msg "INFO" "Enhanced Deep Clean module finished.";
    if [[ -n "$dm" ]]; then if prompt_confirm "Attempt to restart Display Manager ($dm) now (might fail)?" "N"; then run_command "systemctl start $dm" false "Restart DM after Clean"; fi; fi
    return 0
}
# FINISH ### MODULE NVIDIA CLEANUP ###

# START ### NVIDIA INSTALL FUNCTION ###
run_nvidia_install() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install ---"; log_msg "INFO" "Starting Driver Install.";
    print_color "$CYAN" "Pre-flight checks..."; if ! run_prepare_build_env; then log_msg "ERROR" "Aborting: Build env prep failed."; return 1; fi;
    local sb_stat; sb_stat=$(mokutil --sb-state 2>/dev/null || echo "Unknown"); log_msg "INFO" "Secure Boot: $sb_stat"; print_color "$CYAN" " Secure Boot: $sb_stat"; if [[ "$sb_stat" == "SecureBoot enabled" ]]; then print_color "$RED" " ERROR: Secure Boot ENABLED."; log_msg "ERROR" "Secure Boot enabled."; if ! prompt_confirm "Disable Secure Boot in BIOS/UEFI first? (Y=Exit now / n=Continue - INSTALL WILL LIKELY FAIL)"; then log_msg "WARN" "Continuing with Secure Boot enabled - Expect failure."; else return 1; fi; fi

    local driver_ver=""; local method=""
    # Select method first
    while true; do
        print_color "$YELLOW" "\nSelect install method:";
        echo " 1) APT (Ubuntu Repo - nvidia-driver-XXX)";
        echo " 2) Runfile ($USER_HOME - Offers download for specific versions)";
        echo " 3) APT (Nvidia Repo - cuda-drivers meta-package)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt_ubuntu"; break;;
            2) method="runfile"; break;;
            3) method="apt_nvidia"; break;;
            *) print_color "$RED" "Invalid.";;
        esac;
    done;
    log_msg "USER" "Selected method: $method"

    local status=1;
    if [[ "$method" == "apt_ubuntu" ]]; then
        # Ask for version specifically for this method
        while true; do print_color "$YELLOW" "\nSelect driver version for nvidia-driver-XXX package:"; echo " 1) 535"; echo " 2) 550"; echo " 3) 570"; read -r -p "$(print_color "$YELLOW" "Choice: ")" ver_choice < /dev/tty; case "$ver_choice" in 1) driver_ver="535"; break;; 2) driver_ver="550"; break;; 3) driver_ver="570"; break;; *) print_color "$RED" "Invalid.";; esac; done; log_msg "USER" "Selected driver version for APT Ubuntu: $driver_ver"
        install_nvidia_apt "$driver_ver"; status=$?;
    elif [[ "$method" == "apt_nvidia" ]]; then
        install_nvidia_apt_official_repo; status=$?; # Version is handled by cuda-drivers package
    elif [[ "$method" == "runfile" ]]; then
        install_nvidia_runfile; status=$?; # Runfile selection/download handles version inside
    else
        log_msg "ERROR" "Invalid method stored: $method"; status=1; # Should not happen
    fi

    if [[ $status -eq 0 ]]; then
         print_color "$GREEN" "\n--- Driver Install Complete ---";
         # Update initramfs after successful install is good practice
         if prompt_confirm "Run 'update-initramfs -u -k all' now?" "Y"; then
             run_command "update-initramfs -u -k all" true "Post-Install Initramfs Update"
         fi
         print_color "$YELLOW" "Reboot REQUIRED.";
         print_color "$CYAN" "Verify with 'nvidia-smi' after reboot.";
         log_msg "INFO" "Driver install success.";
    else
         print_color "$RED" "\n--- Driver Install Failed ---";
         log_msg "ERROR" "Driver install failed.";
    fi
    return $status
}
# FINISH ### NVIDIA INSTALL FUNCTION ###

# START ### NVIDIA INSTALL APT UBUNTU ###
install_nvidia_apt() {
    local ver="$1"; local pkg="nvidia-driver-$ver"
    print_color "$CYAN" "\nStarting Standard APT install (Ubuntu Repo): $pkg"; log_msg "INFO" "Starting APT Ubuntu install: $pkg"
    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for APT Ubuntu" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    run_command "apt-get update" false "Update before driver" || print_color "$YELLOW" "Warn: apt update failed."
    print_color "$CYAN" "Installing $pkg...";
    # Use 'apt-get' for better scriptability / consistency with purge
    if run_command "apt-get install $pkg -y" true "Install $pkg"; then # Log full output to separate file
        log_msg "INFO" "APT install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        # Check for the specific version installed via DKMS
        if echo "$dkms_out" | grep -q "nvidia/${ver}"; then print_color "$GREEN" "DKMS built ok for $ver."; log_msg "INFO" "DKMS PASSED for nvidia/${ver}."; return 0;
        # Fallback check in case version string has minor diffs (e.g. 535.183.01)
        elif echo "$dkms_out" | grep -q "nvidia/" | grep -q "${ver}\."; then print_color "$GREEN" "DKMS built ok (found ${ver}.x)."; log_msg "INFO" "DKMS PASSED (found nvidia/${ver}.x)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found for $ver!"; log_msg "ERROR" "DKMS FAILED for $ver."; print_color "$YELLOW" "Check logs (Option 11 -> 2)."; return 1; fi
    else log_msg "ERROR" "apt-get install $pkg failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi
}
# FINISH ### NVIDIA INSTALL APT UBUNTU ###

# START ### NVIDIA INSTALL APT NVIDIA REPO ###
# Installs driver using cuda-drivers from Nvidia repo, also sets up repo if needed.
install_nvidia_apt_official_repo() {
    # No version argument needed here.
    local setup_only="${1:-false}" # Optional arg to only setup repo without install

    if [[ "$setup_only" == true ]]; then
        print_color "$CYAN" "\nEnsuring Nvidia Repo is configured (Setup Only)..."; log_msg "INFO" "Starting Nvidia Repo setup check/config.";
    else
        print_color "$CYAN" "\nStarting Nvidia Repo APT install (using 'cuda-drivers')..."; log_msg "INFO" "Starting Nvidia Repo APT install.";
        if ! check_tty; then return 1; fi
        local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Nvidia Repo" || print_color "$YELLOW" "Warn: Stop DM failed."; fi
    fi

    print_color "$CYAN" "Checking/Installing prerequisite tools (wget, gnupg)...";
    run_command "apt-get update" false "Pre-update for repo tools" || print_color "$YELLOW" "Warn: apt update failed.";
    run_command "apt-get install -y software-properties-common gnupg wget" true "Install common tools" || { log_msg "ERROR" "Failed to install prerequisite tools"; return 1; }

    print_color "$CYAN" "Checking/Installing Nvidia repo keyring...";
    local os_codename; os_codename=$(lsb_release -cs);
    if [[ -z "$os_codename" ]]; then print_color "$RED" "Cannot determine OS codename."; log_msg "ERROR" "Cannot get OS codename."; return 1; fi
    local repo_base_url="https://developer.download.nvidia.com/compute/cuda/repos"
    # Use a potentially more stable keyring version, check Nvidia docs if this changes
    local keyring_deb="cuda-keyring_1.1-1_all.deb"
    local keyring_url="${repo_base_url}/${os_codename}/x86_64/${keyring_deb}"
    local keyring_installed=false
    if dpkg-query -W -f='${Status}' cuda-keyring 2>/dev/null | grep -q "ok installed"; then
        log_msg "INFO" "cuda-keyring already installed."; keyring_installed=true;
    else
        print_color "$YELLOW" "'cuda-keyring' not found. Attempting download and install...";
        if ! run_command "wget $keyring_url -O /tmp/${keyring_deb}" false "Download Keyring"; then log_msg "ERROR" "Keyring download failed."; return 1; fi
        if ! run_command "dpkg -i /tmp/${keyring_deb}" true "Install Keyring"; then log_msg "ERROR" "Keyring install failed."; rm -f /tmp/${keyring_deb}; return 1; fi
        rm -f /tmp/${keyring_deb}; log_msg "INFO" "cuda-keyring installed."; keyring_installed=true;
    fi
    if [[ "$keyring_installed" != true ]]; then print_color "$RED" "Failed to ensure cuda-keyring is installed."; return 1; fi

    print_color "$CYAN" "Checking/Adding Nvidia CUDA repository file...";
    local repo_file="/etc/apt/sources.list.d/cuda-${os_codename}-x86_64.list"
    local repo_line="deb ${repo_base_url}/${os_codename}/x86_64/ /"
    local repo_changed=false
    if [[ ! -f "$repo_file" ]]; then
         print_color "$CYAN" "Adding Nvidia CUDA repository file: $repo_file...";
         # Use sudo tee directly for clarity/simplicity here
         if echo "$repo_line" | sudo tee "$repo_file" > /dev/null; then
            sudo chown root:root "$repo_file" && sudo chmod 644 "$repo_file"
            log_msg "INFO" "Nvidia CUDA repository file created."; repo_changed=true;
         else
            log_msg "ERROR" "Failed to create CUDA repository file: $repo_file."; return 1;
         fi
    else
        log_msg "INFO" "Nvidia CUDA repository file already exists: $repo_file"
        # Check content and add if missing
        if ! grep -qxF "$repo_line" "$repo_file"; then
            print_color "$YELLOW" "Repo file exists but missing expected line. Appending..."
            if echo "$repo_line" | sudo tee -a "$repo_file" > /dev/null; then
                 log_msg "INFO" "Appended Nvidia repo line to $repo_file"; repo_changed=true;
            else
                 log_msg "ERROR" "Failed to append repo line to $repo_file"; return 1;
            fi
        fi
    fi

    # Only run apt update if repo was added/changed or if installing
    if [[ "$repo_changed" == true || "$setup_only" == false ]]; then
        print_color "$CYAN" "Updating APT cache after repo configuration...";
        run_command "apt-get update" false "Update after repo setup" || print_color "$YELLOW" "Warn: apt update failed."
    fi

    if [[ "$setup_only" == true ]]; then
        print_color "$GREEN" "Nvidia repository setup complete."; return 0;
    fi

    # Proceed with driver install if not setup_only
    print_color "$CYAN" "Installing 'cuda-drivers' meta-package from Nvidia repo..."; log_msg "EXEC" "apt-get install cuda-drivers -y"
    if run_command "apt-get install cuda-drivers -y" true "Install cuda-drivers"; then
        log_msg "INFO" "APT cuda-drivers install cmd finished ok."; print_color "$CYAN" "Verifying DKMS status..."; log_msg "INFO" "Verifying DKMS..."; sleep 2; local dkms_out; dkms_out=$(dkms status); log_msg "INFO" "DKMS Status: $dkms_out";
        if echo "$dkms_out" | grep -q "nvidia/"; then print_color "$GREEN" "DKMS module seems built."; log_msg "INFO" "DKMS check PASSED (found nvidia module)."; return 0;
        else print_color "$RED" "ERROR: DKMS module NOT found after cuda-drivers install!"; log_msg "ERROR" "DKMS check FAILED (no nvidia module found)."; return 1; fi
    else
        log_msg "ERROR" "apt-get install cuda-drivers failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg cfg"; run_command "apt-get install -f -y" true "apt fix"; return 1;
    fi
}
# FINISH ### NVIDIA INSTALL APT NVIDIA REPO ###

# -------------------------------------------------------------
# END OF PART 2 - READY FOR PART 3
# -------------------------------------------------------------
# START ### NVIDIA INSTALL RUNFILE ###
install_nvidia_runfile() {
    print_color "$PURPLE" "\n--- Module: NVIDIA Driver Install via Runfile ---"; log_msg "INFO" "Starting Runfile Install Module.";

    # Check for wget
    if ! command -v wget &> /dev/null; then
        print_color "$YELLOW" "wget command not found, needed for downloads.";
        if prompt_confirm "Attempt to install wget (apt install wget)?"; then
            if ! run_command "apt-get update && apt-get install -y wget" true "Install wget"; then
                log_msg "ERROR" "Failed to install wget. Download unavailable."; return 1;
            fi
        else
            log_msg "WARN" "wget not installed. Download option disabled.";
            print_color "$RED" "Exiting runfile install as download might be required."; return 1;
        fi
    fi

    # --- Define known runfiles and URLs ---
    local runfile_535_name="NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_535_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/535.154.05/NVIDIA-Linux-x86_64-535.154.05.run"
    local runfile_570_name="NVIDIA-Linux-x86_64-570.133.07.run"
    local runfile_570_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/570.133.07/NVIDIA-Linux-x86_64-570.133.07.run"

    local runfile_path=""; local chosen_rn="";

    while [[ -z "$runfile_path" ]]; do
        print_color "$YELLOW" "\nSelect Runfile source:";
        echo " 1) Use $runfile_535_name (Check $USER_HOME, download if missing)";
        echo " 2) Use $runfile_570_name (Check $USER_HOME, download if missing)";
        echo " 3) Search $USER_HOME for other NVIDIA-*.run files";
        echo " 4) Cancel";
        read -r -p "$(print_color "$YELLOW" "Choice [1-4]: ")" choice < /dev/tty;

        case "$choice" in
            1) # Specific 535
               chosen_rn="$runfile_535_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       # Use run_command to log wget output
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_535_url\"" true "Download $chosen_rn"; then
                            # Set ownership to user after download
                            run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                            print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                            log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                    print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 1
            2) # Specific 570
               chosen_rn="$runfile_570_name"; runfile_path="$USER_HOME/$chosen_rn";
               if [[ ! -f "$runfile_path" ]]; then
                   print_color "$YELLOW" "File not found: $runfile_path"; log_msg "WARN" "Runfile missing: $runfile_path";
                   if prompt_confirm "Download $chosen_rn from Nvidia?" "Y"; then
                       print_color "$CYAN" "Downloading to $runfile_path...";
                       if run_command "wget --progress=bar:force:noscroll -O \"$runfile_path\" \"$runfile_570_url\"" true "Download $chosen_rn"; then
                           run_command "chown $SUDO_USER:$SUDO_USER \"$runfile_path\"" false "Chown downloaded runfile" || print_color "$YELLOW" "Warning: Failed to chown downloaded file."
                           print_color "$GREEN" "Download complete."; log_msg "INFO" "Downloaded $chosen_rn";
                       else
                           log_msg "ERROR" "Download failed for $chosen_rn"; runfile_path=""; # Reset path
                       fi
                   else
                       log_msg "USER" "Cancelled download."; runfile_path=""; # Reset path
                   fi
               else
                   print_color "$GREEN" "Found locally: $runfile_path"; log_msg "INFO" "Found local runfile: $runfile_path";
               fi
               ;; # End case 2
            3) # Manual Search
               local runfile_opts=(); declare -A runfile_map; local count=1;
               print_color "$CYAN" "\nSearching driver .run files in $USER_HOME..."; log_msg "INFO" "Searching runfiles in $USER_HOME."
               # Use find directly, handle potential errors
               local find_output; find_output=$(find "$USER_HOME" -maxdepth 1 -name 'NVIDIA-Linux-x86_64-*.run' -print0 2>/dev/null)
               if [[ -z "$find_output" ]]; then
                    print_color "$RED" "No driver .run files found in $USER_HOME search."; log_msg "WARN" "No other driver runfiles found in search.";
                    runfile_path=""; # Stay in loop
               else
                   while IFS= read -r -d $'\0' f; do
                       local bn; bn=$(basename "$f");
                       # Exclude CUDA runfiles from this list
                       if [[ "$bn" != "cuda_"* ]]; then
                           runfile_opts+=("$bn"); runfile_map[$count]="$bn"; ((count++));
                       fi;
                   done <<< "$find_output" # Process the find output

                   if [[ ${#runfile_opts[@]} -eq 0 ]]; then
                        print_color "$RED" "No non-CUDA driver .run files found in $USER_HOME search."; log_msg "WARN" "No non-CUDA driver runfiles found in search.";
                        runfile_path=""; # Stay in loop
                   else
                       print_color "$YELLOW" "Select driver runfile:";
                       for i in "${!runfile_map[@]}"; do echo " $i) ${runfile_map[$i]}" >&2; done;
                       local search_choice;
                       while [[ -z "$runfile_path" ]]; do
                           read -r -p "$(print_color "$YELLOW" "Choice: ")" search_choice < /dev/tty;
                           if [[ "$search_choice" =~ ^[0-9]+$ && -v "runfile_map[$search_choice]" ]]; then
                               chosen_rn="${runfile_map[$search_choice]}";
                               runfile_path="$USER_HOME/$chosen_rn";
                               log_msg "USER" "Selected Runfile from search: $runfile_path";
                           else
                               print_color "$RED" "Invalid selection from search.";
                           fi;
                       done;
                   fi
               fi
               ;; # End case 3
            4) # Cancel
               log_msg "USER" "Cancelled Runfile install."; return 1;;
            *) # Invalid
               print_color "$RED" "Invalid choice.";;
        esac
    done # End while loop for selecting runfile

    # --- Proceed with installation using selected runfile_path ---
    if [[ -z "$runfile_path" || ! -f "$runfile_path" ]]; then
         print_color "$RED" "ERROR: Invalid or missing runfile selected. Exiting.";
         log_msg "ERROR" "Runfile path invalid or file missing before install: $runfile_path";
         return 1;
    fi

    print_color "$CYAN" "\nStarting Runfile install using: $chosen_rn";
    chmod +x "$runfile_path" || { log_msg "ERROR" "chmod failed on $runfile_path"; return 1; }

    if ! check_tty; then return 1; fi
    local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for Runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

    print_color "$YELLOW" "Ensure Build Env (Menu 9 -> 2) & Nouveau blacklist (Menu 5) are done.";
    print_color "$YELLOW" "Also ensure correct GCC is default (Menu 9 -> 3).";
    print_color "$CYAN" "Running installer '$chosen_rn' with --dkms flag (INTERACTIVE)..."
    log_msg "EXEC" "$runfile_path --dkms"

    # Run interactively - run_command cannot handle interactive installers easily
    print_color "$PURPLE" "--- Starting Interactive Installer ---";
    # Ensure installer runs with correct permissions and reads from TTY
    if "$runfile_path" --dkms < /dev/tty ; then
        local run_status=$?; # Capture status immediately
        print_color "$PURPLE" "--- Interactive Installer Finished (Status: $run_status) ---";
        log_msg "INFO" "Runfile '$chosen_rn' finished status: $run_status.";

        if [[ $run_status -eq 0 ]]; then
            print_color "$CYAN" "Verifying DKMS status after successful install..."; log_msg "INFO" "Verifying DKMS after runfile install..."; sleep 2;
            local ver; ver=$(echo "$chosen_rn" | grep -oP '[0-9]+(\.[0-9]+){1,2}' | head -n1);
            local dkms_out; dkms_out=$(dkms status);
            log_msg "INFO" "DKMS Status after install: $dkms_out";
            local major_ver; major_ver=$(echo "$ver" | cut -d. -f1);
            if echo "$dkms_out" | grep -q "nvidia/${major_ver}"; then
                print_color "$GREEN" "DKMS module seems built for version ${major_ver}.x."; log_msg "INFO" "DKMS check PASSED (found nvidia/${major_ver}).";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else
                print_color "$RED" "ERROR: DKMS module for version $ver (or ${major_ver}.x) NOT found after supposedly successful install!";
                log_msg "ERROR" "DKMS check FAILED after runfile install (looking for $ver or ${major_ver}.x).";
                print_color "$YELLOW" "Check 'dkms status' and /var/log/nvidia-installer.log.";
                if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 1; # Return failure even if installer reported 0, because DKMS check failed
            fi
        else
             print_color "$RED" "ERROR: Runfile installer '$chosen_rn' reported failure! Status: $run_status";
             print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
             if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
             return $run_status;
        fi
    else
        local run_status=$?; # Capture status
        print_color "$PURPLE" "--- Interactive Installer Failed to Execute Properly (Status: $run_status) ---";
        log_msg "ERROR" "Runfile installer '$chosen_rn' execution failed. Status: $run_status."; print_color "$YELLOW" "Check /var/log/nvidia-installer.log";
        if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after Runfile fail" || print_color "$YELLOW" "Failed restart DM."; fi;
        return $run_status;
    fi
}
# FINISH ### NVIDIA INSTALL RUNFILE ###

# START ### HELPER INSTALL CUDA TOOLKIT APT CORE ###
# This function assumes Nvidia repo might already be configured.
# It only installs the toolkit package.
install_cuda_toolkit_apt_core() {
    local toolkit_pkg="cuda-toolkit" # Default, could be version specific like cuda-toolkit-12-2 if needed
    print_color "$CYAN" "\nInstalling CUDA Toolkit via APT ($toolkit_pkg)..."; log_msg "INFO" "Starting core CUDA APT install."

    # Ensure repo is configured before proceeding
    # Check if nvidia.com provides the package
    if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
         print_color "$YELLOW" "Nvidia repo doesn't seem to provide '$toolkit_pkg' or isn't configured/updated."
         if prompt_confirm "Attempt to configure Nvidia repo and update APT cache first?"; then
             # Run setup only, capture status
             local repo_setup_status=1
             install_nvidia_apt_official_repo "true"; repo_setup_status=$?
             if [[ $repo_setup_status -ne 0 ]]; then
                 print_color "$RED" "Nvidia repo setup failed. Cannot proceed reliably."; return 1;
             fi
             run_command "apt-get update" false "Update before CUDA core install" || { print_color "$RED" "APT update failed."; return 1; }
             # Re-check policy after update
             if ! apt-cache policy $toolkit_pkg | grep -q 'nvidia.com'; then
                  print_color "$YELLOW" "Warning: Nvidia repo still doesn't seem to provide '$toolkit_pkg' after setup/update.";
                  log_msg "WARN" "Nvidia repo doesn't provide $toolkit_pkg after setup attempt."
                  if ! prompt_confirm "Continue anyway (may install older Ubuntu version)?"; then return 1; fi
             fi
         else
             print_color "$YELLOW" "Proceeding without confirmed Nvidia repo. May install older version from Ubuntu repos.";
             log_msg "WARN" "Proceeding with CUDA toolkit install without confirmed Nvidia repo."
         fi
    else
         log_msg "INFO" "Confirmed $toolkit_pkg available from Nvidia repo."
    fi

    print_color "$CYAN" "Running: apt-get install $toolkit_pkg -y";
    if run_command "apt-get install $toolkit_pkg -y" true "Install CUDA Toolkit APT Core"; then
        log_msg "INFO" "CUDA APT install ($toolkit_pkg) finished."; print_color "$GREEN" "CUDA APT install finished."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
        local nvcc_path; nvcc_path=$(command -v nvcc || echo "/usr/local/cuda/bin/nvcc");
        if [[ -x "$nvcc_path" ]]; then
             local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
        else
             print_color "$YELLOW" "nvcc not found in PATH or default location. Update PATH/LD_LIBRARY_PATH."; log_msg "WARN" "nvcc check FAILED.";
        fi;
        print_color "$YELLOW" "Ensure PATH includes /usr/local/cuda/bin and LD_LIBRARY_PATH includes /usr/local/cuda/lib64 if needed.";
        return 0;
    else
        log_msg "ERROR" "apt-get install $toolkit_pkg failed."; return 1;
    fi
}
# FINISH ### HELPER INSTALL CUDA TOOLKIT APT CORE ###


# START ### MODULE CUDA INSTALL ###
run_cuda_install() {
    print_color "$PURPLE" "\n--- Module: CUDA Toolkit Install ---"; log_msg "INFO" "Starting CUDA Install.";
    # Simplified pre-check
    if ! nvidia-smi &> /dev/null; then
        log_msg "WARN" "nvidia-smi command failed. Is driver installed and running?";
        print_color "$RED" "WARN: nvidia-smi failed. Driver may be inactive.";
        if ! prompt_confirm "Continue CUDA install anyway (NOT Recommended)?"; then return 1; fi;
    else
        print_color "$GREEN" "nvidia-smi check passed."; log_msg "INFO" "nvidia-smi check passed.";
    fi
    local method="";
    local specific_cuda_runfile_name="cuda_12.2.2_535.104.05_linux.run"

    while true; do
        print_color "$YELLOW" "\nSelect CUDA install method:"
        echo "  1) APT ('cuda-toolkit' - Best if Nvidia Repo is configured)";
        echo "  2) Runfile (Check for '$specific_cuda_runfile_name' or search $USER_HOME)";
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty;
        case "$choice" in
            1) method="apt"; break;;
            2) method="runfile"; break;;
            *) print_color "$RED" "Invalid.";;
        esac
    done;
    log_msg "USER" "Selected CUDA method: $method"

    if [[ "$method" == "apt" ]]; then
        # Call the simplified core install function
        install_cuda_toolkit_apt_core; return $?;

    elif [[ "$method" == "runfile" ]]; then
        # (Keep existing runfile logic from v1.10 - it's already complex and functional)
        local chosen_cuda_runfile_path=""; local chosen_cuda_rn="";
        while [[ -z "$chosen_cuda_runfile_path" ]]; do
            print_color "$YELLOW" "\nSelect CUDA Runfile source:";
            echo " 1) Use $specific_cuda_runfile_name (Check $USER_HOME)";
            echo " 2) Search $USER_HOME for other cuda_*.run files";
            echo " 3) Cancel";
            read -r -p "$(print_color "$YELLOW" "Choice [1-3]: ")" cuda_choice < /dev/tty;
            case "$cuda_choice" in
                1) chosen_cuda_rn="$specific_cuda_runfile_name";
                   if [[ -f "$USER_HOME/$chosen_cuda_rn" ]]; then
                       chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; print_color "$GREEN" "Found locally: $chosen_cuda_runfile_path"; log_msg "INFO" "Found specific CUDA runfile: $chosen_cuda_runfile_path";
                   else print_color "$RED" "Specific file not found: $USER_HOME/$chosen_cuda_rn"; log_msg "WARN" "Specific CUDA runfile missing."; print_color "$YELLOW" "Please download manually or choose search."; fi ;; # Stay in loop
                2) local cuda_runfile_opts=(); declare -A cuda_runfile_map; local ccount=1;
                   print_color "$CYAN" "\nSearching CUDA .run files in $USER_HOME..."; log_msg "INFO" "Searching CUDA runfiles in $USER_HOME."
                   local cuda_find_output; cuda_find_output=$(find "$USER_HOME" -maxdepth 1 -name 'cuda_*_linux.run' -print0 2>/dev/null)
                   if [[ -z "$cuda_find_output" ]]; then print_color "$RED" "No CUDA .run files found in search."; log_msg "WARN" "No CUDA runfiles found in search.";
                   else
                        while IFS= read -r -d $'\0' f; do local bn; bn=$(basename "$f"); cuda_runfile_opts+=("$bn"); cuda_runfile_map[$ccount]="$bn"; ((ccount++)); done <<< "$cuda_find_output"
                       if [[ ${#cuda_runfile_opts[@]} -eq 0 ]]; then print_color "$RED" "Error processing found CUDA files."; log_msg "ERROR" "Processing find results for CUDA failed.";
                       else
                           print_color "$YELLOW" "Select CUDA runfile:";
                           for i in "${!cuda_runfile_map[@]}"; do echo " $i) ${cuda_runfile_map[$i]}" >&2; done;
                           local csearch_choice;
                           while [[ -z "$chosen_cuda_runfile_path" ]]; do
                               read -r -p "$(print_color "$YELLOW" "Choice: ")" csearch_choice < /dev/tty;
                               if [[ "$csearch_choice" =~ ^[0-9]+$ && -v "cuda_runfile_map[$csearch_choice]" ]]; then
                                   chosen_cuda_rn="${cuda_runfile_map[$csearch_choice]}"; chosen_cuda_runfile_path="$USER_HOME/$chosen_cuda_rn"; log_msg "USER" "Selected CUDA Runfile from search: $chosen_cuda_runfile_path";
                               else print_color "$RED" "Invalid selection."; fi;
                           done;
                        fi
                   fi ;; # End search logic
                3) log_msg "USER" "Cancelled CUDA Runfile install."; return 1;; *) print_color "$RED" "Invalid choice.";;
            esac
        done # End CUDA runfile selection loop

        # --- Proceed with CUDA Runfile Install ---
        if [[ -z "$chosen_cuda_runfile_path" || ! -f "$chosen_cuda_runfile_path" ]]; then print_color "$RED" "ERROR: Invalid CUDA runfile. Exiting."; log_msg "ERROR" "CUDA Runfile path invalid."; return 1; fi

        print_color "$CYAN" "\nInstalling CUDA via Runfile ($chosen_cuda_rn)..."; log_msg "INFO" "Starting CUDA Runfile install: $chosen_cuda_runfile_path"
        chmod +x "$chosen_cuda_runfile_path" || { log_msg "ERROR" "chmod CUDA runfile failed"; return 1; }
        if ! check_tty; then return 1; fi; local dm; dm=$(get_display_manager); if [[ -n "$dm" ]]; then run_command "systemctl stop $dm" false "Stop DM for CUDA runfile" || print_color "$YELLOW" "Warn: Stop DM failed."; fi

        print_color "$YELLOW" "Runfile Install Options (IMPORTANT!)";
        print_color "$YELLOW" " -> Answer 'accept' to EULA.";
        print_color "$RED"    " -> DESELECT the 'Driver' component if you already installed drivers separately.";
        print_color "$YELLOW" " -> Keep 'CUDA Toolkit' selected.";
        log_msg "INFO" "Instructed user on runfile options (deselect driver).";

        print_color "$CYAN" "Running CUDA Runfile '$chosen_cuda_rn' INTERACTIVELY..."; log_msg "EXEC" "$chosen_cuda_runfile_path";
        print_color "$PURPLE" "--- Starting Interactive CUDA Installer ---";
        if "$chosen_cuda_runfile_path" < /dev/tty ; then
            local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Finished (Status: $cuda_run_status) ---"; log_msg "INFO" "CUDA Runfile finished status $cuda_run_status.";
            if [[ $cuda_run_status -eq 0 ]]; then
                print_color "$GREEN" "CUDA Runfile finished successfully."; print_color "$CYAN" "Verifying nvcc..."; log_msg "INFO" "Verifying nvcc...";
                local cuda_base_path="/usr/local"; local latest_cuda_link="$cuda_base_path/cuda"; local nvcc_path="";
                if [[ -L "$latest_cuda_link" ]] && [[ -x "$latest_cuda_link/bin/nvcc" ]]; then nvcc_path="$latest_cuda_link/bin/nvcc";
                else local newest_cuda_dir; newest_cuda_dir=$(find "$cuda_base_path" -maxdepth 1 -name 'cuda-*' -type d -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-); if [[ -n "$newest_cuda_dir" ]] && [[ -x "$newest_cuda_dir/bin/nvcc" ]]; then nvcc_path="$newest_cuda_dir/bin/nvcc"; else nvcc_path="/usr/local/cuda/bin/nvcc"; fi; fi
                if [[ -x "$nvcc_path" ]]; then local nvcc_ver; nvcc_ver=$("$nvcc_path" --version | grep 'release'); print_color "$GREEN" "nvcc found at $nvcc_path: $nvcc_ver"; log_msg "INFO" "nvcc PASSED: $nvcc_path - $nvcc_ver";
                else print_color "$YELLOW" "nvcc not found. Update PATH/LD_LIB."; log_msg "WARN" "nvcc FAILED check."; fi;
                print_color "$YELLOW" "Ensure PATH/LD_LIBRARY_PATH are set if needed.";
                 if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA success" || print_color "$YELLOW" "Failed restart DM."; fi;
                return 0;
            else log_msg "ERROR" "CUDA Runfile failed status $cuda_run_status."; print_color "$RED" "CUDA Runfile Failed!"; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return 1; fi
        else local cuda_run_status=$?; print_color "$PURPLE" "--- Interactive CUDA Installer Failed Execution (Status: $cuda_run_status) ---"; log_msg "ERROR" "CUDA Runfile execution failed. Status: $cuda_run_status."; print_color "$YELLOW" "Check logs."; if [[ -n "$dm" ]]; then run_command "systemctl start $dm" false "Start DM after CUDA fail" || print_color "$YELLOW" "Failed restart DM."; fi; return $cuda_run_status; fi
    fi # End method if/elif
}
# FINISH ### MODULE CUDA INSTALL ###

# -------------------------------------------------------------
# END OF PART 3 - READY FOR PART 4
# -------------------------------------------------------------
# START ### GRUB CUSTOM BUILDER FUNCTION ###
run_grub_custom_builder() {
    local grub_def="/etc/default/grub"; local current_cmdline=""
    print_color "$PURPLE" "\n--- GRUB Custom Parameter Builder (Experimental) ---"; log_msg "INFO" "Starting GRUB Custom Builder."

    # Read current setting
    if [[ -f "$grub_def" ]]; then
        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_def" | cut -d'=' -f2 | sed 's/"//g')
        print_color "$CYAN" "Current GRUB_CMDLINE_LINUX_DEFAULT: \"$current_cmdline\""
        log_msg "INFO" "Current GRUB CMDLINE: $current_cmdline"
    else
        print_color "$RED" "Cannot read $grub_def!"; log_msg "ERROR" "Cannot read $grub_def in custom builder."; return 1;
    fi

    # Initialize parameters based on current settings or defaults
    local params; params=($current_cmdline) # Convert string to array
    local use_quiet="N"; [[ " ${params[@]} " =~ " quiet " ]] && use_quiet="Y"
    local use_splash="N"; [[ " ${params[@]} " =~ " splash " ]] && use_splash="Y"
    local use_nomodeset="N"; [[ " ${params[@]} " =~ " nomodeset " ]] && use_nomodeset="Y"
    local use_nvidiadrm="N"; [[ " ${params[@]} " =~ " nvidia-drm.modeset=1 " ]] && use_nvidiadrm="Y"
    local custom_params=""

    # Filter out the params we will toggle, keep others
    local other_params=()
    for p in "${params[@]}"; do
        if [[ "$p" != "quiet" && "$p" != "splash" && "$p" != "nomodeset" && "$p" != "nvidia-drm.modeset=1" ]]; then
            other_params+=("$p")
        fi
    done
    custom_params=$(echo "${other_params[@]}") # Join remaining params back into a string

    print_color "$YELLOW" "\nConfigure parameters (Current state shown):"
    prompt_confirm "Include 'quiet' parameter?" "$use_quiet"; [[ $? -eq 0 ]] && use_quiet="Y" || use_quiet="N"
    prompt_confirm "Include 'splash' parameter?" "$use_splash"; [[ $? -eq 0 ]] && use_splash="Y" || use_splash="N"
    prompt_confirm "Include 'nomodeset' parameter? (Disables most KMS drivers)" "$use_nomodeset"; [[ $? -eq 0 ]] && use_nomodeset="Y" || use_nomodeset="N"
    prompt_confirm "Include 'nvidia-drm.modeset=1' parameter? (Recommended for Nvidia)" "$use_nvidiadrm"; [[ $? -eq 0 ]] && use_nvidiadrm="Y" || use_nvidiadrm="N"

    print_color "$YELLOW" "\nCurrent other/custom parameters: $custom_params"
    read -r -p "$(print_color "$YELLOW" "Enter any ADDITIONAL custom parameters (space-separated, or leave blank): ")" additional_params < /dev/tty
    custom_params="$custom_params $additional_params"
    # Clean up potential double spaces and leading/trailing whitespace
    custom_params=$(echo "$custom_params" | tr -s ' ' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Build the new command line
    local new_cmdline_array=()
    [[ "$use_quiet" == "Y" ]] && new_cmdline_array+=("quiet")
    [[ "$use_splash" == "Y" ]] && new_cmdline_array+=("splash")
    [[ "$use_nomodeset" == "Y" ]] && new_cmdline_array+=("nomodeset")
    [[ "$use_nvidiadrm" == "Y" ]] && new_cmdline_array+=("nvidia-drm.modeset=1")
    # Add custom params if not empty
    [[ -n "$custom_params" ]] && new_cmdline_array+=($custom_params) # Add as separate elements

    local new_cmdline; new_cmdline=$(echo "${new_cmdline_array[@]}") # Join with spaces

    print_color "$PURPLE" "\n--- Generated Config Line ---"
    print_color "$CYAN" "GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\""
    log_msg "INFO" "Custom GRUB CMDLINE generated: $new_cmdline"
    print_color "$PURPLE" "---------------------------"

    if ! prompt_confirm "Apply this custom config line to $grub_def?"; then
        log_msg "USER" "Cancelled custom GRUB apply."; return 1
    fi

    # Apply the changes
    local grub_bak="/etc/default/grub.custom_backup.$(date +%s)"
    print_color "$YELLOW" "Backing up current config to $grub_bak..."
    if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Custom"; then
        log_msg "ERROR" "Custom GRUB backup failed."; return 1
    fi

    print_color "$CYAN" "Applying custom config line using sed...";
    local escaped_cmdline; escaped_cmdline=$(sed 's/[&/\]/\\&/g' <<< "$new_cmdline") # Basic escaping for sed
    if run_command "sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$escaped_cmdline\"|' \"$grub_def\"" false "Apply Custom Grub Line"; then
        log_msg "INFO" "Applied custom GRUB config line ok.";
        print_color "$CYAN" "Running update-grub...";
        if run_command "update-grub" true "update-grub after custom config"; then
            print_color "$GREEN" "Custom GRUB config applied and updated."; log_msg "INFO" "Custom GRUB updated ok."; return 0;
        else
            log_msg "ERROR" "update-grub failed after custom config."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1;
        fi
    else
        log_msg "ERROR" "Failed to apply custom config line using sed."; return 1
    fi
}
# FINISH ### GRUB CUSTOM BUILDER FUNCTION ###

# START ### GRUB FIX FUNCTION ###
run_grub_fix() {
    print_color "$PURPLE" "\n--- Module: GRUB Configuration Fix ---"; log_msg "INFO" "Starting GRUB Fix."
    local grub_def="/etc/default/grub"; local grub_bak="/etc/default/grub.preset_backup.$(date +%s)"; local cfg=""; local cfg_name="";
    print_color "$YELLOW" "Select GRUB action:";
    echo " 1) Apply Standard Default (quiet splash)";
    echo " 2) Apply Verbose Boot (no quiet splash)";
    echo " 3) Apply Failsafe (nomodeset)";
    echo " 4) Apply Std + Nvidia DRM Modeset (quiet splash nvidia-drm.modeset=1)";
    echo " 5) Apply Verbose + Nvidia DRM Modeset (nvidia-drm.modeset=1)";
    echo " 6) Custom Parameter Builder (Experimental)";
    echo " 7) Reinstall GRUB (EFI)";
    echo " 8) Cancel";
    read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty;
    case "$choice" in
        1) cfg_name="Standard"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Standard
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
# Add other GRUB settings below if needed, ensuring they don't conflict
GRUBEOF
) ;; # END Standard Preset
        2) cfg_name="Verbose"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose Preset
        3) cfg_name="Failsafe (nomodeset)"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Failsafe
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Failsafe Preset
        4) cfg_name="Std + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Std+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUBEOF
) ;; # END Std+DRM Preset
        5) cfg_name="Verbose + Nvidia DRM Modeset"; cfg=$(cat <<'GRUBEOF'
# GRUB config generated by nvidia-mybitch.sh Preset: Verbose+DRM
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUBEOF
) ;; # END Verbose+DRM Preset
        6) run_grub_custom_builder; return $? ;; # Call Custom Builder
        7) print_color "$CYAN" "Selected: Reinstall GRUB (EFI)."; log_msg "USER" "Selected GRUB Reinstall."
           if ! mount | grep -q /boot/efi; then
                print_color "$YELLOW" "Warning: /boot/efi does not seem to be mounted."
                if ! prompt_confirm "Attempt to mount EFI partition and continue? (Requires knowing EFI partition)"; then return 1; fi
                 efi_part=$(findmnt -n -o SOURCE --target /boot/efi || lsblk -o NAME,PARTLABEL | grep -i EFI | awk '{print "/dev/"$1}' | head -n1)
                 if [[ -z "$efi_part" ]]; then print_color "$RED" "Could not determine EFI partition automatically."; return 1; fi
                 if ! run_command "mount $efi_part /boot/efi" true "Mount EFI"; then print_color "$RED" "Failed to mount EFI partition."; return 1; fi
           fi
           if prompt_confirm "Run 'grub-install --recheck' (Assumes /boot/efi is correctly mounted)?"; then
               if run_command "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck" true "grub-install"; then
                   log_msg "INFO" "grub-install ok."; print_color "$CYAN" "Running update-grub...";
                   if run_command "update-grub" true "update-grub"; then log_msg "INFO" "update-grub ok."; return 0; else log_msg "ERROR" "update-grub failed."; return 1; fi
               else log_msg "ERROR" "grub-install failed."; return 1; fi
           else log_msg "USER" "Cancelled GRUB reinstall."; return 1; fi ;; # END GRUB Reinstall
        8) print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled GRUB fix."; return 1 ;; # END Cancel
        *) print_color "$RED" "Invalid."; return 1 ;;
    esac
    # Logic to apply the selected preset (if cfg is set)
    if [[ -n "$cfg" ]]; then
        print_color "$CYAN" "\nSelected Config Preset: $cfg_name"; print_color "$PURPLE" "--- Config ---"; print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$cfg"; print_color "$PURPLE" "--------------"; log_msg "INFO" "Applying GRUB preset: $cfg_name"
        if prompt_confirm "Apply this preset to $grub_def (OVERWRITES ENTIRE FILE)?"; then
            print_color "$YELLOW" "Backing up $grub_def to $grub_bak..."; if ! run_command "cp -a \"$grub_def\" \"$grub_bak\"" false "Backup GRUB Preset"; then log_msg "ERROR" "Backup failed."; return 1; fi
            print_color "$CYAN" "Writing preset config...";
            # Overwrite the file with the heredoc content
            if echo "$cfg" | sudo tee "$grub_def" > /dev/null; then # Ensure using sudo for tee
                 sudo chown root:root "$grub_def" && sudo chmod 644 "$grub_def"
                log_msg "INFO" "Wrote preset config ok."; print_color "$CYAN" "Running update-grub...";
                if run_command "update-grub" true "update-grub after preset"; then print_color "$GREEN" "GRUB updated successfully."; log_msg "INFO" "GRUB updated ok."; return 0;
                else log_msg "ERROR" "update-grub failed."; print_color "$YELLOW" "Restore backup: sudo cp \"$grub_bak\" \"$grub_def\" && sudo update-grub"; return 1; fi
            else log_msg "ERROR" "Write preset config failed."; return 1; fi
        else log_msg "USER" "Cancelled GRUB preset apply."; return 1; fi
    fi;
    return 0; # Should only be reached if choice was handled (e.g. custom builder)
}
# FINISH ### GRUB FIX FUNCTION ###

# START ### MODULE KERNEL FIX ###
run_kernel_fix() {
    print_color "$PURPLE" "\n--- Module: Kernel Reset ---"; log_msg "INFO" "Starting Kernel Reset."
    print_color "$YELLOW" "Removes & reinstalls a specific kernel version. USE CAUTION.";
    print_color "$YELLOW" "Ensure you are booted into a DIFFERENT, WORKING kernel.";
    local current_k; current_k=$(uname -r); log_msg "INFO" "Current kernel: $current_k"; print_color "$CYAN" "Currently running kernel: $current_k"

    print_color "$CYAN" "\nIdentifying installed kernel images..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
    # Get kernel versions from image packages
     while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1; fi

    print_color "$YELLOW" "\nSelect kernel version to reset:"
    for i in "${!kernel_map[@]}"; do
        local status_flag=""
        [[ "${kernel_map[$i]}" == "$current_k" ]] && status_flag=" (Currently Running - Cannot Reset)"
        echo " $i) ${kernel_map[$i]}$status_flag" >&2
    done
    echo " $((count))) Cancel" >&2

    local choice; local kernel_to_fix=""
    while [[ -z "$kernel_to_fix" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                if [[ "${kernel_map[$choice]}" == "$current_k" ]]; then
                     print_color "$RED" "Cannot reset the currently running kernel ($current_k)."; log_msg "WARN" "Attempted to reset running kernel.";
                else
                     kernel_to_fix="${kernel_map[$choice]}"
                fi
            elif [[ "$choice" -eq "$count" ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled kernel reset selection."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected kernel to reset: $kernel_to_fix"
    print_color "$RED" "\nWARNING: This will PURGE packages for kernel $kernel_to_fix"
    print_color "$RED" "         (image, headers, modules, modules-extra)"
    print_color "$RED" "         and then attempt to REINSTALL them."
    if ! prompt_confirm "Are you absolutely sure? You are booted from $current_k."; then log_msg "USER" "Cancelled kernel reset confirmation."; return 1; fi

    print_color "$CYAN" "\nStep 1: Purging packages for kernel $kernel_to_fix...";
    local purge_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix} linux-modules-${kernel_to_fix} linux-modules-extra-${kernel_to_fix}"
    if run_command "apt-get purge --autoremove -y $purge_pkgs" true "Purge Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix purged ok."; else log_msg "ERROR" "Kernel purge failed."; print_color "$YELLOW" "Attempting fix..."; run_command "dpkg --configure -a" false "dpkg configure"; run_command "apt-get install -f -y" true "apt fix"; return 1; fi

    print_color "$CYAN" "\nStep 2: Updating GRUB after purge..."; run_command "update-grub" true "Update GRUB after purge" || log_msg "ERROR" "update-grub failed after purge."

    print_color "$CYAN" "\nStep 3: Reinstalling kernel $kernel_to_fix packages...";
    local install_pkgs="linux-image-${kernel_to_fix} linux-headers-${kernel_to_fix}"
    # Determine if HWE meta-package should be reinstalled (simple check)
    local install_cmd="apt-get update && apt-get install -y $install_pkgs"
    if [[ "$kernel_to_fix" == *-hwe-* ]]; then
        local os_release; os_release=$(lsb_release -sr) # Get release number e.g., 22.04
        if [[ -n "$os_release" ]]; then
            local hwe_pkg="linux-generic-hwe-${os_release}"
            print_color "$CYAN" "Attempting to reinstall HWE meta-package ($hwe_pkg) as well..."
            install_cmd+=" && apt-get install -y $hwe_pkg"
        else
             print_color "$YELLOW" "Could not determine OS release for HWE package."
        fi
    fi
    if run_command "$install_cmd" true "Reinstall Kernel $kernel_to_fix"; then log_msg "INFO" "Kernel $kernel_to_fix reinstall ok."; else log_msg "ERROR" "Kernel reinstall failed."; return 1; fi

    print_color "$GREEN" "\n--- Kernel Reset Complete for $kernel_to_fix ---";
    print_color "$YELLOW" "Reboot required to boot into the reinstalled kernel."; log_msg "INFO" "Kernel Reset finished."; return 0
}
# FINISH ### MODULE KERNEL FIX ###

# START ### MODULE CHROOT HELPER ###
run_chroot_helper() {
    print_color "$PURPLE" "\n--- Module: Chroot Helper (For booting from Live USB/ISO) ---"; log_msg "INFO" "Starting Chroot Helper.";
    print_color "$YELLOW" "This helps mount your installed system and chroot into it.";
    print_color "$YELLOW" "USE THIS ONLY WHEN BOOTED FROM A LIVE ENVIRONMENT.";

    # Basic check for live environment
    if mountpoint -q /cdrom || grep -q -E 'casper|toram|live' /proc/cmdline; then log_msg "INFO" "Live environment detected."; else print_color "$RED" "Warning: Doesn't look like a standard Live environment."; log_msg "WARN" "Not Live OS?"; if ! prompt_confirm "Are you sure you are booted from a Live USB/ISO?"; then return 1; fi; fi

    local root_part=""; local efi_part=""; local swap_part=""; local mount_p="/mnt/mybitch_chroot"; local binds=( "/dev" "/dev/pts" "/proc" "/sys" "/run" )
    print_color "$CYAN" "\nIdentifying partitions (lsblk)..."; lsblk -f >&2;
    print_color "$YELLOW" "\nEnter the device paths for your installed system:"
    while true; do read -r -p "$(print_color "$YELLOW" " -> ROOT partition (e.g., /dev/nvme0n1p2 or /dev/sda3): ")" root_part < /dev/tty; if [[ -b "$root_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    while true; do read -r -p "$(print_color "$YELLOW" " -> EFI partition (e.g., /dev/nvme0n1p1 or /dev/sda1): ")" efi_part < /dev/tty; if [[ -b "$efi_part" ]]; then break; else print_color "$RED" "Invalid block device."; fi; done;
    read -r -p "$(print_color "$YELLOW" " -> SWAP partition (optional, e.g., /dev/sda2 or blank): ")" swap_part < /dev/tty; if [[ -n "$swap_part" && ! -b "$swap_part" ]]; then print_color "$RED" "Invalid block device for swap, ignoring."; swap_part=""; fi

    log_msg "USER" "Chroot Target - Root: $root_part, EFI: $efi_part, Swap: ${swap_part:-none}."

    print_color "$CYAN" "\nUnmounting previous attempts at $mount_p..."; umount -R "$mount_p" &>/dev/null; sleep 1; rm -rf "$mount_p"; # Clean up dir too
    print_color "$CYAN" "Mounting target system..."
    mkdir -p "$mount_p" || { log_msg "ERROR" "mkdir $mount_p fail"; return 1; }
    mount "$root_part" "$mount_p" || { log_msg "ERROR" "mount root $root_part fail"; rm -rf "$mount_p"; return 1; };
    mkdir -p "$mount_p/boot/efi" || { log_msg "ERROR" "mkdir $mount_p/boot/efi fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    mount "$efi_part" "$mount_p/boot/efi" || { log_msg "ERROR" "mount efi $efi_part fail"; umount "$mount_p"; rm -rf "$mount_p"; return 1; }
    if [[ -n "$swap_part" ]]; then
         print_color "$CYAN" "Activating swap partition $swap_part...";
         run_command "swapon $swap_part" false "Activate Swap" || print_color "$YELLOW" "Warning: Failed to activate swap.";
    fi

    print_color "$CYAN" "Binding system directories for chroot..."; local bind_f=0;
    for p in "${binds[@]}"; do
        # Ensure target directory exists within the mount point
        mkdir -p "$mount_p$p";
        if ! mount --bind "$p" "$mount_p$p"; then log_msg "ERROR" "Bind $p fail"; bind_f=1; print_color "$RED" " ERROR: Bind $p fail!"; fi;
    done;

    if [[ $bind_f -eq 1 ]]; then print_color "$YELLOW" "One or more binds failed. Chroot environment may be incomplete."; else print_color "$GREEN" "System binds successful."; fi

    print_color "$CYAN" "Copying DNS info (/etc/resolv.conf)...";
    # Handle cases where resolv.conf might be a broken symlink in the chroot target
    if [[ -L "$mount_p/etc/resolv.conf" ]]; then
        run_command "rm \"$mount_p/etc/resolv.conf\"" false "Remove resolv.conf symlink"
    fi
    if cp --dereference /etc/resolv.conf "$mount_p/etc/resolv.conf"; then print_color "$GREEN" "DNS info copied."; else log_msg "WARN" "DNS copy failed."; print_color "$YELLOW" "Warning: Failed to copy DNS info."; fi

    print_color "$GREEN" "\nTarget system mounted successfully at $mount_p.";
    print_color "$YELLOW" "Entering chroot environment. Type 'exit' or press Ctrl+D when finished.";
    print_color "$CYAN" "Inside chroot, you can run commands like 'apt update', 'update-grub', etc.";
    read -r -p "$(print_color "$YELLOW" "Press Enter to enter chroot...")" < /dev/tty

    log_msg "EXEC" "chroot $mount_p /bin/bash";
    # Use a more complete chroot environment setup
    chroot "$mount_p" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(chroot) \u@\h:\w\$ ' PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash --login +h
    local chroot_st=$?; log_msg "INFO" "Exited chroot status $chroot_st."

    print_color "$PURPLE" "\n--- Exited Chroot Environment ---";
    print_color "$YELLOW" "IMPORTANT: Filesystem is still mounted!";
    print_color "$YELLOW" "Unmount manually when finished using commands like:";
    print_color "$CYAN" "   sudo umount -R \"$mount_p\"";
    print_color "$YELLOW" "(If recursive unmount fails, unmount binds individually then base mounts)";
    print_color "$CYAN" "   (e.g., sudo umount \"$mount_p/dev/pts\" \"$mount_p/dev\" ...etc... )"
    print_color "$CYAN" "   (then sudo umount \"$mount_p/boot/efi\" \"$mount_p\" )"
    if [[ -n "$swap_part" ]]; then print_color "$CYAN" "   sudo swapoff $swap_part"; fi
    return 0
}
# FINISH ### MODULE CHROOT HELPER ###

# START ### MODULE VIEW LOGS ###
run_view_logs() {
    print_color "$PURPLE" "\n--- Module: Log Viewer ---"; log_msg "INFO" "Starting Log Viewer."
    while true; do
        # Clear screen for better readability
        if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
        print_color "$GREEN" "\nSelect log file or command to view:"
        echo " 1) Nvidia/CUDA Installer Log (/var/log/nvidia-installer.log or /var/log/cuda-installer.log)";
        echo " 2) DKMS Build Logs (Latest Nvidia Build)";
        echo " 3) APT History Log (/var/log/apt/history.log)";
        echo " 4) APT Terminal Log (/var/log/apt/term.log)";
        echo " 5) Xorg Log (/var/log/Xorg.0.log)";
        echo " 6) Xorg Log (Previous) (/var/log/Xorg.0.log.old)";
        echo " 7) Journalctl: Current Boot Errors (-b 0 -p err)";
        echo " 8) Journalctl: Previous Boot Errors (-b -1 -p err)";
        echo " 9) Journalctl: Kernel Messages (-k)";
        echo "10) This Script's Main Log ($MAIN_LOG_FILE)";
        echo "11) Back to Main Menu";
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-11]: ")" choice < /dev/tty

        case "$choice" in
            1) if [[ -f /var/log/cuda-installer.log ]]; then view_log_file "/var/log/cuda-installer.log" "CUDA Installer"; elif [[ -f /var/log/nvidia-installer.log ]]; then view_log_file "/var/log/nvidia-installer.log" "Nvidia Installer"; else print_color "$YELLOW" "No Nvidia/CUDA installer log found in /var/log."; log_msg "WARN" "No Nvidia/CUDA installer log found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty; fi ;;
            2) local latest_dkms; local k_v; k_v=$(uname -r);
               print_color "$CYAN" "Searching for latest Nvidia DKMS build log..."
               # Find the most recently modified make.log within any nvidia/*/KERNEL/ structure
               latest_dkms=$(find /var/lib/dkms/nvidia/ -name "make.log" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
               if [[ -n "$latest_dkms" ]]; then
                    view_log_file "$latest_dkms" "Latest DKMS Build ($(basename "$(dirname "$(dirname "$latest_dkms")")"))";
               else
                    print_color "$YELLOW" "No Nvidia DKMS make.log files found."; log_msg "WARN" "No Nvidia DKMS logs found."; read -r -p "$(print_color "$YELLOW" "Press Enter...")" < /dev/tty;
               fi ;;
            3) view_log_file "/var/log/apt/history.log" "APT History";;
            4) view_log_file "/var/log/apt/term.log" "APT Terminal";;
            5) view_log_file "/var/log/Xorg.0.log" "Current Xorg Log";;
            6) view_log_file "/var/log/Xorg.0.log.old" "Previous Xorg Log";;
            7) print_color "$CYAN" "Showing current boot errors (journalctl -b 0 -p err)..."; journalctl --no-pager -b 0 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            8) print_color "$CYAN" "Showing previous boot errors (journalctl -b -1 -p err)..."; journalctl --no-pager -b -1 -p err < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
            9) print_color "$CYAN" "Showing kernel messages for current boot (journalctl -k)..."; journalctl --no-pager -k < /dev/tty ; read -r -p "$(print_color "$YELLOW" "\nPress Enter to continue...")" < /dev/tty ;;
           10) view_log_file "$MAIN_LOG_FILE" "This Script Log";;
           11) log_msg "INFO" "Exiting Log Viewer."; break;;
            *) print_color "$RED" "Invalid selection." ;;
        esac;
        # No automatic pause needed here as view_log_file pauses, and journalctl commands have manual pause
    done; return 0;
}
# FINISH ### MODULE VIEW LOGS ###

# START ### UPDATE INITRAMFS FUNCTION ###
run_update_initramfs() {
    print_color "$PURPLE" "\n--- Module: Update Initramfs ---"; log_msg "INFO" "Starting Update Initramfs."
    print_color "$CYAN" "Identifying installed kernel versions..."
    local kernels=(); local kernel_map; declare -A kernel_map; local count=1;

    # Find installed kernel images and populate map
    while IFS= read -r k_image; do
        local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//')
        local found=0
        for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done
        if [[ $found -eq 0 && -n "$k_ver" ]]; then # Ensure k_ver is not empty
             kernels+=("$k_ver")
             kernel_map[$count]="$k_ver"
             ((count++))
        fi
    done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)

    if [[ ${#kernels[@]} -eq 0 ]]; then
        print_color "$RED" "ERROR: No kernel images found!"; log_msg "ERROR" "No kernels found via dpkg."; return 1;
    fi

    print_color "$YELLOW" "Select kernel to update initramfs for:"
    for i in "${!kernel_map[@]}"; do
        echo " $i) ${kernel_map[$i]}" >&2
    done
    echo " $((count))) all (Update all installed kernels)" >&2
    echo " $((count+1))) Cancel" >&2

    local choice; local target_k=""
    while [[ -z "$target_k" ]]; do
        read -r -p "$(print_color "$YELLOW" "Choice: ")" choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$count" ]]; then
                target_k="${kernel_map[$choice]}"
            elif [[ "$choice" -eq "$count" ]]; then
                target_k="all"
            elif [[ "$choice" -eq $((count+1)) ]]; then
                print_color "$YELLOW" "Cancelled."; log_msg "USER" "Cancelled initramfs update."; return 1
            else
                 print_color "$RED" "Invalid selection."
            fi
        else
             print_color "$RED" "Invalid input."
        fi
    done

    log_msg "USER" "Selected initramfs update target: $target_k"
    print_color "$CYAN" "Running update-initramfs -u for kernel(s): $target_k...";

    if run_command "update-initramfs -u -k $target_k" true "Update Initramfs $target_k"; then
        print_color "$GREEN" "Initramfs update successful for $target_k."; log_msg "INFO" "Initramfs update ok: $target_k."
        return 0
    else
        print_color "$RED" "Initramfs update failed for $target_k."; log_msg "ERROR" "Initramfs update FAILED: $target_k.";
        return 1
    fi
}
# FINISH ### UPDATE INITRAMFS FUNCTION ###

# START ### NETWORK FIX FUNCTION ###
run_network_fix() {
    print_color "$PURPLE" "\n--- Module: Network Troubleshooting ---"; log_msg "INFO" "Starting Network Fix Module."
    print_color "$YELLOW" "This attempts common fixes for network issues, especially in CLI."

    while true; do
        print_color "$GREEN" "\nNetwork Troubleshooting Options:"
        echo " 1) Check NetworkManager Status"
        echo " 2) Restart NetworkManager Service"
        echo " 3) Show Network Devices (ip link/addr)"
        echo " 4) Show Recent Network Kernel Logs (dmesg/journalctl)"
        echo " 5) Apply Netplan Configuration"
        echo " 6) Check DNS Configuration (/etc/resolv.conf & systemd-resolved)"
        echo " 7) Check/Reinstall linux-firmware package"
        echo " 8) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-8]: ")" choice < /dev/tty

        case "$choice" in
            1) print_color "$CYAN" "Checking NetworkManager status...";
               run_command "systemctl status NetworkManager.service --no-pager" false "NetworkManager Status";; # Added --no-pager
            2) print_color "$CYAN" "Attempting to restart NetworkManager...";
               if run_command "systemctl restart NetworkManager.service" false "Restart NetworkManager"; then
                   print_color "$GREEN" "NetworkManager restarted. Check status (Option 1) or test connection (e.g., ping 8.8.8.8).";
               else
                   print_color "$RED" "Failed to restart NetworkManager.";
               fi ;;
            3) print_color "$CYAN" "Showing network links (ip link show)...";
               run_command "ip link show" false "Show IP Links";
               print_color "$CYAN" "\nShowing network addresses (ip addr show)...";
               run_command "ip addr show" false "Show IP Addresses";;
            4) print_color "$CYAN" "Showing recent kernel messages related to network/firmware (last 50 lines)...";
               if command -v journalctl &> /dev/null; then
                    print_color "$CYAN" "(Using journalctl -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    journalctl --no-pager -k | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via journalctl."
               else
                    print_color "$CYAN" "(Using dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50)"
                    dmesg | grep -Ei 'net|eth|wlan|r8169|iwlwifi|firmware|ath|btusb|bluetooth' | tail -n 50 < /dev/tty
                    log_msg "INFO" "Displayed recent network kernel messages via dmesg."
               fi
               ;;
            5) if command -v netplan &> /dev/null; then
                   print_color "$CYAN" "Attempting to apply Netplan configuration (sudo netplan apply)...";
                   if run_command "netplan apply" true "Apply Netplan"; then # Log output in case of errors
                       print_color "$GREEN" "Netplan configuration applied. Check network status.";
                   else
                       print_color "$RED" "Failed to apply Netplan configuration. Check output/logs.";
                   fi
               else
                   print_color "$YELLOW" "netplan command not found. This system likely doesn't use Netplan. Skipping.";
                   log_msg "WARN" "netplan command not found.";
               fi ;;
            6) print_color "$CYAN" "Checking DNS settings (/etc/resolv.conf)...";
               if [[ -f "/etc/resolv.conf" ]]; then
                   run_command "cat /etc/resolv.conf" false "Show resolv.conf";
                   if [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink -f /etc/resolv.conf)" == */systemd/resolve/stub-resolv.conf ]]; then
                        print_color "$CYAN" "DNS appears managed by systemd-resolved. Checking service status...";
                        run_command "systemctl status systemd-resolved.service --no-pager" false "systemd-resolved status";
                   elif [[ -L "/etc/resolv.conf" ]] && [[ "$(readlink /etc/resolv.conf)" == *run/NetworkManager/resolv.conf* ]]; then
                         print_color "$CYAN" "DNS appears managed by NetworkManager directly (using resolvconf?).";
                         print_color "$CYAN" "Check NetworkManager status (Option 1) and logs.";
                   elif [[ -L "/etc/resolv.conf" ]]; then
                        print_color "$CYAN" "DNS is a symlink to: $(readlink /etc/resolv.conf)";
                   else
                         print_color "$CYAN" "/etc/resolv.conf is a static file.";
                   fi
               else
                   print_color "$YELLOW" "/etc/resolv.conf not found.";
                   log_msg "WARN" "/etc/resolv.conf not found";
               fi ;;
            7) print_color "$CYAN" "Checking 'linux-firmware' package...";
                if dpkg-query -W -f='${Status}' linux-firmware 2>/dev/null | grep -q "ok installed"; then
                     print_color "$GREEN" "'linux-firmware' package is installed.";
                     log_msg "INFO" "linux-firmware package installed.";
                     if prompt_confirm "Reinstall 'linux-firmware' anyway (can take a while)?"; then
                        if run_command "apt-get update && apt-get install --reinstall -y linux-firmware" true "Reinstall linux-firmware"; then
                             print_color "$GREEN" "Reinstalled linux-firmware. A reboot might be needed."; log_msg "INFO" "Reinstalled linux-firmware.";
                        else
                             print_color "$RED" "Failed to reinstall linux-firmware."; log_msg "ERROR" "Failed reinstall linux-firmware";
                        fi
                     fi
                else
                     print_color "$YELLOW" "'linux-firmware' package NOT installed. This could cause hardware issues.";
                     log_msg "WARN" "linux-firmware package not installed.";
                      if prompt_confirm "Install 'linux-firmware' package (required for many devices)?"; then
                        if run_command "apt-get update && apt-get install -y linux-firmware" true "Install linux-firmware"; then
                             print_color "$GREEN" "Installed linux-firmware."; log_msg "INFO" "Installed linux-firmware.";
                             print_color "$YELLOW" "A reboot might be needed for firmware changes.";
                        else
                             print_color "$RED" "Failed to install linux-firmware."; log_msg "ERROR" "Failed install linux-firmware";
                        fi
                     fi
                fi ;;

            8) log_msg "INFO" "Exiting Network Fix module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         local last_status=$?
         # Pause only if an action was attempted (excluding exit/invalid)
         if [[ "$choice" =~ ^[1-7]$ ]]; then
             if [[ "$choice" =~ ^[1346]$ && $last_status -eq 0 ]]; then # Only show basic success for checks
                 print_color "$GREEN" "\nCheck complete.";
             elif [[ $last_status -ne 0 ]]; then
                  # Error message already printed by run_command
                  print_color "$YELLOW" "\nOperation finished with status $last_status.";
             else
                  # Successful operation (like restart, apply, install)
                  print_color "$GREEN" "\nOperation finished successfully.";
             fi
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Network menu...")" < /dev/tty
         fi
    done
    return 0
}
# FINISH ### NETWORK FIX FUNCTION ###

# START ### KERNEL PINNING FUNCTION ###
run_kernel_pinning() {
    print_color "$PURPLE" "\n--- Module: Kernel Package Pinning ---"; log_msg "INFO" "Starting Kernel Pinning Module."
    local pin_file="/etc/apt/preferences.d/99-mybitch-kernel-pin"

    while true; do
        print_color "$YELLOW" "\nKernel Pinning Options:";
        echo " 1) Pin to CURRENTLY RUNNING Kernel ($(uname -r))"
        echo " 2) Pin to a SPECIFIC Installed Kernel"
        echo " 3) View Current Pinning File ($pin_file)"
        echo " 4) Remove Pinning File ($pin_file)"
        echo " 5) Back to Previous Menu"
        local choice; read -r -p "$(print_color "$YELLOW" "Choice [1-5]: ")" choice < /dev/tty

        case "$choice" in
            1) target_k=$(uname -r);
               if [[ -z "$target_k" ]]; then print_color "$RED" "Could not determine current kernel."; continue; fi
               print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $target_k.";
               if prompt_confirm "Create/overwrite pinning file for $target_k?"; then
                  generate_and_apply_pin "$target_k" "$pin_file"
               fi
               ;;
            2) # List installed kernels for selection
               print_color "$CYAN" "Identifying installed kernel versions..."
               local kernels=(); local kernel_map; declare -A kernel_map; local count=1;
               while IFS= read -r k_image; do local k_ver; k_ver=$(echo "$k_image" | sed 's/^linux-image-//'); local found=0; for existing_ver in "${kernels[@]}"; do if [[ "$existing_ver" == "$k_ver" ]]; then found=1; break; fi; done; if [[ $found -eq 0 && -n "$k_ver" ]]; then kernels+=("$k_ver"); kernel_map[$count]="$k_ver"; ((count++)); fi; done < <(dpkg -l | grep -E '^ii.*linux-image-[0-9]' | awk '{print $2}' | sort -V)
               if [[ ${#kernels[@]} -eq 0 ]]; then print_color "$RED" "ERROR: No kernels found!"; log_msg "ERROR" "No kernels found for pinning."; continue; fi

               print_color "$YELLOW" "Select kernel version to pin TO:"
               for i in "${!kernel_map[@]}"; do echo " $i) ${kernel_map[$i]}" >&2; done; echo " $((count))) Cancel" >&2;
               local pin_choice; local selected_k=""
               while [[ -z "$selected_k" ]]; do read -r -p "$(print_color "$YELLOW" "Choice: ")" pin_choice < /dev/tty; if [[ "$pin_choice" =~ ^[0-9]+$ ]]; then if [[ "$pin_choice" -ge 1 && "$pin_choice" -lt "$count" ]]; then selected_k="${kernel_map[$pin_choice]}"; elif [[ "$pin_choice" -eq "$count" ]]; then print_color "$YELLOW" "Cancelled."; selected_k="cancel"; else print_color "$RED" "Invalid."; fi; else print_color "$RED" "Invalid."; fi; done
               if [[ "$selected_k" != "cancel" ]]; then
                    print_color "$CYAN" "Will pin packages to prevent upgrades beyond kernel $selected_k.";
                    if prompt_confirm "Create/overwrite pinning file for $selected_k?"; then
                        generate_and_apply_pin "$selected_k" "$pin_file"
                    fi
               fi
               ;;
            3) print_color "$CYAN" "Contents of $pin_file:";
               if [[ -f "$pin_file" ]]; then run_command "cat $pin_file" false "View Pin File"; else print_color "$YELLOW" "Pin file does not exist."; fi
               ;;
            4) print_color "$YELLOW" "Removing kernel pinning file: $pin_file";
               if [[ ! -f "$pin_file" ]]; then print_color "$YELLOW" "Pin file does not exist."; continue; fi;
               if prompt_confirm "Remove the pinning file? (Allows kernel upgrades)"; then
                   if run_command "rm -vf $pin_file" false "Remove Pin File"; then
                       print_color "$GREEN" "Pin file removed. Run 'sudo apt update' for changes to take effect."; log_msg "INFO" "Removed pin file $pin_file."
                       run_command "apt-get update" false "Update APT after pin removal"
                   else
                       log_msg "ERROR" "Failed to remove pin file.";
                   fi
               fi
               ;;
            5) log_msg "INFO" "Exiting Kernel Pinning module."; break;;
            *) print_color "$RED" "Invalid selection.";;
        esac
         # Add pause after actions
         if [[ "$choice" =~ ^[1-4]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to Pinning menu...")" < /dev/tty
         fi
    done
    return 0
}

generate_and_apply_pin() {
    local pin_k="$1"
    local pin_f="$2"
    log_msg "INFO" "Generating pin file $pin_f for kernel $pin_k"

    # Extract base version number (e.g., 6.8.0-40) for wildcard matching
    local pin_base_ver; pin_base_ver=$(echo "$pin_k" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+')
    if [[ -z "$pin_base_ver" ]]; then
        print_color "$RED" "Could not extract base version from $pin_k for pinning."; log_msg "ERROR" "Could not extract base version from $pin_k"; return 1;
    fi

    local pin_content; cat << PIN_EOF > /tmp/kernel_pin_content
# Kernel Pinning Configuration generated by nvidia-mybitch.sh
# Prevents upgrades beyond kernel version containing '$pin_base_ver'

# Pin generic meta-packages and specific version packages
Package: linux-image-generic linux-headers-generic linux-generic* linux-image-*-generic linux-headers-*-generic linux-modules-*-generic linux-modules-extra-*-generic
Pin: version ${pin_base_ver}.*
Pin-Priority: 1001

# Example: Explicitly block a known bad version (Uncomment and edit if needed)
# Package: linux-image-6.8.0-57-generic linux-headers-6.8.0-57-generic linux-modules-6.8.0-57-generic linux-modules-extra-6.8.0-57-generic
# Pin: version 6.8.0-57.*
# Pin-Priority: -1

PIN_EOF

    pin_content=$(cat /tmp/kernel_pin_content)
    rm /tmp/kernel_pin_content

    print_color "$PURPLE" "--- Pinning File Content ---"
    print_color "$CYAN"; NO_TYPE_EFFECT=1 type_effect "$pin_content"; print_color "$PURPLE" "--------------------------" # Use type_effect here

    if ! prompt_confirm "Write this content to $pin_f?"; then log_msg "USER" "Cancelled writing pin file."; return 1; fi

    # Use sudo tee to write the file as root
    if echo "$pin_content" | sudo tee "$pin_f" > /dev/null; then
        sudo chown root:root "$pin_f" && sudo chmod 644 "$pin_f"
        print_color "$GREEN" "Pinning file $pin_f created/updated."; log_msg "INFO" "Wrote pin file $pin_f for $pin_k."
        print_color "$CYAN" "Running 'sudo apt update' to apply changes..."
        if run_command "apt-get update" false "Update APT after pinning"; then
             print_color "$GREEN" "APT cache updated. Kernel packages are now pinned.";
        else
             print_color "$RED" "APT update failed after pinning.";
        fi
        return 0
    else
        print_color "$RED" "Failed to write pinning file!"; log_msg "ERROR" "Failed to write pin file $pin_f."
        return 1
    fi
}
# FINISH ### KERNEL PINNING FUNCTION ###

# START ### GUIDED INSTALL FUNCTION ###
run_guided_install() {
    print_color "$PURPLE" "\n--- Guided Install: Nvidia Driver + CUDA (Method B Recommended) ---"; log_msg "INFO" "Starting Guided Install.";
    print_color "$YELLOW" "This runs: Clean -> Nvidia Repo Driver -> Nvidia Repo CUDA -> Initramfs -> Pin Prompt";
    local current_k; current_k=$(uname -r); print_color "$YELLOW" "(Will install for kernel: $current_k)";
    if ! prompt_confirm "Proceed with Guided Install on kernel $current_k?"; then return 1; fi

    local step_status=0

    print_color "$PURPLE" "\n--- Step 1: Enhanced Deep Clean ---";
    run_nvidia_cleanup; step_status=$?;
    if [[ $step_status -ne 0 ]]; then log_msg "ERROR" "Guided Install ABORTED: Deep Clean failed (Status: $step_status)."; print_color "$RED" "Guided Install ABORTED: Deep Clean failed."; return 1; fi;
    print_color "$GREEN" "Deep Clean Completed. Reboot highly recommended before proceeding.";
    if ! prompt_confirm "Continue install without rebooting (NOT RECOMMENDED)?"; then
        print_color "$YELLOW" "Exiting Guided Install. Please reboot into your desired kernel ($current_k) and run again."; log_msg "USER" "Aborted Guided Install for reboot."; return 1;
    fi

    print_color "$PURPLE" "\n--- Step 2: Install Driver via Nvidia Repo (cuda-drivers) ---";
    # Ensure repo is setup AND install the driver
    install_nvidia_apt_official_repo "false"; step_status=$?; # Pass "false" to ensure it installs
    if [[ $step_status -ne 0 ]]; then log_msg "ERROR" "Guided Install ABORTED: Nvidia Repo Driver install failed (Status: $step_status)."; print_color "$RED" "Guided Install ABORTED: Driver install failed."; return 1; fi;
    log_msg "INFO" "Guided Install: Step 2 (Driver Install) successful."

    print_color "$PURPLE" "\n--- Step 3: Install CUDA Toolkit via APT (from Nvidia Repo) ---";
    install_cuda_toolkit_apt_core; step_status=$?; # This helper function installs the toolkit
    if [[ $step_status -ne 0 ]]; then log_msg "ERROR" "Guided Install ABORTED: CUDA Toolkit install failed (Status: $step_status)."; print_color "$RED" "Guided Install ABORTED: Toolkit install failed."; return 1; fi;
    log_msg "INFO" "Guided Install: Step 3 (Toolkit Install) successful."

    print_color "$PURPLE" "\n--- Step 4: Update Initramfs ---";
    print_color "$CYAN" "Updating initramfs for all kernels...";
    run_command "update-initramfs -u -k all" true "Guided Install Initramfs Update"; step_status=$?;
    if [[ $step_status -ne 0 ]]; then log_msg "WARN" "Guided Install Warning: Initramfs update failed (Status: $step_status). Continuing..."; print_color "$YELLOW" "Warning: Initramfs update failed. Check logs."; else log_msg "INFO" "Guided Install: Step 4 (Initramfs Update) successful."; fi

    print_color "$GREEN" "\n--- Guided Install Steps Completed ---";
    log_msg "INFO" "Guided Install finished.";
    print_color "$YELLOW" "Reboot REQUIRED to activate drivers/toolkit.";
    print_color "$CYAN" "After rebooting into kernel $current_k, verify with 'nvidia-smi' and 'nvcc --version'.";

    # Recommend Pinning
    print_color "$PURPLE" "\n--- Step 5: Recommendation - Kernel Pinning ---";
    print_color "$YELLOW" "To prevent kernel updates from breaking this setup, PINNING kernel $current_k is strongly recommended.";
    if prompt_confirm "Go to Kernel Pinning module now?"; then
        run_kernel_pinning
    else
        print_color "$CYAN" "You can access Kernel Pinning later via Menu 9 -> 6.";
    fi
    return 0 # Return success even if initramfs failed, as main parts completed
}
# FINISH ### GUIDED INSTALL FUNCTION ###

# START ### SYSTEM PREP UTILS SUBMENU ###
run_system_prep_utils_submenu() {
     while true; do
         if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
         print_color "$PURPLE" "\n=== System Prep & Utils Submenu ===";
         echo "  $(print_color "$CYAN" "1)") Manage Display Manager (Stop/Start/Status)";
         echo "  $(print_color "$CYAN" "2)") Prepare Build Environment (DKMS, Headers, Tools)";
         echo "  $(print_color "$CYAN" "3)") Manage GCC Version (Check, Install, Setup Alts, Choose Default)"; # Updated Desc
         echo "  $(print_color "$CYAN" "4)") Update Initramfs (For specific kernel or all)";
         echo "  $(print_color "$CYAN" "5)") Network Troubleshooting Tools";
         echo "  $(print_color "$CYAN" "6)") Kernel Package Pinning (Hold/Unhold)"; # Added pinning
         echo "  $(print_color "$CYAN" "7)") Return to Main Menu";
         local choice;
         read -r -p "$(print_color "$YELLOW" "Enter choice [1-7]: ")" choice < /dev/tty;
         case "$choice" in
             1) run_manage_display_manager ;;
             2) run_prepare_build_env ;;
             3) run_manage_gcc ;;
             4) run_update_initramfs ;;
             5) run_network_fix ;;
             6) run_kernel_pinning ;; # Added pinning call
             7) break;; # Exit submenu loop
             *) print_color "$RED" "Invalid selection.";;
         esac;
         local last_status=$?;
         # Only pause if an action ran (choice 1-6)
         if [[ "$choice" =~ ^[1-6]$ ]]; then
             read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to submenu...")" < /dev/tty;
         fi;
    done;
    return 0;
}
# FINISH ### SYSTEM PREP UTILS SUBMENU ###

# START ### MAIN MENU FUNCTION ###
main_menu() {
    print_color "$PURPLE" "\n=== $(print_color "$GREEN" "NVIDIA") $(print_color "$CYAN" "MyBitch") $(print_color "$PURPLE" "Manager") v$SCRIPT_VERSION ===";
    print_color "$GREEN" "Select an operation:";
    echo "  $(print_color "$CYAN" " 1)") Guided Install (Recommended: Clean -> Nvidia Repo Driver+CUDA)";
    echo "  $(print_color "$CYAN" " 2)") NVIDIA Deep Clean (Manual Step)";
    echo "  $(print_color "$CYAN" " 3)") NVIDIA Driver Install (Manual Step - APT Std, APT Nvidia, Runfile)";
    echo "  $(print_color "$CYAN" " 4)") Install CUDA Toolkit (Manual Step - APT or Runfile)";
    echo "  $(print_color "$CYAN" " 5)") Blacklist Nouveau Driver";
    echo "  $(print_color "$CYAN" " 6)") GRUB Fix / Reinstall / Params (Presets & Custom)";
    echo "  $(print_color "$CYAN" " 7)") Kernel Reset (Remove & Reinstall)";
    echo "  $(print_color "$CYAN" " 8)") Update Initramfs (Target specific kernel)";
    echo "  $(print_color "$CYAN" " 9)") System Prep & Utilities (DM, BuildEnv, GCC, Initramfs, Network, Pinning)"; # Updated desc
    echo "  $(print_color "$CYAN" "10)") Chroot Helper (Live OS ONLY)";
    echo "  $(print_color "$CYAN" "11)") View Logs (System, Nvidia, APT, etc.)";
    echo "  $(print_color "$CYAN" "12)") Exit";

    local choice;
    read -r -p "$(print_color "$YELLOW" "Enter choice [1-12]: ")" choice < /dev/tty;

    case "$choice" in
        1) run_guided_install ;;          # NEW
        2) run_nvidia_cleanup ;;           # Was 1
        3) run_nvidia_install ;;           # Was 2
        4) run_cuda_install ;;             # Was 3
        5) run_nouveau_blacklist ;;        # Was 4
        6) run_grub_fix ;;                 # Was 5
        7) run_kernel_fix ;;               # Was 6
        8) run_update_initramfs ;;         # Was 7
        9) run_system_prep_utils_submenu ;; # Was 8, now includes Pinning
       10) run_chroot_helper ;;            # Was 9
       11) run_view_logs ;;                # Was 10
       12) print_color "$GREEN" "Keep hustlin'. Exiting..."; log_msg "INFO" "Exiting script."; exit 0 ;; # Was 11
        *) print_color "$RED" "Invalid selection." ;;
    esac

    local last_status=$?;
    # Don't pause after invalid choice or exit
    if [[ "$choice" -ge 1 && "$choice" -le 11 ]]; then # Pause for options 1-11
        # Let sub-modules handle their own success/fail messages
        read -r -p "$(print_color "$YELLOW" "\nPress Enter to return to main menu...")" < /dev/tty;
    fi;
}
# FINISH ### MAIN MENU FUNCTION ###

# START ### SCRIPT RUNNER ###
# Check sudo FIRST - it sets up USER_HOME and LOG paths
check_sudo

# Append to log file for history across runs
log_msg "INFO" "====== GPU Manager Started. Version $SCRIPT_VERSION ======"
log_msg "INFO" "Running as EUID=$EUID, User=$SUDO_USER, Home=$USER_HOME"

# Main loop
while true; do
    # Clear screen at the start of each main menu loop
    if command -v tput &> /dev/null; then tput clear; else clear; fi >&2
    main_menu
done
# FINISH ### SCRIPT RUNNER ###
