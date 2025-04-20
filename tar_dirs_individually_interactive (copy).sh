#!/bin/bash

# === CONFIGURATION ===
# Paths will be requested interactively below

# === COLORS ===
GREEN=$(tput setaf 2; tput bold)
CYAN=$(tput setaf 6; tput bold)
WHITE=$(tput setaf 7; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1; tput bold)
RESET=$(tput sgr0)

# === FUNCTIONS ===
echoc() {
    COLOR=$1
    shift
    echo -e "${COLOR}$*${RESET}"
}

# Function to handle ~ expansion manually and safely
expand_tilde() {
    local path="$1"
    # If path starts with ~, replace ~ with $HOME
    [[ "$path" == "~/"* ]] && path="${HOME}/${path:2}"
    echo "$path"
}


# === SCRIPT START ===
echoc $GREEN "############################################################"
echoc $GREEN "#      ${CYAN}INTERACTIVE DIRECTORY TARBALLER (tar.gz)${GREEN}       #"
echoc $GREEN "#            ${WHITE}Baggin' Up Stashes Edition${GREEN}            #"
echoc $GREEN "############################################################"
echo ""

# --- Get Paths Interactively ---
echoc $CYAN ">>> Enter the paths for the operation."

# Prompt for Source Directory
while true; do
    read -p "${CYAN}Enter the FULL path to the folder containing the directories to archive: ${WHITE}" SOURCE_PARENT_DIR_RAW
    # Handle ~ manually for validation step
    SOURCE_PARENT_DIR=$(expand_tilde "$SOURCE_PARENT_DIR_RAW")
    if [ -z "$SOURCE_PARENT_DIR" ]; then
        echoc $RED "!!! Path cannot be empty. Try again."
        continue
    fi
    if [ ! -d "$SOURCE_PARENT_DIR" ]; then
        echoc $RED "!!! Source directory not found or not a directory: ${WHITE}$SOURCE_PARENT_DIR"
        echoc $RED "!!! Please enter a valid, existing directory path."
    else
        echoc $GREEN "    +++ Source directory validated: ${WHITE}$SOURCE_PARENT_DIR"
        break # Exit loop if valid
    fi
done
echo ""

# Prompt for Destination Directory
while true; do
    read -p "${CYAN}Enter the FULL path where the individual .tar.gz archives should be saved: ${WHITE}" DESTINATION_DIR_RAW
    # Handle ~ manually
    DESTINATION_DIR=$(expand_tilde "$DESTINATION_DIR_RAW")
     if [ -z "$DESTINATION_DIR" ]; then
        echoc $RED "!!! Path cannot be empty. Try again."
        continue
    fi
    # Check if DESTINATION_DIR exists, create if not
    if [ ! -d "$DESTINATION_DIR" ]; then
        echoc $YELLOW ">>> Destination directory does not exist: ${WHITE}$DESTINATION_DIR"
        read -p "${CYAN}Create it now? (y/N): ${WHITE}" confirm_create
        if [[ "$confirm_create" =~ ^[Yy]$ ]]; then
            echoc $YELLOW ">>> Creating destination directory..."
            # Use mkdir -p on the potentially tilde-expanded path
            mkdir -p "$DESTINATION_DIR"
            if [ $? -ne 0 ]; then
                echoc $RED "!!! ERROR: Failed to create destination directory. Check permissions. Try again."
                # Loop continues implicitly
            else
                echoc $GREEN "    +++ Destination directory created: ${WHITE}$DESTINATION_DIR"
                break # Exit loop if created successfully
            fi
        else
            echoc $RED "!!! Cannot proceed without a destination directory. Try again."
            # Loop continues implicitly
        fi
    else
        echoc $GREEN "    +++ Destination directory validated: ${WHITE}$DESTINATION_DIR"
        break # Exit loop if already exists
    fi
done


# --- Main Processing Loop ---
echoc $CYAN "\n>>> Starting archiving process..."
SUCCESS_COUNT=0
FAIL_COUNT=0
PROCESSED_COUNT=0

# Use the validated SOURCE_PARENT_DIR variable
find "$SOURCE_PARENT_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' subdir_path; do
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    subdir_name=$(basename "$subdir_path")
    # Use the validated DESTINATION_DIR variable
    archive_path="${DESTINATION_DIR}/${subdir_name}.tar.gz"

    echoc $YELLOW ">>> Processing: ${WHITE}$subdir_name"

    # Check if archive already exists (optional: uncomment 'continue' to skip)
    if [ -f "$archive_path" ]; then
       echoc $YELLOW "    ... Archive already exists: ${WHITE}$archive_path. Skipping."
       # continue # Uncomment this line if you want to skip existing archives
    fi

    echoc $CYAN "    ... Creating archive: ${WHITE}${archive_path}"

    # Use the validated SOURCE_PARENT_DIR variable for -C
    if tar czf "$archive_path" -C "$SOURCE_PARENT_DIR" "$subdir_name"; then
        echoc $GREEN "    +++ Success: Archived '${subdir_name}'"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echoc $RED "    !!! FAILURE: Could not archive '${subdir_name}'. Check permissions or disk space."
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # Optionally remove partial archive on failure:
        # rm -f "$archive_path"
    fi
done

# --- Summary ---
echoc $CYAN "\n--- Archiving Summary ---"
if [ $PROCESSED_COUNT -eq 0 ]; then
    echoc $YELLOW ">>> No subdirectories found to process in ${WHITE}$SOURCE_PARENT_DIR"
else
    echoc $GREEN "+++ Successfully created ${SUCCESS_COUNT} archives."
    if [ $FAIL_COUNT -gt 0 ]; then
        echoc $RED "!!! Failed to create ${FAIL_COUNT} archives."
    fi
    echoc $WHITE "Archives saved in: ${DESTINATION_DIR}"
fi

echoc $GREEN "############################################################"
echoc $GREEN "#                     ${CYAN}OPERATION COMPLETE${GREEN}                 #"
echoc $GREEN "############################################################"

exit 0
