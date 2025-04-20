#!/bin/bash

# --- FlintX GRUB Key Creator ---
# Detects current system info (Kernel/Initrd/UUID) and
# generates/updates individual GRUB .cfg snippet files
# in a specified directory on the local Debian system.

# --- Configuration ---
CONFIG_FILE="$HOME/.grub_key_creator.conf" # Saves snippet dir path
DEFAULT_SNIPPET_DIR="/boot/grub_configs" # Default location for snippets
SNIPPET_BACKUP_DIR_RELPATH="backups" # Relative to snippet dir

# --- Helper Functions ---
prompt_yes_no() { local p="$1" d="${2:-N}" a; while true; do read -p "$p [Y/n]: " a; a="${a:-$d}"; if [[ "$a" =~ ^[Yy]$ ]]; then return 0; fi; if [[ "$a" =~ ^[Nn]$ ]]; then return 1; fi; echo "Please answer 'y' or 'n'."; done; }

# --- Load/Save/Prompt for Snippet Directory ---
load_snippet_dir_config() { if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; if [ -z "$SAVED_SNIPPET_DIR" ]; then return 1; fi; if ! sudo test -d "$SAVED_SNIPPET_DIR"; then echo "[WARN] Saved snippet path '$SAVED_SNIPPET_DIR' invalid."; return 1; fi; return 0; fi; return 1; }
save_snippet_dir_config() { local s="$1"; echo "[INFO] Saving snippet directory path..."; sudo touch "$CONFIG_FILE"; sudo chown "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "$CONFIG_FILE"; sudo chmod 600 "$CONFIG_FILE"; echo "# KeyCreator v1" | sudo tee "$CONFIG_FILE" > /dev/null; echo "SAVED_SNIPPET_DIR=\"$s\"" | sudo tee -a "$CONFIG_FILE" > /dev/null; echo "[INFO] Saved."; }
prompt_snippet_dir_config() {
    local vd=false; while [ "$vd" = false ]; do echo "[INFO] Recommended snippet location is /boot/grub_configs for GRUB."; read -e -p "Debian Snippet Dir [Default: ${DEFAULT_SNIPPET_DIR}]: " SNIPPET_DIR; SNIPPET_DIR="${SNIPPET_DIR:-$DEFAULT_SNIPPET_DIR}"; SNIPPET_DIR=$(eval echo "$SNIPPET_DIR"); if [[ "$SNIPPET_DIR" != "/boot/"* ]] && [[ "$SNIPPET_DIR" != "/root/"* ]]; then echo "[WARN] Path not in /boot or /root. Check GRUB access."; fi; if sudo mkdir -p "$SNIPPET_DIR"; then echo "[OK] Snippets will be stored in: $SNIPPET_DIR"; vd=true; else echo "[ERR] Cannot create/access snippet directory '$SNIPPET_DIR'."; fi; done
    if prompt_yes_no "Save this path for next time?"; then save_snippet_dir_config "$SNIPPET_DIR"; fi
}

# --- Detect System Info (Kernel/UUID) ---
detect_system_info() {
    echo "[INFO] Detecting system info...";
    DETECTED_UUID=$(findmnt -n -o UUID /) || DETECTED_UUID=""
    read -p "Debian Root UUID [${DETECTED_UUID:-Not Found}]: " FINAL_UUID
    FINAL_UUID="${FINAL_UUID:-$DETECTED_UUID}"
    if ! [[ "$FINAL_UUID" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then echo "[ERR] Invalid UUID."; return 1; fi
    echo "[OK] Using UUID: $FINAL_UUID"

    DETECTED_KERNEL_PATH=$(ls -t /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue\|recovery\|old' | head -n 1) || DETECTED_KERNEL_PATH=""
    DETECTED_INITRD_PATH=""
    if [ -n "$DETECTED_KERNEL_PATH" ] && [ -f "$DETECTED_KERNEL_PATH" ]; then
        kernel_version=$(basename "$DETECTED_KERNEL_PATH" | sed 's/^vmlinuz-//')
        DETECTED_INITRD_PATH=$(ls -t "/boot/initrd.img-${kernel_version}"* 2>/dev/null | head -n 1) || DETECTED_INITRD_PATH=""
        if [ ! -f "$DETECTED_INITRD_PATH" ]; then DETECTED_INITRD_PATH=""; fi
    else DETECTED_KERNEL_PATH=""; fi

    if [ -z "$DETECTED_KERNEL_PATH" ]; then
         echo "[WARN] No kernel detected.";
         read -e -p "Enter Kernel Path: " FINAL_KERNEL_PATH
         read -e -p "Enter Initrd Path: " FINAL_INITRD_PATH
    else
        echo " Detected Kernel: $DETECTED_KERNEL_PATH"; echo " Detected Initrd: $DETECTED_INITRD_PATH";
        if ! prompt_yes_no "Use detected paths?"; then
             read -e -p "Enter Kernel Path: " FINAL_KERNEL_PATH
             read -e -p "Enter Initrd Path: " FINAL_INITRD_PATH
        else
            FINAL_KERNEL_PATH="$DETECTED_KERNEL_PATH"; FINAL_INITRD_PATH="$DETECTED_INITRD_PATH";
        fi
    fi
    if ! sudo test -f "$FINAL_KERNEL_PATH" || ! sudo test -f "$FINAL_INITRD_PATH"; then echo "[ERR] Kernel/initrd invalid."; return 1; fi
    echo "[OK] Using Kernel: $FINAL_KERNEL_PATH"; echo "[OK] Using Initrd: $FINAL_INITRD_PATH";
    # Make available globally within this script run
    export FINAL_UUID FINAL_KERNEL_PATH FINAL_INITRD_PATH
    return 0
}

# --- Generate All Snippets (.cfg files) ---
generate_all_snippets() {
    local sdir="$1"
    if [ -z "$FINAL_KERNEL_PATH" ]; then echo "[ERROR] System info (kernel/initrd/uuid) must be set first (Option 1)."; return 1; fi
    echo "[INFO] Generating/Updating all .cfg snippets in ${sdir}...";
    local bakdir="${sdir}/${SNIPPET_BACKUP_DIR_RELPATH}"; sudo mkdir -p "$bakdir" || echo "[WARN] Failed backup dir creation."
    if sudo ls "${sdir}"/*.cfg > /dev/null 2>&1; then echo " Backing up existing..."; local ts=$(date +%Y%m%d_%H%M%S); sudo mkdir -p "${bakdir}/bak_${ts}"; if sudo test -d "${bakdir}/bak_${ts}"; then sudo mv "${sdir}"/*.cfg "${bakdir}/bak_${ts}/"; fi; fi
    # Helper func to generate one snippet
    gen() { echo " -> $1"; printf "%s" "$2" | sudo tee "${sdir}/$1" > /dev/null ; sudo chmod 644 "${sdir}/$1"; };
    # Define vars for clarity
    local k="$FINAL_KERNEL_PATH"; local i="$FINAL_INITRD_PATH"; local u="$FINAL_UUID"
    local common="insmod gzio part_gpt ext2; search --no-floppy --fs-uuid --set=root ${u}"
    local linux_base="linux ${k} root=UUID=${u} ro"; local initrd_base="initrd ${i}"
    local nd="nouveau.modeset=0 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"
    # Generate each snippet file
    gen "debian_gui_nomodeset.cfg" "# SNIP: GUI Nomodeset\nload_video\n${common}\n${linux_base} nomodeset\n${initrd_base}"
    gen "debian_gui_nomodeset_noefifb.cfg" "# SNIP: GUI Nomodeset NoEFIFB\nload_video\n${common}\n${linux_base} nomodeset video=efifb:off\n${initrd_base}"
    gen "debian_gui_nouveau_quiet.cfg" "# SNIP: GUI Nouveau Quiet\n${common}\n${linux_base} quiet\n${initrd_base}"
    gen "debian_gui_nouveau_verbose.cfg" "# SNIP: GUI Nouveau Verbose\n${common}\n${linux_base}\n${initrd_base}"
    gen "debian_gui_nouveau_drm_debug.cfg" "# SNIP: GUI Nouveau DRM Debug\n${common}\n${linux_base} drm.debug=0x1e log_buf_len=10M\n${initrd_base}"
    gen "debian_gui_nvidia_quiet.cfg" "# SNIP: GUI Nvidia Quiet\n${common}\n${linux_base} quiet nvidia-drm.modeset=1\n${initrd_base}"
    gen "debian_gui_nvidia_verbose.cfg" "# SNIP: GUI Nvidia Verbose\n${common}\n${linux_base} nvidia-drm.modeset=1\n${initrd_base}"
    gen "debian_gui_nvidia_drm_debug.cfg" "# SNIP: GUI Nvidia DRM Debug\n${common}\n${linux_base} nvidia-drm.modeset=1 drm.debug=0x1e log_buf_len=10M\n${initrd_base}"
    gen "debian_gui_nvidia_intel_pstate_disabled.cfg" "# SNIP: GUI Nvidia No P-State\n${common}\n${linux_base} quiet nvidia-drm.modeset=1 intel_pstate=disable\n${initrd_base}"
    gen "debian_gui_nvidia_max_cstate_1.cfg" "# SNIP: GUI Nvidia Max C1\n${common}\n${linux_base} quiet nvidia-drm.modeset=1 processor.max_cstate=1 intel_idle.max_cstate=1\n${initrd_base}"
    gen "debian_gui_nvidia_pcie_aspm_off.cfg" "# SNIP: GUI Nvidia No ASPM\n${common}\n${linux_base} quiet nvidia-drm.modeset=1 pcie_aspm=off\n${initrd_base}"
    gen "debian_recovery_basic.cfg" "# SNIP: Recovery Basic\n${common}\n${linux_base} single\n${initrd_base}"
    gen "debian_recovery_nomodeset.cfg" "# SNIP: Recovery Nomodeset\nload_video\n${common}\n${linux_base} single nomodeset\n${initrd_base}"
    gen "debian_tty_debug.cfg" "# SNIP: TTY Debug\n${common}\n${linux_base} 3 ${nd} debug ignore_loglevel log_buf_len=10M\n${initrd_base}"
    gen "debian_tty_nomodeset_nouveau_disabled.cfg" "# SNIP: TTY Nomodeset ND\n${common}\n${linux_base} 3 nomodeset ${nd}\n${initrd_base}"
    gen "debian_tty_nouveau_disabled.cfg" "# SNIP: TTY ND\n${common}\n${linux_base} quiet 3 ${nd}\n${initrd_base}"
    gen "debian_tty_nouveau_enabled.cfg" "# SNIP: TTY Nouveau Enabled\n${common}\n${linux_base} quiet 3\n${initrd_base}"
    gen "debian_tty_nvidia.cfg" "# SNIP: TTY Nvidia Active\n${common}\n${linux_base} quiet 3 nvidia-drm.modeset=1\n${initrd_base}"
    gen "debian_tty_debug_sysrq.cfg" "# SNIP: TTY Debug SysRq\n${common}\n${linux_base} 3 ${nd} debug ignore_loglevel log_buf_len=10M sysrq_always_enabled=1\n${initrd_base}"
    gen "debian_gui_nvidia_quiet_sysrq.cfg" "# SNIP: GUI Nvidia Quiet SysRq\n${common}\n${linux_base} quiet nvidia-drm.modeset=1 sysrq_always_enabled=1\n${initrd_base}";
    echo "[INFO] Snippet generation complete.";
}


# --- Main Script Logic ---
echo "--- FlintX GRUB Key Creator ---"
if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must run with sudo."; exit 1; fi
# Declare globals needed
declare SNIPPET_DIR FINAL_UUID FINAL_KERNEL_PATH FINAL_INITRD_PATH

# Load or prompt for snippet directory
if load_snippet_dir_config && prompt_yes_no "Use saved snippet directory [$SAVED_SNIPPET_DIR]?"; then
    SNIPPET_DIR="$SAVED_SNIPPET_DIR"
    echo "[INFO] Using saved snippet directory."
else
    prompt_snippet_dir_config # Sets SNIPPET_DIR globally
fi

# Main menu loop
while true; do
    clear
    echo "--- Key Creator Main Menu ---"
    echo "Snippet Storage Directory: ${SNIPPET_DIR}"
    echo "Current System Info:"
    echo "  Kernel: ${FINAL_KERNEL_PATH:-Not Set}"
    echo "  Initrd: ${FINAL_INITRD_PATH:-Not Set}"
    echo "  UUID  : ${FINAL_UUID:-Not Set}"
    echo "---------------------------"
    echo "Actions:"
    echo "1. Detect/Confirm System Info (Needed before generating)"
    echo "2. Generate/Update ALL .cfg Snippets in '$SNIPPET_DIR'"
    echo "3. Change Snippet Storage Directory"
    echo "4. Exit"
    read -p "Choose action (1-4): " choice

    case $choice in
        1)
            detect_system_info # Exports global vars on success
            ;;
        2)
            if [ -z "$FINAL_KERNEL_PATH" ]; then
                echo "[WARN] Please run option 1 first to set system info."
            elif prompt_yes_no "Generate/Update ALL snippets in '$SNIPPET_DIR' using current info?"; then
                generate_all_snippets "$SNIPPET_DIR"
            else
                echo "[INFO] Snippet generation skipped."
            fi
            ;;
        3)
            # Force prompt for new dir, potentially save it
            prompt_snippet_dir_config
            ;;
        4)
            echo "[INFO] Exiting Key Creator."
            exit 0
            ;;
        *)
            echo "[ERROR] Invalid choice."
            ;;
    esac
    read -p "Press Enter to continue..."
done

exit 0
