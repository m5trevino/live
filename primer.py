#!/usr/bin/env python3

import subprocess
import platform
import os
import glob
from pathlib import Path

# ############################################################################
# primer.py (Python version)
#
# PURPOSE: Gathers info about the current graphics state (Nvidia/Nouveau),
#          configuration, and potential issues to help decide on safe
#          boot options before rebooting. Python rewrite of the Bash check.
#          **THIS SCRIPT PROVIDES INFO & SUGGESTIONS - NO GUARANTEES!**
#
# HOW TO USE:
# 1. Make executable: chmod +x primer.py
# 2. Run it: python3 primer.py  OR  ./primer.py
# 3. Read the report and warnings carefully.
# 4. Choose your GRUB/systemd-boot option based on the intel.
#
# ############################################################################

# START ### GLOBAL STATE & CONFIG ###
KERNEL_VERSION = platform.release()
state = {
    "nvidia_loaded": False,
    "nouveau_loaded": False,
    "nvidia_blacklisted": False,
    "nouveau_blacklisted": False,
    "dkms_ok": "N/A",  # Can be True, False, "N/A"
    "nvidia_pkg_installed": False,
    "nouveau_pkg_installed": False,
    "firmware_pkg_installed": False,
    "xorg_driver": "Auto/Unknown",
    "xorg_driver_found_in_config": False,
    "nvidia_hw_detected": False,
    "lspci_ran_ok": False,
    "lspci_sudo_warn": False,
    "warnings": [],
    "suggestions": [],
    "critical_warnings": [], # Separate list for critical DKMS issues
}
MODPROBE_DIRS = ["/etc/modprobe.d/"]
XORG_CONFIG_DIRS = ["/etc/X11/", "/usr/share/X11/"]
# FINISH ### GLOBAL STATE & CONFIG ###

# START ### UTILITY FUNCTIONS ###
def run_command(cmd_list):
    """Runs a command and returns its stdout, stderr, and return code."""
    try:
        process = subprocess.run(
            cmd_list,
            capture_output=True,
            text=True,
            check=False, # Don't raise exception on non-zero exit
            timeout=10 # Add a timeout
        )
        return process.stdout, process.stderr, process.returncode
    except FileNotFoundError:
        # warn(f"Command not found: {cmd_list[0]}") # Handled contextually
        return None, f"Command not found: {cmd_list[0]}", -1 # Indicate command not found
    except subprocess.TimeoutExpired:
        return None, f"Command timed out: {' '.join(cmd_list)}", -2
    except Exception as e:
        return None, f"Error running command {' '.join(cmd_list)}: {e}", -3

def info(message):
    print(f"[INFO] {message}")

def warn(message):
    print(f"[WARN] {message}")
    state["warnings"].append(message)

def error(message):
    # Treat errors as warnings for reporting, but print as ERROR
    print(f"[ERROR] {message}")
    state["warnings"].append(f"ERROR: {message}")

def critical(message):
    print(f"[CRITICAL] {message}")
    state["critical_warnings"].append(f"CRITICAL: {message}")
    state["warnings"].append(f"CRITICAL: {message}") # Also add to general warnings

def suggest(message):
    state["suggestions"].append(message)

def check_file_for_pattern(filepath, pattern):
    """Checks if a file contains a pattern, ignoring comments."""
    try:
        with open(filepath, 'r', errors='ignore') as f:
            for line in f:
                stripped_line = line.strip()
                if stripped_line and not stripped_line.startswith('#'):
                    if pattern in stripped_line:
                        return True
    except FileNotFoundError:
        pass # File not existing isn't an error here
    except PermissionError:
        warn(f"Permission denied reading: {filepath}")
    except Exception as e:
        warn(f"Error reading {filepath}: {e}")
    return False

def find_files_recursive(dirs, pattern="*"):
    """Finds files matching a pattern in given directories recursively."""
    found_files = []
    for d in dirs:
        base_path = Path(d)
        if base_path.is_dir():
            found_files.extend(list(base_path.rglob(pattern)))
        elif base_path.is_file() and base_path.match(pattern): # Handle direct file paths too
             found_files.append(base_path)
    return [str(f) for f in found_files] # Return as strings
# FINISH ### UTILITY FUNCTIONS ###

# START ### KERNEL INFO CHECK ###
def check_kernel():
    info(f"Current Kernel: {KERNEL_VERSION}")
