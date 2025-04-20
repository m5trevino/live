#!/bin/bash

# ############################################################################
# update_boot_keys_interactive.sh (v4.1)
#
# PURPOSE: Interactively updates hardcoded UUIDs and kernel/initrd versions
#          in config files (Ventoy GRUB, key-maker script, other config 'keys')
#          to match a target Linux system. Detects if running ON the target
#          system ('Internal Mode') or from an external system ('External Mode').
#          *Corrected default path for config keys dir.*
#
# HOW TO USE:
# 1. Make the script executable: chmod +x update_boot_keys_interactive.sh
# 2. Run the script: ./update_boot_keys_interactive.sh
# 3. Answer the first question: Are you running this ON the target system?
# 4. IF IN EXTERNAL MODE:
#    - Make sure the target MX root partition is mounted somewhere.
#    - Provide the mount point when asked.
# 5. Confirm/provide paths for key-maker, Ventoy cfg, and config dir.
# 6. !! DOUBLE-CHECK the modified files !!
#
# IMPORTANT: BACK UP YOUR CONFIG FILES BEFORE RUNNING THIS SCRIPT!
# ############################################################################

set -e # Exit immediately if a command exits with a non-zero status.
# set -u # Temporarily disable -u during reads, re-enable later if needed.

# START ### DEFAULT CONFIGURATION ###
# --- These are the starting points, script will confirm them ---
DEFAULT_EXTERNAL_MOUNT="/mnt/mxroot" # Default for EXTERNAL mode
DEFAULT_KEY_MAKER_SCRIPT="/usr/bin/key-maker"
DEFAULT_VENTOY_CFG="/media/flintx/Ventoy/ventoy/ventoy_grub.cfg"
# !! Updated path for config keys directory !!
DEFAULT_CONFIG_DIR="/boot/grub_configs" # <- Path provided by user
# FINISH ### DEFAULT CONFIGURATION ###

# START ### MODE DETECTION & INTERACTIVE PATH SETUP ###
echo "--- Interactive Boot Key Updater (v4.1) ---"
echo ""

RUNNING_INTERNALLY=false
read -p "Are you running this script *ON* the MX system you want to update keys for? (y/n): " run_mode
echo ""

if [[ "$run_mode" =~ ^[Yy]$ ]]; then
    RUNNING_INTERNALLY=true
    echo "[INFO] Running in INTERNAL mode. Will use '/' to find system info."
    SYSTEM_INFO_SOURCE="/"
    MX_ROOT_MOUNT="N/A (Internal Mode)"
else
    echo "[INFO] Running in EXTERNAL mode. Need the mount point of the target system."
    MX_ROOT_MOUNT="" # Clear it so confirm_path asks properly
fi
echo "---------------------------"

