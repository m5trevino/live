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