# FINISH ### KERNEL INFO CHECK ###

# START ### LOADED MODULES CHECK ###
def check_loaded_modules():
    info("Checking loaded kernel modules...")
    stdout, stderr, retcode = run_command(["lsmod"])

    if retcode != 0:
        error(f"Failed to run lsmod. Cannot check loaded modules. ({stderr.strip()})")
        return

    lines = stdout.splitlines()
    state["nvidia_loaded"] = any(line.startswith("nvidia ") for line in lines)
    state["nouveau_loaded"] = any(line.startswith("nouveau ") for line in lines)

    if state["nvidia_loaded"]:
        info("  - Nvidia driver module IS LOADED.")
    else:
        info("  - Nvidia driver module IS NOT loaded.")

    if state["nouveau_loaded"]:
        info("  - Nouveau driver module IS LOADED.")
    else:
        info("  - Nouveau driver module IS NOT loaded.")

    if not state["nvidia_loaded"] and not state["nouveau_loaded"]:
        info("  - Neither Nvidia nor Nouveau modules loaded (using basic video).")
    if state["nvidia_loaded"] and state["nouveau_loaded"]:
        warn("Both Nvidia AND Nouveau modules seem loaded - potential conflict.")
# FINISH ### LOADED MODULES CHECK ###

# START ### BLACKLIST CHECK ###
def check_blacklists():
    info(f"Checking module blacklists in {' '.join(MODPROBE_DIRS)} ...")
    nouveau_blacklisted = False
    nvidia_blacklisted = False
    config_files = find_files_recursive(MODPROBE_DIRS, "*.conf")
    config_files += find_files_recursive(MODPROBE_DIRS) # Get files without extension too

    for conf_file in set(config_files): # Use set to avoid duplicates
        if check_file_for_pattern(conf_file, "blacklist nouveau"):
            nouveau_blacklisted = True
        if check_file_for_pattern(conf_file, "blacklist nvidia"):
            nvidia_blacklisted = True

    state["nouveau_blacklisted"] = nouveau_blacklisted
    state["nvidia_blacklisted"] = nvidia_blacklisted

    if nouveau_blacklisted:
        info("  - Nouveau IS blacklisted.")
    else:
        info("  - Nouveau does NOT appear blacklisted.")

    if nvidia_blacklisted:
        info("  - Nvidia IS blacklisted (uncommon unless forcing Nouveau).")
    else:
        info("  - Nvidia does NOT appear blacklisted.")
# FINISH ### BLACKLIST CHECK ###

# START ### PACKAGE & DKMS CHECK ###
def check_packages_dkms():
    info("Checking relevant packages (using dpkg)...")
    stdout, stderr, retcode = run_command(["dpkg-query", "--version"])
    if retcode != 0:
        warn("dpkg-query command not found or failed. Cannot check package status.")
        return # Can't proceed with package checks

    # Check Nvidia package
    nvidia_patterns = ["nvidia-driver-*", "nvidia-tesla-*-driver", "nvidia-legacy-*-driver", "nvidia-dkms-*"]
    for pattern in nvidia_patterns:
        stdout, _, retcode = run_command(["dpkg-query", "-W", "-f=${Status}", pattern])
        # dpkg-query returns 0 if *any* package matches, even if not installed
        # So we check the output contains "install ok installed"
        if retcode == 0 and stdout and "install ok installed" in stdout:
            state["nvidia_pkg_installed"] = True
            break # Found one, that's enough

    if state["nvidia_pkg_installed"]:
        info("  - Nvidia driver package/DKMS appears installed.")
        check_dkms() # Check DKMS only if package is installed
    else:
        info("  - Nvidia driver package/DKMS NOT found.")

    # Check Nouveau package
    stdout, _, retcode = run_command(["dpkg-query", "-W", "-f=${Status}", "xserver-xorg-video-nouveau"])
    if retcode == 0 and stdout and "install ok installed" in stdout:
        state["nouveau_pkg_installed"] = True
        info("  - xserver-xorg-video-nouveau package IS installed.")
    else:
        info("  - xserver-xorg-video-nouveau package NOT found.")

    # Check Firmware package
    firmware_patterns = ["linux-firmware", "firmware-misc-nonfree"]
    for pattern in firmware_patterns:
         stdout, _, retcode = run_command(["dpkg-query", "-W", "-f=${Status}", pattern])
         if retcode == 0 and stdout and "install ok installed" in stdout:
            state["firmware_pkg_installed"] = True
            break

    if state["firmware_pkg_installed"]:
        info("  - Relevant firmware package (linux-firmware or firmware-misc-nonfree) IS installed.")
    else:
        info("  - Common firmware packages NOT found.")
        # Only warn if relevant (Nouveau likely used or Nvidia not installed)
        if not state["nvidia_pkg_installed"] or not state["nouveau_blacklisted"]:
             warn("Firmware package missing - may impact Nouveau stability/features.")