# Function to ask for path confirmation
confirm_path() {
    local prompt_message="$1"
    local default_path="$2"
    local -n path_variable_ref="$3"
    local user_input="" # Initialize to avoid potential issues with unbound variable if read fails
    local confirmed_path=""

    while [ -z "$confirmed_path" ]; do
        local prompt_suffix=":"
        if [ -n "$default_path" ]; then
             prompt_suffix=" [${default_path}]:"
        fi
        # Use -r to prevent backslash interpretation, -e enables readline if available
        read -r -e -p "$prompt_message${prompt_suffix} " user_input

        if [ -z "$user_input" ] && [ -n "$default_path" ]; then
            confirmed_path="${default_path}"
        elif [ -z "$user_input" ] && [ -z "$default_path" ]; then
             echo "[WARNING] No default value set. Please provide a valid path."
        else
            # User entered something, use their input
            if [ -z "$user_input" ]; then
                 echo "[WARNING] Empty path entered. Please provide a valid path."
            else
                 # Trim leading/trailing whitespace (optional but good practice)
                 user_input=$(echo "$user_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                 if [ -z "$user_input" ]; then
                      echo "[WARNING] Empty path after trimming whitespace. Please provide a valid path."
                 else
                      confirmed_path="${user_input}"
                 fi
            fi
        fi
    done
    path_variable_ref="${confirmed_path}"
    echo ""
}

# --- Ask for paths based on mode ---
echo "Please confirm or provide the correct paths for the config files."
echo "Press Enter to accept the default value shown in [brackets]."
echo ""

# Ask for mount point ONLY if in EXTERNAL mode
if [ "$RUNNING_INTERNALLY" = false ]; then
    confirm_path "Target MX Root Mount Point?" "${DEFAULT_EXTERNAL_MOUNT}" MX_ROOT_MOUNT
    SYSTEM_INFO_SOURCE="${MX_ROOT_MOUNT}"
fi

# Always confirm these paths
confirm_path "Path to key-maker script?" "${DEFAULT_KEY_MAKER_SCRIPT}" KEY_MAKER_SCRIPT
confirm_path "Path to Ventoy grub.cfg?" "${DEFAULT_VENTOY_CFG}" VENTOY_CFG
confirm_path "Path to config 'keys' directory?" "${DEFAULT_CONFIG_DIR}" CONFIG_DIR

# Re-enable '-u' if needed
# set -u

echo "--- Configuration Set ---"
if [ "$RUNNING_INTERNALLY" = true ]; then echo "[MODE] INTERNAL (using '/' for system info)"; else echo "[MODE] EXTERNAL (using '${MX_ROOT_MOUNT}' for system info)"; fi
echo "[PATHS] Key-Maker   : ${KEY_MAKER_SCRIPT}"
echo "[PATHS] Ventoy CFG  : ${VENTOY_CFG}"
echo "[PATHS] Config Dir  : ${CONFIG_DIR}"
echo "---------------------------"; sleep 1
# FINISH ### MODE DETECTION & INTERACTIVE PATH SETUP ###

# START ### SANITY CHECKS ###
echo "[INFO] Performing checks..."
# Check the source for system info (either '/' or the mount point)
if [ "$RUNNING_INTERNALLY" = false ]; then
    if ! [ -d "${SYSTEM_INFO_SOURCE}" ]; then echo "[ERROR] Mount point '${SYSTEM_INFO_SOURCE}' not found or not a directory." >&2; exit 1; fi
    if [ -z "$(ls -A ${SYSTEM_INFO_SOURCE})" ]; then echo "[ERROR] Mount point '${SYSTEM_INFO_SOURCE}' appears to be empty." >&2; exit 1; fi
    echo "  - External Mount Point OK."
else
     if ! [ -d "/boot" ]; then echo "[ERROR] Running internally, but /boot directory not found?" >&2; exit 1; fi
     echo "  - Running internally, /boot accessible."
fi
# Check existence and permissions for other files/dirs
PATHS_TO_CHECK=("${KEY_MAKER_SCRIPT}" "${VENTOY_CFG}" "${CONFIG_DIR}")
PATHS_DESC=("Key-Maker Script" "Ventoy CFG" "Config Dir")
ALL_CHECKS_PASSED=true
# (Sanity check logic remains the same)
for i in "${!PATHS_TO_CHECK[@]}"; do
    item="${PATHS_TO_CHECK[$i]}"; desc="${PATHS_DESC[$i]}"; check_passed=true
    if ! [ -e "$item" ]; then echo "[ERROR] ${desc} path not found: $item" >&2; check_passed=false; ALL_CHECKS_PASSED=false
    elif [ -f "$item" ] && ! [ -w "$item" ]; then echo "[ERROR] ${desc} file not writable: $item" >&2; check_passed=false; ALL_CHECKS_PASSED=false
    elif [ -d "$item" ]; then
         if ! [ -w "$item" ] && ! ls -A "$item" >/dev/null 2>&1; then echo "[ERROR] Cannot access/write contents of ${desc} directory: $item" >&2; check_passed=false; ALL_CHECKS_PASSED=false
         elif ! [ -w "$item" ]; then echo "[WARNING] ${desc} directory '$item' itself might not be writable, but attempting to write files inside."; fi
    fi
    if [ "$check_passed" = true ]; then echo "  - ${desc} path OK."; fi
done
if [ "$ALL_CHECKS_PASSED" = false ]; then echo "[FATAL] One or more path checks failed. Exiting." >&2; exit 1; fi
echo "[INFO] All path checks passed."
# FINISH ### SANITY CHECKS ###

# START ### GET SYSTEM INFO ###
# (Logic unchanged)
echo "[INFO] Detecting UUID for target system ('${SYSTEM_INFO_SOURCE}')..."
NEW_UUID=$(findmnt -n -o UUID --target "${SYSTEM_INFO_SOURCE}")
if [ -z "${NEW_UUID}" ]; then echo "[ERROR] Could not determine UUID for '${SYSTEM_INFO_SOURCE}'." >&2; if [ "$RUNNING_INTERNALLY" = false ]; then echo "  Make sure it's mounted correctly." >&2; fi; exit 1; fi
echo "[INFO] Found UUID: ${NEW_UUID}"
if [ "$RUNNING_INTERNALLY" = true ]; then TARGET_BOOT_DIR="/boot"; else TARGET_BOOT_DIR="${SYSTEM_INFO_SOURCE}/boot"; fi
echo "[INFO] Searching for latest kernel in ${TARGET_BOOT_DIR}..."
if ! [ -d "${TARGET_BOOT_DIR}" ]; then echo "[ERROR] Boot directory not found: ${TARGET_BOOT_DIR}" >&2; exit 1; fi
LATEST_VMLINUZ_BASENAME=$(ls -1 "${TARGET_BOOT_DIR}"/vmlinuz-* | sed "s|${TARGET_BOOT_DIR}/||" | grep -v 'rescue' | sort -V | tail -n 1)
if [ -z "${LATEST_VMLINUZ_BASENAME}" ]; then echo "[ERROR] Could not find any vmlinuz-* files in ${TARGET_BOOT_DIR}" >&2; exit 1; fi
KERNEL_VERSION_STRING=$(echo "${LATEST_VMLINUZ_BASENAME}" | sed 's/^vmlinuz-//')
LATEST_INITRD_BASENAME="initrd.img-${KERNEL_VERSION_STRING}"
LATEST_VMLINUZ_PATH="${TARGET_BOOT_DIR}/${LATEST_VMLINUZ_BASENAME}"; LATEST_INITRD_PATH="${TARGET_BOOT_DIR}/${LATEST_INITRD_BASENAME}"
if ! [ -f "${LATEST_VMLINUZ_PATH}" ] || ! [ -f "${LATEST_INITRD_PATH}" ]; then echo "[ERROR] Could not verify existence of kernel/initrd pair:" >&2; echo "  Kernel: ${LATEST_VMLINUZ_PATH}" >&2; echo "  Initrd: ${LATEST_INITRD_PATH}" >&2; exit 1; fi
echo "[INFO] Found latest kernel: ${LATEST_VMLINUZ_BASENAME}"; echo "[INFO] Found matching initrd: ${LATEST_INITRD_BASENAME}"
# FINISH ### GET SYSTEM INFO ###

# START ### DEFINE UPDATE FUNCTION ###
# (Unchanged)
update_standard_config() {
    local file="$1"; local uuid="$2"; local kernel_base="$3"; local initrd_base="$4"
    if ! [ -f "$file" ] || ! [ -w "$file" ]; then echo "   [SKIP] Cannot update $file (not a writable file)."; return; fi
    echo "[ACTION] Updating standard config file: $file"
    cp "${file}" "${file}.bak_$(date +%Y%m%d_%H%M%S)"; echo "   - Created backup: ${file}.bak_$(date +%Y%m%d_%H%M%S)"
    sed -i "s|root=UUID=[a-f0-9-]\{36\}|root=UUID=${uuid}|g" "$file"
    sed -i "s|^UUID=[a-f0-9-]\{36\}|UUID=${uuid}|g" "$file"; echo "   - Updated UUID pattern to: ${uuid}"
    sed -i "s|/boot/vmlinuz-[^[:space:]\"']\+|/boot/${kernel_base}|g" "$file"; echo "   - Updated kernel pattern to: /boot/${kernel_base}"
    sed -i "s|/boot/initrd.img-[^[:space:]\"']\+|/boot/${initrd_base}|g" "$file"; echo "   - Updated initrd pattern to: /boot/${initrd_base}"
}
# FINISH ### DEFINE UPDATE FUNCTION ###

# START ### UPDATE CONFIG FILES ###
# (Logic unchanged)
echo "[INFO] Preparing to update config files..."
if [ -f "${VENTOY_CFG}" ]; then update_standard_config "${VENTOY_CFG}" "${NEW_UUID}" "${LATEST_VMLINUZ_BASENAME}" "${LATEST_INITRD_BASENAME}"; else echo "[WARNING] Ventoy CFG file '${VENTOY_CFG}' not found (or is a dir?). Skipping."; fi
if [ -d "${CONFIG_DIR}" ]; then
    echo "[INFO] Processing files in config directory: ${CONFIG_DIR}"
    find "${CONFIG_DIR}" -maxdepth 1 -type f -regextype posix-extended -regex '.*\.cfg$|.*\.conf$' | while IFS= read -r file; do
        if grep -qE 'root=UUID=|^\s*UUID=' "$file"; then update_standard_config "$file" "${NEW_UUID}" "${LATEST_VMLINUZ_BASENAME}" "${LATEST_INITRD_BASENAME}"; else echo "   [SKIP] File $file does not appear to contain UUID patterns."; fi
    done
else echo "[WARNING] Config directory '${CONFIG_DIR}' not found or not a directory. Skipping."; fi
if [ -f "${KEY_MAKER_SCRIPT}" ] && [ -w "${KEY_MAKER_SCRIPT}" ]; then
    echo "[ACTION] Updating UUID in key-maker script: ${KEY_MAKER_SCRIPT}"
    cp "${KEY_MAKER_SCRIPT}" "${KEY_MAKER_SCRIPT}.bak_$(date +%Y%m%d_%H%M%S)"; echo "   - Created backup: ${KEY_MAKER_SCRIPT}.bak_$(date +%Y%m%d_%H%M%S)"
    sed -i "s|^UUID=[a-f0-9-]\{36\}|UUID=${NEW_UUID}|" "${KEY_MAKER_SCRIPT}"; echo "   - Updated UUID line to use: ${NEW_UUID}"
else echo "[WARNING] Key-maker script '${KEY_MAKER_SCRIPT}' not found or not writable. Skipping UUID update for it."; fi
# FINISH ### UPDATE CONFIG FILES ###

# START ### COMPLETION MESSAGE ###
# (Unchanged)
echo ""; echo "--- Boot Key Update Complete ---"; echo "[SUCCESS] Script finished processing."
if [ "$RUNNING_INTERNALLY" = true ]; then echo "[Mode] INTERNAL"; else echo "[Mode] EXTERNAL (Source: ${MX_ROOT_MOUNT})"; fi
echo "[Paths] Key-Maker   : ${KEY_MAKER_SCRIPT}"; echo "[Paths] Ventoy CFG  : ${VENTOY_CFG}"; echo "[Paths] Config Dir  : ${CONFIG_DIR}"; echo ""
echo "** IMPORTANT **"; echo "-> Double-check the changes made to ALL relevant files!"; echo "-> Test booting with the updated Ventoy config."; echo "-> If shit's fucked up, restore from the '.bak' files created."; echo "-> If key-maker was updated, test generating keys to ensure it uses the new UUID."; echo "--------------------------------"
# FINISH ### COMPLETION MESSAGE ###

exit 0
