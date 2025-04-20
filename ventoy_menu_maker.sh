#!/bin/bash

# --- FlintX Ventoy Menu Maker ---
# Reads a directory of GRUB .cfg snippets (created by key_creator.sh)
# and generates the /ventoy/ventoy_grub.cfg file for the
# Ventoy Menu Extension Plugin on the specified Ventoy USB drive.

# --- Configuration ---
CONFIG_FILE="$HOME/.grub_keymaster_v10.conf" # Shared config with key_creator
# Paths relative to Ventoy mount point
VENTOY_CONFIG_FILE_RELPATH="ventoy/ventoy_grub.cfg"
VENTOY_BACKUP_DIR_RELPATH="ventoy/backups"

# --- Helper Functions ---
prompt_yes_no() { local p="$1" d="${2:-N}" a; while true; do read -p "$p [Y/n]: " a; a="${a:-$d}"; if [[ "$a" =~ ^[Yy]$ ]]; then return 0; fi; if [[ "$a" =~ ^[Nn]$ ]]; then return 1; fi; echo "Please answer 'y' or 'n'."; done; }

# --- Load/Save/Prompt for Base Config (Paths) ---
# Needs SAVED_SNIPPET_DIR and SAVED_VENTOY_MOUNT from shared config
load_base_config() { if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; if [ -z "$SAVED_SNIPPET_DIR" ] || [ -z "$SAVED_VENTOY_MOUNT" ]; then return 1; fi; if ! sudo test -d "$SAVED_VENTOY_MOUNT" || ! sudo test -d "$SAVED_SNIPPET_DIR"; then echo "[WARN] Saved paths invalid."; return 1; fi; return 0; fi; return 1; }
save_base_config() { local s="$1" v="$2"; echo "[INFO] Saving base settings..."; sudo touch "$CONFIG_FILE"; sudo chown "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "$CONFIG_FILE"; sudo chmod 600 "$CONFIG_FILE"; echo "# GK v10" | sudo tee "$CONFIG_FILE" > /dev/null; echo "SAVED_SNIPPET_DIR=\"$s\"" | sudo tee -a "$CONFIG_FILE" > /dev/null; echo "SAVED_VENTOY_MOUNT=\"$v\"" | sudo tee -a "$CONFIG_FILE" > /dev/null; echo "[INFO] Saved."; }
prompt_base_config() {
    local vm=false; while [ "$vm" = false ]; do read -e -p "Ventoy USB Mount Path: " VENTOY_MOUNT_POINT; VENTOY_MOUNT_POINT=$(eval echo "$VENTOY_MOUNT_POINT"); if [ -d "$VENTOY_MOUNT_POINT" ]; then vm=true; sudo mkdir -p "${VENTOY_MOUNT_POINT}/ventoy" || exit 1; echo "[OK] Ventoy: $VENTOY_MOUNT_POINT"; else echo "[ERR] Not found."; fi; done
    local vd=false; while [ "$vd" = false ]; do echo "[INFO] Location where key_creator.sh stored snippets?"; read -e -p "Debian Snippet Dir: " SNIPPET_DIR; SNIPPET_DIR=$(eval echo "$SNIPPET_DIR"); if sudo test -d "$SNIPPET_DIR"; then echo "[OK] Found Snippets: $SNIPPET_DIR"; vd=true; else echo "[ERR] Snippet directory not found."; fi; done
    if prompt_yes_no "Save these paths?"; then save_base_config "$SNIPPET_DIR" "$VENTOY_MOUNT_POINT"; fi
}

# --- Get Target UUID (Needed for Menu Header) ---
get_target_uuid() {
    echo "[INFO] Need the UUID of the Debian partition containing snippets."
    DETECTED_UUID=$(findmnt -n -o TARGET,UUID "$SNIPPET_DIR" | awk '{print $2}') || DETECTED_UUID=""
     if [ -z "$DETECTED_UUID" ]; then # Fallback to root if snippet dir isn't mounted directly
         DETECTED_UUID=$(findmnt -n -o UUID /)
     fi
    read -p "Confirm Debian Partition UUID [Detected: ${DETECTED_UUID:-Not Found}]: " FINAL_UUID
    FINAL_UUID="${FINAL_UUID:-$DETECTED_UUID}"
    if ! [[ "$FINAL_UUID" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
        echo "[ERROR] Invalid UUID format entered: $FINAL_UUID"; return 1;
    fi
    echo "[INFO] Using UUID for menu generation: $FINAL_UUID"
    # Export for use in generate_ventoy_menu
    export FINAL_UUID="$FINAL_UUID"
    return 0
}


# --- Generate Ventoy Menu (ventoy_grub.cfg) ---
generate_ventoy_menu() {
    local snippet_dir="$1"; local part_uuid="$2"; local ventoy_mount="$3"
    local ventoy_cfg_file="${ventoy_mount}/${VENTOY_CONFIG_FILE_RELPATH}"
    local ventoy_backup_dir="${ventoy_mount}/${VENTOY_BACKUP_DIR_RELPATH}"

    echo "[INFO] Starting generation of ${ventoy_cfg_file}..."
    sudo mkdir -p "$(dirname "$ventoy_cfg_file")"
    if sudo test -f "$ventoy_cfg_file"; then echo "[INFO] Backing up existing..."; sudo mkdir -p "$ventoy_backup_dir"; local backup_ts=$(date +%Y%m%d_%H%M%S); sudo cp "$ventoy_cfg_file" "${ventoy_backup_dir}/ventoy_grub_${backup_ts}.cfg.bak"; fi

    echo "[INFO] Writing new ${ventoy_cfg_file}..."
    local temp_cfg_file=$(mktemp); chmod 644 "$temp_cfg_file"

    # Write Header
    cat << HEADER_EOF > "$temp_cfg_file"
# --- FlintX Custom Debian Loader (Generated: $(date)) ---
# Location: /ventoy/ventoy_grub.cfg
# Loads .cfg snippets from local Debian install. Press F6 in Ventoy.

set timeout=30
set menu_color_normal=white/black
set menu_color_highlight=black/cyan
set pagination=1

# Set variables needed by the menu entries
set flintx_target_uuid="${part_uuid}"
set flintx_config_path="${snippet_dir}" # Full path on Debian FS

# Function to find the target Partition
function find_debian_root {
    insmod part_gpt || true; insmod ext2 || true; # Load needed modules (adapt if needed)
    if search --no-floppy --fs-uuid --set=debian_root "\${flintx_target_uuid}"; then return 0; else
        echo "ERROR: Debian Root UUID \${flintx_target_uuid} NOT FOUND!"; sleep 10; return 1; fi
}
menuentry "--- FlintX Debian Boot Options (UUID: ${part_uuid:0:8}...) ---" --class=header {}
HEADER_EOF
    if [ $? -ne 0 ]; then echo "[ERROR] Failed writing header."; rm -f "$temp_cfg_file"; return 1; fi

    # Add menu entries directly for each .cfg file found
    local count=0
    local cfg_file_count=$(sudo ls -1 "${snippet_dir}"/*.cfg 2>/dev/null | wc -l)
    if [ "$cfg_file_count" -eq 0 ]; then
        echo "[WARN] No '.cfg' snippets found in ${snippet_dir} to add!"
        echo "menuentry \"(No .cfg files found in ${snippet_dir})\" { sleep 5 }" >> "$temp_cfg_file"
    else
        # Helper function to generate the menu entry text safely
        generate_single_menuentry() {
            local menu_title="$1"; local cfg_filename="$2"; local entry_class="$3"
            # Use printf with correct path construction
            printf '    menuentry "%s" --class %s {\n        find_debian_root\n        if [ \$? -eq 0 ]; then\n            local target_cfg="(\$debian_root)%s/%s"\n            echo "Loading config: \${target_cfg}"\n            if [ -e "\${target_cfg}" ]; then\n                configfile "\${target_cfg}"\n                echo "Configfile done, attempting boot..."\n                boot\n            else\n                 echo "ERROR: Snippet \${target_cfg} not found!"\n                 sleep 5\n            fi\n        fi\n        sleep 1\n    }\n' \
                   "$menu_title" "$entry_class" "$flintx_config_path" "$cfg_filename" # Note: flintx_config_path must be global for this shell function
        }

        # Define Submenus and add entries
        echo "submenu '--> [GUI] Standard Modes' --class=gui {" >> "$temp_cfg_file"
        sudo find "${snippet_dir}" -maxdepth 1 \( -name 'debian_gui_nouveau*.cfg' -o -name 'debian_gui_nvidia_quiet.cfg' -o -name 'debian_gui_nvidia_verbose.cfg' -o -name 'debian_gui_nvidia_quiet_sysrq.cfg' \) -print0 | while IFS= read -r -d $'\0' f; do
            fn=$(basename "$f"); mn=$(echo "$fn" | sed -e 's/\.cfg$//;s/debian_gui_//;s/_/ /g;s/\b\(.\)/\u\1/g'); cl="debian"; if [[ "$fn" == *"nvidia"* ]]; then cl="nvidia"; fi; if [[ "$fn" == *"debug"* ]]; then cl="debug"; fi
            generate_single_menuentry "$mn" "$fn" "$cl" >> "$temp_cfg_file"; count=$((count + 1)); done
        echo "    menuentry '<-- Back' --class=vtoyret VTOY_RET {}" >> "$temp_cfg_file"; echo "}" >> "$temp_cfg_file"

        echo "submenu '--> [TTY] Text Modes' --class=tty {" >> "$temp_cfg_file"
        sudo find "${snippet_dir}" -maxdepth 1 \( -name 'debian_tty*.cfg' ! -name '*sysrq*.cfg' ! -name '*debug*.cfg' \) -print0 | while IFS= read -r -d $'\0' f; do
             fn=$(basename "$f"); mn=$(echo "$fn" | sed -e 's/\.cfg$//;s/debian_tty_//;s/_/ /g;s/\b\(.\)/\u\1/g'); cl="debian"; if [[ "$fn" == *"nvidia"* ]]; then cl="nvidia"; fi; if [[ "$fn" == *"nomodeset"* ]]; then cl="fallback"; fi
             generate_single_menuentry "$mn" "$fn" "$cl" >> "$temp_cfg_file"; count=$((count + 1)); done
        echo "    menuentry '<-- Back' --class=vtoyret VTOY_RET {}" >> "$temp_cfg_file"; echo "}" >> "$temp_cfg_file"

        echo "submenu '--> [GFX] Fallback / Advanced' --class=fallback {" >> "$temp_cfg_file"
        sudo find "${snippet_dir}" -maxdepth 1 \( -name 'debian_gui_nomodeset*.cfg' -o -name 'debian_gui_nvidia_intel*.cfg' -o -name 'debian_gui_nvidia_max*.cfg' -o -name 'debian_gui_nvidia_pcie*.cfg' \) -print0 | while IFS= read -r -d $'\0' f; do
           fn=$(basename "$f"); mn=$(echo "$fn" | sed -e 's/\.cfg$//;s/debian_gui_//;s/_/ /g;s/\b\(.\)/\u\1/g'); cl="fallback"; if [[ "$fn" == *"nvidia"* ]]; then cl="nvidia"; fi
           generate_single_menuentry "$mn" "$fn" "$cl" >> "$temp_cfg_file"; count=$((count + 1)); done
        echo "    menuentry '<-- Back' --class=vtoyret VTOY_RET {}" >> "$temp_cfg_file"; echo "}" >> "$temp_cfg_file"

        echo "submenu '--> [DEBUG] Debug / Recovery' --class=debug {" >> "$temp_cfg_file"
        sudo find "${snippet_dir}" -maxdepth 1 \( -name '*debug*.cfg' -o -name '*recovery*.cfg' -o -name '*sysrq*.cfg' \) -print0 | while IFS= read -r -d $'\0' f; do
           fn=$(basename "$f"); mn=$(echo "$fn" | sed -e 's/\.cfg$//;s/debian_//;s/_/ /g;s/\b\(.\)/\u\1/g'); cl="debug"; if [[ "$fn" == *"recovery"* ]]; then cl="recovery"; fi; if [[ "$fn" == *"nvidia"* ]]; then cl="nvidia"; fi; if [[ "$fn" == *"tty"* ]]; then cl="tty"; fi
           generate_single_menuentry "$mn" "$fn" "$cl" >> "$temp_cfg_file"; count=$((count + 1)); done
        echo "    menuentry '<-- Back' --class=vtoyret VTOY_RET {}" >> "$temp_cfg_file"; echo "}" >> "$temp_cfg_file"
    fi

    # Add final return entry
    cat << FOOTER_EOF >> "$temp_cfg_file"

menuentry '' --class=spacer {}
menuentry '<-- Return to Ventoy Main Menu [Esc]' --class=vtoyret VTOY_RET {}
FOOTER_EOF

    # Copy temp file to final destination
    echo "[INFO] Copying temp file to ${ventoy_cfg_file}..."
    sudo cp "$temp_cfg_file" "$ventoy_cfg_file" || { echo "[ERROR] Failed copying."; rm -f "$temp_cfg_file"; return 1; }
    sudo chmod 644 "$ventoy_cfg_file" || echo "[WARN] Failed permissions."
    rm -f "$temp_cfg_file"

    echo "[INFO] Ventoy menu generation complete. Processed $count entries."
    return 0
}

# --- Main Script Logic ---
echo "--- FlintX Ventoy Menu Maker ---"
if [ "$(id -u)" -ne 0 ]; then echo "[ERROR] Must run with sudo."; exit 1; fi
declare SNIPPET_DIR VENTOY_MOUNT_POINT PARTITION_UUID FINAL_UUID

# Load or prompt for base paths
if load_base_config && prompt_yes_no "Use saved paths [Snippets: $SAVED_SNIPPET_DIR | Ventoy: $SAVED_VENTOY_MOUNT]?"; then
    SNIPPET_DIR="$SAVED_SNIPPET_DIR"; VENTOY_MOUNT_POINT="$SAVED_VENTOY_MOUNT"
    echo "[INFO] Using saved paths."
else
    prompt_base_config # Sets SNIPPET_DIR and VENTOY_MOUNT_POINT globally
fi

# Get the UUID for the menu header / verification
if ! get_target_uuid; then # Sets FINAL_UUID globally on success
    echo "[ERROR] Could not determine UUID for the snippet partition. Cannot generate menu."
    exit 1
fi
PARTITION_UUID=$FINAL_UUID # Use the confirmed UUID

# Confirmation before generating menu
echo "--- Ready to Generate Ventoy Menu ---"
echo "Ventoy USB Mounted at: $VENTOY_MOUNT_POINT"
echo "Using Snippets From  : $SNIPPET_DIR"
echo "On Debian Partition  : $PARTITION_UUID"
echo "Will backup and write: ${VENTOY_MOUNT_POINT}/${VENTOY_CONFIG_FILE_RELPATH}"
echo "-------------------------------------"
if ! prompt_yes_no "Proceed to generate Ventoy custom menu file?"; then
    echo "[INFO] Aborted by user."
    exit 0
fi

# Generate the file
if ! generate_ventoy_menu "$SNIPPET_DIR" "$PARTITION_UUID" "$VENTOY_MOUNT_POINT"; then
    echo "[ERROR] Menu generation failed."
    exit 1
fi

echo ""
echo "[SUCCESS] Process complete!"
echo "[NEXT] Safely unmount Ventoy USB: sudo umount ${VENTOY_MOUNT_POINT}"
echo "       Boot from USB, press F6 for the FlintX Custom Menu."

exit 0