def check_dkms():
    info("Checking Nvidia DKMS status...")
    stdout, stderr, retcode = run_command(["dkms", "status"])

    if retcode == -1: # Command not found case from run_command
         warn("dkms command not found - unable to verify Nvidia module build.")
         state["dkms_ok"] = "N/A"
         return
    if retcode != 0:
         warn(f"dkms status command failed. Cannot verify module build. ({stderr.strip()})")
         state["dkms_ok"] = "N/A"
         return

    if not stdout or "nvidia" not in stdout.lower():
        info("  - No Nvidia DKMS modules found registered.")
        state["dkms_ok"] = False # Explicitly false if package installed but no dkms entry
        return

    dkms_lines = [line for line in stdout.lower().splitlines() if "nvidia" in line]
    found_for_kernel = False
    built_for_kernel = False
    for line in dkms_lines:
        if KERNEL_VERSION in line:
            found_for_kernel = True
            # Look for "installed" or "built" status for the current kernel
            if "installed" in line or "built" in line:
                 built_for_kernel = True
                 break # Found a good one

    if found_for_kernel:
        if built_for_kernel:
            state["dkms_ok"] = True
            info(f"  - DKMS module for Nvidia IS BUILT/installed for kernel {KERNEL_VERSION}.")
        else:
            state["dkms_ok"] = False
            error(f"DKMS shows Nvidia module for {KERNEL_VERSION} exists but status is NOT 'installed' or 'built'.")
    else:
        state["dkms_ok"] = False
        critical(f"Nvidia DKMS module IS NOT BUILT for current kernel {KERNEL_VERSION}! Nvidia boot will likely FAIL.")

# FINISH ### PACKAGE & DKMS CHECK ###

# START ### XORG CONFIG CHECK ###
def check_xorg_config():
    info("Checking Xorg configuration...")
    xorg_files = find_files_recursive(XORG_CONFIG_DIRS, "*.conf")
    # Also check for plain xorg.conf if it exists directly in the base dirs
    for d in XORG_CONFIG_DIRS:
        p = Path(d) / "xorg.conf"
        if p.is_file():
            xorg_files.append(str(p))

    found_nvidia_driver = False
    found_nouveau_driver = False

    for conf_file in set(xorg_files):
        try:
            with open(conf_file, 'r', errors='ignore') as f:
                for line in f:
                    stripped = line.strip()
                    if stripped.startswith("Driver"):
                        parts = stripped.split()
                        if len(parts) == 2:
                            driver_name = parts[1].strip('"\'')
                            if driver_name == "nvidia":
                                found_nvidia_driver = True
                            elif driver_name == "nouveau":
                                found_nouveau_driver = True
        except FileNotFoundError:
            pass
        except PermissionError:
            warn(f"Permission denied reading Xorg config: {conf_file}")
        except Exception as e:
            warn(f"Error reading Xorg config {conf_file}: {e}")

    if found_nvidia_driver:
        state["xorg_driver"] = "nvidia (explicit)"
        state["xorg_driver_found_in_config"] = True
        info("  - Found Xorg config explicitly setting Driver 'nvidia'.")
    elif found_nouveau_driver:
        state["xorg_driver"] = "nouveau (explicit)"
        state["xorg_driver_found_in_config"] = True
        info("  - Found Xorg config explicitly setting Driver 'nouveau'.")
    else:
        info("  - No explicit 'nvidia' or 'nouveau' Driver line detected in common Xorg configs.")
# FINISH ### XORG CONFIG CHECK ###

