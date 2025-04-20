#!/bin/bash

# Script to gather system and graphics logs for troubleshooting boot issues.
# Run this script with sudo AFTER booting into a working (e.g., TTY) session.

echo "--- FlintX Boot Log Gatherer ---"

# --- Configuration ---
OUTPUT_BASE_DIR="~/debug_logs" # Base directory for logs (in user's home)
# Expand the tilde ~ to the actual home directory path
OUTPUT_BASE_DIR_EXPANDED=$(eval echo "$OUTPUT_BASE_DIR")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${OUTPUT_BASE_DIR_EXPANDED}/boot_log_${TIMESTAMP}"

# --- Check for Root Privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script needs to be run with sudo or as root."
  exit 1
fi

# --- Create Output Directory ---
echo "[INFO] Creating log directory: ${LOG_DIR}"
mkdir -p "${LOG_DIR}"
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create log directory. Check permissions."
    exit 1
fi
# Set permissions so the regular user can access it later
chown -R "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "${OUTPUT_BASE_DIR_EXPANDED}" || echo "[WARN] Could not change ownership of base log dir."
chmod 775 "${LOG_DIR}" || echo "[WARN] Could not set permissions on log dir."


# --- Gather Logs & Info ---

echo "[INFO] Gathering Kernel Logs (dmesg)..."
dmesg -T > "${LOG_DIR}/dmesg_current.log" || echo "[WARN] Failed to get current dmesg."
journalctl -k -b -1 --no-pager > "${LOG_DIR}/dmesg_previous_boot.log" || echo "[WARN] Failed to get dmesg for previous boot (maybe first boot?)."

echo "[INFO] Gathering Systemd Journal Logs..."
journalctl -b --no-pager > "${LOG_DIR}/journal_current.log" || echo "[WARN] Failed to get current journal."
journalctl -b -1 --no-pager > "${LOG_DIR}/journal_previous_boot.log" || echo "[WARN] Failed to get journal for previous boot."

echo "[INFO] Gathering Display Manager Logs (from journal)..."
# Add other display managers if you use them (lightdm, sddm, etc.)
journalctl -b -u gdm3 --no-pager > "${LOG_DIR}/journal_current_gdm3.log" || echo "[INFO] No current GDM3 logs found or error."
journalctl -b -1 -u gdm3 --no-pager > "${LOG_DIR}/journal_previous_gdm3.log" || echo "[INFO] No previous GDM3 logs found or error."
# journalctl -b -u lightdm --no-pager > "${LOG_DIR}/journal_current_lightdm.log" || echo "[INFO] No current LightDM logs found or error."
# journalctl -b -1 -u lightdm --no-pager > "${LOG_DIR}/journal_previous_lightdm.log" || echo "[INFO] No previous LightDM logs found or error."

echo "[INFO] Gathering Xorg Logs..."
cp /var/log/Xorg.0.log "${LOG_DIR}/xorg_current.log" 2>/dev/null || echo "[INFO] No current Xorg log (/var/log/Xorg.0.log) found."
cp /var/log/Xorg.0.log.old "${LOG_DIR}/xorg_previous.log" 2>/dev/null || echo "[INFO] No previous Xorg log (/var/log/Xorg.0.log.old) found."
cp /var/log/Xorg.1.log "${LOG_DIR}/xorg_previous_alt.log" 2>/dev/null || echo "[INFO] No alternative previous Xorg log (/var/log/Xorg.1.log) found."
# Grab any others just in case
cp /var/log/Xorg.*.log* "${LOG_DIR}/" 2>/dev/null || echo "[INFO] No other Xorg logs found."


echo "[INFO] Gathering System Information..."
uname -a > "${LOG_DIR}/uname.txt" || echo "[WARN] Failed to get uname."
cat /proc/cmdline > "${LOG_DIR}/kernel_cmdline.txt" || echo "[WARN] Failed to get kernel cmdline."
lsmod > "${LOG_DIR}/lsmod.txt" || echo "[WARN] Failed to get lsmod."
lspci -k > "${LOG_DIR}/lspci_k.txt" || echo "[WARN] Failed to get lspci -k."
dpkg -l | grep -i 'nvidia\|nouveau\|mesa\|xserver-xorg-video\|libgl\|vulkan' > "${LOG_DIR}/graphics_packages.txt" || echo "[WARN] Failed to list graphics packages."

echo "[INFO] Checking for Nvidia Specific Info..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi > "${LOG_DIR}/nvidia-smi.txt" || echo "[WARN] nvidia-smi command failed."
    nvidia-smi -q > "${LOG_DIR}/nvidia-smi_q.txt" || echo "[WARN] nvidia-smi -q command failed."
else
    echo "[INFO] nvidia-smi command not found. Skipping." > "${LOG_DIR}/nvidia-smi.txt"
fi

# --- Final Touches ---
# Set permissions again just to be sure user can read everything
chown -R "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "${LOG_DIR}" || echo "[WARN] Could not change ownership of log dir."
chmod -R u+r,g+r,o-rwx "${LOG_DIR}" || echo "[WARN] Could not set final read permissions." # Readable by user/group


echo "[SUCCESS] Log gathering complete."
echo "Logs saved in: ${LOG_DIR}"
echo "Review the files there, especially the '_previous_boot' logs."
echo "--- End FlintX Boot Log Gatherer ---"

exit 0
#!/bin/bash

