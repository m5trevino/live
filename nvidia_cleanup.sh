#!/bin/bash

echo "Starting NVIDIA cleanup..."

# Stop display manager
echo "Stopping GDM3..."
sudo systemctl stop gdm3
sudo systemctl isolate multi-user.target

# Remove all NVIDIA packages
echo "Removing NVIDIA packages..."
sudo apt-get remove --purge '^nvidia-.*' -y
sudo apt-get remove --purge '^libnvidia-.*' -y
sudo apt-get remove --purge '^cuda-.*' -y
sudo apt autoremove -y

# Clean config files
echo "Cleaning config files..."
sudo rm -f /etc/modprobe.d/blacklist-nvidia*
sudo rm -f /etc/modprobe.d/nvidia-graphics-drivers.conf
sudo rm -rf /etc/X11/xorg.conf

# Clean NVIDIA directories
echo "Cleaning NVIDIA directories..."
sudo rm -rf /usr/lib/nvidia*
sudo rm -rf /var/lib/nvidia*

# Update initramfs
echo "Updating initramfs..."
sudo update-initramfs -u

echo "Cleanup complete! Ready to reboot."
echo "Run 'sudo reboot' when ready."
#!/bin/bash

echo "Starting NVIDIA cleanup..."

# Stop display manager
echo "Stopping GDM3..."
sudo systemctl stop gdm3
sudo systemctl isolate multi-user.target

# Remove all NVIDIA packages
echo "Removing NVIDIA packages..."
sudo apt-get remove --purge '^nvidia-.*' -y
sudo apt-get remove --purge '^libnvidia-.*' -y
sudo apt-get remove --purge '^cuda-.*' -y
sudo apt autoremove -y

# Clean config files
echo "Cleaning config files..."
sudo rm -f /etc/modprobe.d/blacklist-nvidia*
sudo rm -f /etc/modprobe.d/nvidia-graphics-drivers.conf
sudo rm -rf /etc/X11/xorg.conf

# Clean NVIDIA directories
echo "Cleaning NVIDIA directories..."
sudo rm -rf /usr/lib/nvidia*
sudo rm -rf /var/lib/nvidia*

# Update initramfs
echo "Updating initramfs..."
sudo update-initramfs -u

echo "Cleanup complete! Ready to reboot."
echo "Run 'sudo reboot' when ready."