# START ### HARDWARE CHECK ###
def check_hardware():
    info("Checking PCI device list for Nvidia card...")
    lspci_cmd = ["lspci", "-nnk"] # Use -nnk for IDs and kernel driver info
    sudo_prefix = []

    # Try running without sudo first
    stdout, stderr, retcode = run_command(lspci_cmd)

    # If failed (often permission error without sudo for -k/-nnk), try sudo -n
    if retcode != 0 and os.geteuid() != 0:
        stdout_sudo_check, _, retcode_sudo_check = run_command(["sudo", "-n", "true"])
        if retcode_sudo_check == 0: # Check if passwordless sudo is possible
             stdout_sudo, stderr_sudo, retcode_sudo = run_command(["sudo"] + lspci_cmd)
             if retcode_sudo == 0:
                 stdout, stderr, retcode = stdout_sudo, stderr_sudo, retcode_sudo
                 sudo_prefix = ["sudo"] # Mark that we used sudo
             else:
                # sudo -n true worked, but sudo lspci failed? Unusual. Fallback to non-sudo.
                warn("Tried sudo lspci, but it failed. Using potentially limited non-sudo output.")
                state["lspci_sudo_warn"] = True
        else:
             # Cannot run passwordless sudo
             warn("Could not run lspci with sudo without password. Output might be limited.")
             state["lspci_sudo_warn"] = True
             # Stick with the non-sudo result, even if it failed.

    state["lspci_ran_ok"] = (retcode == 0)

    if not state["lspci_ran_ok"]:
        error(f"Failed to run lspci command ({' '.join(sudo_prefix + lspci_cmd)}). Cannot check hardware. Error: {stderr.strip()}")
        return

    # Parse the output
    found_nvidia_vga = False
    lines = stdout.splitlines()
    for line in lines:
        # Look for VGA compatible or 3D controller lines containing NVIDIA vendor ID [10de] or name
        if ("VGA compatible controller" in line or "3D controller" in line):
            if "NVIDIA" in line.upper() or "[10de:" in line:
                 found_nvidia_vga = True
                 break # Found one

    if found_nvidia_vga:
        state["nvidia_hw_detected"] = True
        info("  - Nvidia graphics hardware DETECTED.")
    else:
        # Changed from error to warning in Bash, keeping that here
        warn("Nvidia graphics hardware NOT detected via lspci (or permission issue/limited output)!")

# FINISH ### HARDWARE CHECK ###