# Script to gather system and graphics logs for troubleshooting boot issues.
# Run this script with sudo AFTER booting into a working (e.g., TTY) session.

echo "--- FlintX Boot Log Gatherer ---"

# --- Configuration ---
OUTPUT_BASE_DIR="~/debug_logs" # Base directory for logs (in user's home)
# Expand the tilde ~ to the actual home directory path
OUTPUT_BASE_DIR_EXPANDED=$(eval echo "$OUTPUT_BASE_DIR")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${OUTPUT_BASE_DIR_EXPANDED}/boot_log_${TIMESTAMP}"

# --- Check for Root Privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] This script needs to be run with sudo or as root."
  exit 1
fi

# --- Create Output Directory ---
echo "[INFO] Creating log directory: ${LOG_DIR}"
mkdir -p "${LOG_DIR}"
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create log directory. Check permissions."
    exit 1
fi
# Set permissions so the regular user can access it later
chown -R "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "${OUTPUT_BASE_DIR_EXPANDED}" || echo "[WARN] Could not change ownership of base log dir."
chmod 775 "${LOG_DIR}" || echo "[WARN] Could not set permissions on log dir."


# --- Gather Logs & Info ---

echo "[INFO] Gathering Kernel Logs (dmesg)..."
dmesg -T > "${LOG_DIR}/dmesg_current.log" || echo "[WARN] Failed to get current dmesg."
journalctl -k -b -1 --no-pager > "${LOG_DIR}/dmesg_previous_boot.log" || echo "[WARN] Failed to get dmesg for previous boot (maybe first boot?)."

echo "[INFO] Gathering Systemd Journal Logs..."
journalctl -b --no-pager > "${LOG_DIR}/journal_current.log" || echo "[WARN] Failed to get current journal."
journalctl -b -1 --no-pager > "${LOG_DIR}/journal_previous_boot.log" || echo "[WARN] Failed to get journal for previous boot."

echo "[INFO] Gathering Display Manager Logs (from journal)..."
# Add other display managers if you use them (lightdm, sddm, etc.)
journalctl -b -u gdm3 --no-pager > "${LOG_DIR}/journal_current_gdm3.log" || echo "[INFO] No current GDM3 logs found or error."
journalctl -b -1 -u gdm3 --no-pager > "${LOG_DIR}/journal_previous_gdm3.log" || echo "[INFO] No previous GDM3 logs found or error."
# journalctl -b -u lightdm --no-pager > "${LOG_DIR}/journal_current_lightdm.log" || echo "[INFO] No current LightDM logs found or error."
# journalctl -b -1 -u lightdm --no-pager > "${LOG_DIR}/journal_previous_lightdm.log" || echo "[INFO] No previous LightDM logs found or error."

echo "[INFO] Gathering Xorg Logs..."
cp /var/log/Xorg.0.log "${LOG_DIR}/xorg_current.log" 2>/dev/null || echo "[INFO] No current Xorg log (/var/log/Xorg.0.log) found."
cp /var/log/Xorg.0.log.old "${LOG_DIR}/xorg_previous.log" 2>/dev/null || echo "[INFO] No previous Xorg log (/var/log/Xorg.0.log.old) found."
cp /var/log/Xorg.1.log "${LOG_DIR}/xorg_previous_alt.log" 2>/dev/null || echo "[INFO] No alternative previous Xorg log (/var/log/Xorg.1.log) found."
# Grab any others just in case
cp /var/log/Xorg.*.log* "${LOG_DIR}/" 2>/dev/null || echo "[INFO] No other Xorg logs found."


echo "[INFO] Gathering System Information..."
uname -a > "${LOG_DIR}/uname.txt" || echo "[WARN] Failed to get uname."
cat /proc/cmdline > "${LOG_DIR}/kernel_cmdline.txt" || echo "[WARN] Failed to get kernel cmdline."
lsmod > "${LOG_DIR}/lsmod.txt" || echo "[WARN] Failed to get lsmod."
lspci -k > "${LOG_DIR}/lspci_k.txt" || echo "[WARN] Failed to get lspci -k."
dpkg -l | grep -i 'nvidia\|nouveau\|mesa\|xserver-xorg-video\|libgl\|vulkan' > "${LOG_DIR}/graphics_packages.txt" || echo "[WARN] Failed to list graphics packages."

echo "[INFO] Checking for Nvidia Specific Info..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi > "${LOG_DIR}/nvidia-smi.txt" || echo "[WARN] nvidia-smi command failed."
    nvidia-smi -q > "${LOG_DIR}/nvidia-smi_q.txt" || echo "[WARN] nvidia-smi -q command failed."
else
    echo "[INFO] nvidia-smi command not found. Skipping." > "${LOG_DIR}/nvidia-smi.txt"
fi

# --- Final Touches ---
# Set permissions again just to be sure user can read everything
chown -R "${SUDO_USER:-$(logname)}":"${SUDO_USER:-$(logname)}" "${LOG_DIR}" || echo "[WARN] Could not change ownership of log dir."
chmod -R u+r,g+r,o-rwx "${LOG_DIR}" || echo "[WARN] Could not set final read permissions." # Readable by user/group


echo "[SUCCESS] Log gathering complete."
echo "Logs saved in: ${LOG_DIR}"
echo "Review the files there, especially the '_previous_boot' logs."
echo "--- End FlintX Boot Log Gatherer ---"

exit 0
