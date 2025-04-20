#!/bin/bash
# Script to switch the systemd target to the full graphical environment

echo "Switching system target to 'graphical.target'..."
echo "This will start the display manager and all associated services."
echo "You may be logged out of this text console."

if sudo systemctl isolate graphical.target; then
    echo "Successfully initiated switch to graphical target."
    # It might take a moment for the switch to complete.
else
    echo "ERROR: Failed to isolate graphical.target. Check systemd logs."
    exit 1
fi

exit 0
#!/bin/bash
# Script to switch the systemd target to the full graphical environment

echo "Switching system target to 'graphical.target'..."
echo "This will start the display manager and all associated services."
echo "You may be logged out of this text console."

if sudo systemctl isolate graphical.target; then
    echo "Successfully initiated switch to graphical target."
    # It might take a moment for the switch to complete.
else
    echo "ERROR: Failed to isolate graphical.target. Check systemd logs."
    exit 1
fi

exit 0
