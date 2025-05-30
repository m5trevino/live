#!/bin/sh

PATH=/sbin:$PATH

export LC_ALL=C

exec >&3

echo "uname -a:"
uname -a
echo

echo "/proc/version:"
cat /proc/version
echo

if [ -e /proc/driver/nvidia/version ]; then
	echo "/proc/driver/nvidia/version:"
	cat /proc/driver/nvidia/version
	echo
fi

if (lspci --version) > /dev/null 2>&1; then
	echo "lspci 'display controller [030?]':"
	for device in $(lspci -mn | awk '{ if ($2 ~ "\"030[0-2]\"") { print $1 } }'); do
		LC_ALL=C lspci -vvnn -s $device
	done
fi

if [ -x /bin/dmesg ]; then
	echo "dmesg:"
	dmesg | grep -iE 'nvidia|nvrm|agp|vga'
	echo
fi

echo "Device node permissions:"
ls -l /dev/dri/* /dev/nvidia* 2>/dev/null
getent group video
echo

echo "Alternative 'nvidia':"
update-alternatives --display nvidia
echo

echo "Alternative 'glx':"
update-alternatives --display glx
echo

echo "OpenGL and NVIDIA library files installed:"
ls -l	/etc/alternatives/glx* \
	/etc/alternatives/nvidia* \
	/etc/alternatives/*libGL* \
	/etc/alternatives/*_gl_conf \
	/etc/ld.so.conf.d/*_GL.conf \
	/etc/X11/*.conf \
	/usr/lib/libEGL.* \
	/usr/lib/libGL.* \
	/usr/lib/libGLES*.* \
	/usr/lib/libGLcore* \
	/usr/lib/libcuda* \
	/usr/lib/libnvidia* \
	/usr/lib/*-linux-gnu*/libEGL.* \
	/usr/lib/*-linux-gnu*/libGL.* \
	/usr/lib/*-linux-gnu*/libGLES*.* \
	/usr/lib/*-linux-gnu*/libGLcore* \
	/usr/lib/*-linux-gnu*/libcuda* \
	/usr/lib/*-linux-gnu*/libnvidia* \
	/usr/lib32/libGL.* \
	/usr/lib32/libGLcore* \
	/usr/lib32/libnvidia* \
	/usr/lib/xorg/modules/*glx* \
	/usr/lib/xorg/modules/*/*glx* \
	/usr/lib/xorg/modules/*nvidia* \
	/usr/lib/xorg/modules/*/*nvidia* \
	/var/log/Xorg.*.log* \
	2>/dev/null

ls -la	\
	/etc/nvidia/ \
	/etc/OpenCL/vendors/ \
	/usr/lib/nvidia/ \
	/usr/lib/nvidia/*/ \
	/usr/lib/*-linux-gnu*/nvidia/ \
	/usr/lib/*-linux-gnu*/nvidia/*/ \
	/usr/lib/mesa/ \
	/usr/lib/*-linux-gnu*/mesa/ \
	/usr/lib/mesa-diverted/ \
	/usr/lib/mesa-diverted/*-linux-gnu*/ \
	/usr/lib32/nvidia/ \
	/usr/lib32/nvidia/diversions/ \
	/etc/X11/xorg.conf.d/ \
	/usr/share/X11/xorg.conf.d/ \
	2>/dev/null
echo

echo "/etc/modprobe.d:"
ls -la /etc/modprobe.d/
echo
grep -ri nvidia /etc/modprobe.d/
grep -ri nouveau /etc/modprobe.d/
echo

echo "/etc/modules-load.d:"
ls -la /etc/modules /etc/modules-load.d/ 2>&1
echo
grep -ri nvidia /etc/modules /etc/modules-load.d/ 2>/dev/null
grep -ri nouveau /etc/modules /etc/modules-load.d/ 2>/dev/null
echo

echo "Files from nvidia-installer:"
ls -la /usr/bin/nvidia-installer /usr/bin/nvidia-uninstall /var/lib/nvidia 2>/dev/null
echo

echo "Config and logfiles:"
echo
for file in \
	/etc/bumblebee/bumblebee.conf \
	/etc/bumblebee/xorg.conf.nvidia \
	/etc/modprobe.d/*nvidia*.conf \
	/etc/X11/xorg.conf \
	/etc/X11/xorg.conf.d/*.conf \
	$(ls -dt $HOME/.local/share/xorg/Xorg.*.log* 2>/dev/null | head -n 2) \
	$(ls -dt /var/log/Xorg.*.log* 2>/dev/null | head -n 2)
do
	if [ -f "$file" ] && [ -r "$file" ]; then
		echo "<<<<<<<<<< $file >>>>>>>>>>"
		cat "$file"
		echo "^^^^^^^^^^ $file ^^^^^^^^^^"
		echo
	fi
done

if [ -d /run/systemd/system ]; then
	echo "<<<<<<<<<< Xorg (journald) >>>>>>>>>>"
	journalctl -b _COMM=Xorg --no-pager
	echo "^^^^^^^^^^ Xorg (journald) ^^^^^^^^^^"
	echo
fi

echo "Kernel modules: nvidia.ko"
find /lib/modules -name "nvidia*.ko"
echo
find /lib/modules -name "nvidia*.ko" | xargs -r modinfo | grep -v ^parm:
echo

echo "lsmod:"
lsmod
echo

echo "xrandr:"
test ! -x /usr/bin/xrandr || xrandr 2>&1
echo

echo "OpenCL ICDs:"
grep -H . /etc/OpenCL/vendors/* 2>/dev/null
echo

echo "APT sources:"
apt-cache policy
echo

exit 0
