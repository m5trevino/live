#!/usr/bin/env bash

# START ### CONFIGURATION & HELPERS ###
# --- Script to quickly mount system and enter chroot from Live OS ---

# Function to print colored messages
print_color() {
    local color_code="$1"
    local message="$2"
    local reset_code="\e[0m"
    echo -e "${color_code}${message}${reset_code}"
}

# Colors
INFO_COLOR="\e[36m"    # Cyan
CMD_COLOR="\e[33m"     # Yellow
PROMPT_COLOR="\e[35m"   # Magenta
ERROR_COLOR="\e[31m"    # Red
SUCCESS_COLOR="\e[32m"  # Green
WARN_COLOR="\e[31m"     # Red

# Function for error handling
handle_error() {
    local error_message="$1"
    local exit_code="${2:-1}" # Default exit code 1
    print_color "$ERROR_COLOR" "ERROR: $error_message"
    print_color "$ERROR_COLOR" "Aborting script."
    # Note: We don't attempt auto-unmount here as the script might fail *during* mounting. User should check manually.
    exit "$exit_code"
}

# Mount point
MOUNT_POINT="/mnt/system"

# Bind mount paths
BIND_MOUNTS=( "/dev" "/dev/pts" "/proc" "/sys" )

# --- Core Functions ---

get_partitions() {
    print_color "$INFO_COLOR" "Need the location of your busted system."
    print_color "$INFO_COLOR" "Use 'lsblk -f' or 'sudo fdisk -l' in another terminal if you ain't sure."
    
    while true; do
        read -p "$(print_color "$PROMPT_COLOR" "Enter the ROOT partition (e.g., /dev/nvme0n1p3, /dev/sda2): ")" ROOT_PART
        if [[ -b "$ROOT_PART" ]]; then
            break
        else
            print_color "$ERROR_COLOR" "That ain't look right. '$ROOT_PART' ain't a block device. Check the path."
        fi
    done

    while true; do
        # Assume EFI for modern systems, could be adapted for BIOS later if needed
        read -p "$(print_color "$PROMPT_COLOR" "Enter the EFI partition (e.g., /dev/nvme0n1p1, /dev/sda1): ")" EFI_PART
        if [[ -b "$EFI_PART" ]]; then
            break
        else
             print_color "$ERROR_COLOR" "That ain't look right. '$EFI_PART' ain't a block device. Check the path."
        fi
    done
     print_color "$INFO_COLOR" "Target Root: $ROOT_PART"
     print_color "$INFO_COLOR" "Target EFI:  $EFI_PART"
     echo ""
}

mount_and_prep_chroot() {
    print_color "$INFO_COLOR" "Setting up the operating table ($MOUNT_POINT)..."
    sudo mkdir -p "$MOUNT_POINT/boot/efi" || handle_error "Couldn't make mount points under $MOUNT_POINT. Check permissions or if path exists and isn't a file."

    print_color "$INFO_COLOR" "Mounting Root ($ROOT_PART)..."
    sudo mount "$ROOT_PART" "$MOUNT_POINT" || handle_error "Failed to mount root partition $ROOT_PART to $MOUNT_POINT."

    print_color "$INFO_COLOR" "Mounting EFI ($EFI_PART)..."
    sudo mount "$EFI_PART" "$MOUNT_POINT/boot/efi" || handle_error "Failed to mount EFI partition $EFI_PART to $MOUNT_POINT/boot/efi."

    print_color "$INFO_COLOR" "Binding the vitals..."
    for path in "${BIND_MOUNTS[@]}"; do
        print_color "$CMD_COLOR" "  Binding $path..."
        sudo mount --bind "$path" "$MOUNT_POINT$path" || handle_error "Failed to bind mount $path."
    done
    print_color "$SUCCESS_COLOR" "Bind mounts complete."


    print_color "$INFO_COLOR" "Slippin' in the DNS info (/etc/resolv.conf)..."
    if sudo cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"; then
         print_color "$SUCCESS_COLOR" "DNS info copied."
    else
         print_color "$WARN_COLOR" "Warning: Couldn't copy DNS info. Network inside chroot might be dead."
    fi
}
# FINISH ### CONFIGURATION & HELPERS ###


# START ### SCRIPT EXECUTION ###
print_color "$INFO_COLOR" "--- Quick Chroot Entry Script ---"
print_color "$WARN_COLOR" "Run this with 'sudo' from your Live OS terminal."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_color "$ERROR_COLOR" "Gotta run this as root, my boy. Use 'sudo ./quick_chroot.sh'."
   exit 1
fi

# Get partitions
get_partitions

# Mount and Prep
mount_and_prep_chroot

# Confirmation and Chroot Entry
print_color "$SUCCESS_COLOR" "Mounts and prep complete."
print_color "$INFO_COLOR" "About to enter chroot environment at '$MOUNT_POINT'."
print_color "$INFO_COLOR" "Once inside, you'll be operating as 'root' on your installed system."
print_color "$INFO_COLOR" "Type 'exit' when you're done inside the chroot."
read -p "$(print_color "$PROMPT_COLOR" "Press Enter to chroot or Ctrl+C to bail...")"

print_color "$CMD_COLOR" "Executing: sudo chroot $MOUNT_POINT /bin/bash"
sudo chroot "$MOUNT_POINT" /bin/bash

# Post-Chroot Reminder
print_color "$INFO_COLOR" "\n--- Exited Chroot ---"
print_color "$WARN_COLOR" "IMPORTANT: Remember to unmount everything manually now!"
print_color "$WARN_COLOR" "Run this (or similar) when you're ready:"
print_color "$CMD_COLOR" "  sudo umount -R $MOUNT_POINT"
print_color "$INFO_COLOR" "(The '-R' attempts recursive unmounts for bind mounts too)."

exit 0
# FINISH ### SCRIPT EXECUTION ###