# START ### ANALYSIS & SUGGESTIONS ###
def analyze_state():
    info("--- Analysis & Suggestions ---")

    s = state # Shortcut

    # Scenario 1: Looks like functional Nvidia setup
    if s["nvidia_pkg_installed"] and s["dkms_ok"] is True and s["nouveau_blacklisted"]:
        suggest("Primary setup appears functional Nvidia (DKMS OK, Nouveau blacklisted).")
        suggest("Suggest standard Nvidia boot (e.g., with nvidia-drm.modeset=1).")
        if not s["nvidia_loaded"]:
            warn("Nvidia setup OK but module not loaded? Check initramfs/current session (may load on reboot).")
        if s["xorg_driver_found_in_config"] and "nvidia" not in s["xorg_driver"]:
            warn(f"Xorg config sets non-Nvidia driver ('{s['xorg_driver']}'), may conflict.")

    # Scenario 2: Looks like functional Nouveau setup (Nvidia explicitly blacklisted)
    elif s["nouveau_pkg_installed"] and s["nvidia_blacklisted"]:
        suggest("Primary setup appears Nouveau (Nvidia driver likely blacklisted/not primary).")
        suggest("Suggest standard GUI/TTY boot options (likely default).")
        if not s["nouveau_loaded"] and s["firmware_pkg_installed"]: # Only warn if firmware present
            warn("Setup seems Nouveau, but module not loaded? Check session (may load on reboot).")
        if s["xorg_driver_found_in_config"] and "nouveau" not in s["xorg_driver"]:
            warn(f"Xorg config sets non-Nouveau driver ('{s['xorg_driver']}'), may conflict.")

    # Scenario 3: Looks like Nouveau setup (Nvidia not installed)
    elif s["nouveau_pkg_installed"] and not s["nouveau_blacklisted"] and not s["nvidia_pkg_installed"]:
        suggest("Setup appears Nouveau (Nvidia not installed, Nouveau active).")
        suggest("Suggest standard GUI/TTY boot options (likely default).")

    # Scenario 4: Nvidia installed but DKMS failed/missing *** CRITICAL ***
    elif s["nvidia_pkg_installed"] and s["dkms_ok"] is False:
        suggest(f"Nvidia installed BUT DKMS module MISSING/FAILED for kernel {KERNEL_VERSION}.")
        suggest("!!! Nvidia boot WILL LIKELY FAIL !!!")
        suggest("STRONGLY recommend booting 'nomodeset' / safe mode / previous kernel.")
        suggest("Fix DKMS (reinstall nvidia-dkms? Check headers? Check logs: /var/lib/dkms/nvidia/.../build/make.log).")

    # Scenario 5: Nvidia loaded, but Nouveau not blacklisted (potential conflict)
    elif s["nvidia_loaded"] and not s["nouveau_blacklisted"]:
        warn("Nvidia loaded, but Nouveau NOT blacklisted. Potential conflict at boot.")
        suggest("Suggest blacklisting Nouveau (/etc/modprobe.d/) and updating initramfs (sudo update-initramfs -u) for reliable Nvidia boot.")
        suggest("Try Nvidia options, but have 'nomodeset' ready.")

    # Scenario 6: Nouveau loaded, but also blacklisted (conflicting state)
    elif s["nouveau_loaded"] and s["nouveau_blacklisted"]:
        warn("Nouveau loaded, but it's ALSO blacklisted? Conflicting state (maybe initramfs issue?).")
        suggest("Review blacklist files and update initramfs (sudo update-initramfs -u).")
        suggest("Boot unpredictable. Safest bet: 'nomodeset' or basic TTY first.")

    # Scenario 7: Catch-all / Ambiguous states
    else:
        suggest("Could not determine clear optimal setup based on common patterns.")
        # Sub-case: Nvidia seems ready but Nouveau isn't blacklisted
        if s["nvidia_pkg_installed"] and s["dkms_ok"] is True and not s["nouveau_blacklisted"]:
           warn("Nvidia appears ready (DKMS OK), but Nouveau NOT blacklisted. Potential conflict!")
           suggest("Strongly suggest blacklisting Nouveau and updating initramfs.")
           suggest("Try Nvidia boot options, have 'nomodeset' ready.")
        # Sub-case: Neither driver seems installed
        elif not s["nvidia_pkg_installed"] and not s["nouveau_pkg_installed"]:
           warn("Neither Nvidia nor Nouveau packages seem installed. Basic display likely.")
           suggest("Install appropriate driver (Nouveau usually default if firmware present).")
        # Generic fallback for other unclear situations
        else:
           suggest("Suggest safe option: 'nomodeset' or basic TTY.")
           suggest("Review modules, blacklists, packages manually for inconsistencies.")

    # Always add fallback advice
    suggest("ALWAYS have a 'nomodeset' or recovery/previous kernel boot option available.")
# FINISH ### ANALYSIS & SUGGESTIONS ###

# START ### REPORT OUTPUT ###
def print_report():
    print("")
    print("*** REPORT SUMMARY ***")

    if state["warnings"]:
        print("")
        print("!! WARNINGS !!")
        # Prioritize critical warnings if any exist
        crit_set = set(state["critical_warnings"])
        for warn_msg in state["critical_warnings"]:
             print(f"  - {warn_msg}")
        # Print non-critical warnings
        for warn_msg in state["warnings"]:
            if warn_msg not in crit_set:
                print(f"  - {warn_msg}")
        print("!!"----------!!")

    print("")
    print(">> SUGGESTED ACTIONS <<")
    if state["suggestions"]:
        for sugg_msg in state["suggestions"]:
            print(f"  -> {sugg_msg}")
    else:
        print("  -> No specific suggestions generated.") # Handle empty array case
    print(">>-----------------<<")

    print("")
    print("--- Check Complete ---")
    print("Remember: This is intel, not a guarantee. Choose your boot option wisely.")
# FINISH ### REPORT OUTPUT ###

# START ### MAIN FUNCTION ###
def main():
    print("--- Pre-Boot Graphics State Check (Python Edition) ---")
    print("Gathering intel... Be patient, my boy.")
    print("")

    check_kernel()
    check_loaded_modules()
    check_blacklists()
    check_packages_dkms() # This internally calls check_dkms if needed
    check_xorg_config()
    check_hardware()
    analyze_state()
    print_report()

# FINISH ### MAIN FUNCTION ###

# START ### SCRIPT RUNNER ###
if __name__ == "__main__":
    main()
    # Exit with 0 explicitly, assuming script completion is success
    # Actual issues are conveyed via warnings/suggestions
    exit(0)
# FINISH ### SCRIPT RUNNER ###
