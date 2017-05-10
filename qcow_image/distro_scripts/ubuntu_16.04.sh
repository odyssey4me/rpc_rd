#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    cloud-init \
    cloud-initramfs-copymods \
    cloud-initramfs-dyn-netconf \
    cloud-initramfs-growroot

#
# Install xentools
#

# tmpmount it
mkdir xentmp
XEN_ISO_FILE=$(ls -1 /tmp/xs-tools-*.iso)
mount -o loop "${XEN_ISO_FILE}" xentmp

# execute the install
pushd xentmp/Linux
    ./install.sh -n
popd

# dismount and clean it up
umount -l xentmp
rm -rf xentmp "${XEN_ISO_FILE}"

#
# install nova agent
#

# extract it
cd ~/
mkdir nova-agent
cd nova-agent
tar xzf "/tmp/nova-agent-*.tar.gz"

# execute the install
./installer.sh

# Inject the LSB-Headers into the init Script
sed '1i### BEGIN INIT INFO\n# Provides: Nova-Agent\n# Required-Start: $remote_fs $syslog\n# Required-Stop: $remote_fs $syslog\n# Default-Start: 2 3 4 5\n# Default-Stop: 0 1 6\n# Short-Description: Start daemon at boot time\n# Description: Enable service provided by daemon.\n### END INIT INFO\n' /usr/share/nova-agent/1.39.0/etc/generic/nova-agent > /usr/share/nova-agent/1.39.0/etc/generic/nova-agent.lsb

# Move the init script in place and make it executable
cp -av /usr/share/nova-agent/1.39.0/etc/generic/nova-agent.lsb /etc/init.d/nova-agent
chmod +x /etc/init.d/nova-agent

# Set it to start by default
update-rc.d -f nova-agent defaults

# clean up
cd ..
rm -rf nova-agent "/tmp/nova-agent-*.tar.gz"

#
# Configure cloud-init
#

# cloud-init config
cat > /etc/cloud/cloud.cfg.d/10_rackspace.cfg <<'EOF'
apt_preserve_sources_list: True
disable_root: False
ssh_pwauth: True
ssh_deletekeys: True
resize_rootfs: True
EOF

# cloud-init kludges
addgroup --system --quiet netdev
echo -n > /etc/udev/rules.d/70-persistent-net.rules
echo -n > /lib/udev/rules.d/75-persistent-net-generator.rules

#
# Misc config
#

# both the above and preseed values quit working :(
cat > /etc/cloud/cloud.cfg.d/90_dpkg.cfg <<'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ ConfigDrive, None ]
EOF

# minimal network conf that doesnt dhcp
# causes boot delay if left out, no bueno
cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback
EOF

# stage a clean hosts file
cat > /etc/hosts <<'EOF'
# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
127.0.0.1 localhost
EOF

# set some stuff
echo 'net.ipv4.conf.eth0.arp_notify = 1' >> /etc/sysctl.conf
echo 'vm.swappiness = 0' >> /etc/sysctl.conf

# RAX fstab is funky
cat > /etc/fstab <<'EOF'
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/xvda1    /               ext3    errors=remount-ro,noatime,barrier=0 0       1
#/dev/xvdc1    none            swap    sw              0       0
EOF

# keep grub2 from using UUIDs and regenerate config
sed -i 's/#GRUB_DISABLE_LINUX_UUID.*/GRUB_DISABLE_LINUX_UUID="true"/g' /etc/default/grub
update-grub

unset UCF_FORCE_CONFFOLD
export UCF_FORCE_CONFFNEW=YES
ucf --purge /boot/grub/menu.lst

# grub legacy for PV Xen guests
apt-get -y remove --purge grub*
rm -rf /boot/grub*
apt-get -y install grub-legacy-ec2
sed -i 's/# indomU.*/# indomU=true/' /boot/grub/menu.lst
sed -i 's/# kopt=.*/# kopt=root=\/dev\/xvda1 console=hvc0 ro quiet splash/' /boot/grub/menu.lst
update-grub-legacy-ec2 -y

# set ssh keys to regenerate at first boot if missing
# this is a fallback to catch when cloud-init fails doing the same
# it will do nothing if the keys already exist
cat > /etc/rc.local <<'EOF'
dpkg-reconfigure openssh-server
echo > /etc/rc.local
EOF

# console fix for PV Ubuntus
cat > /etc/init/hvc0.conf <<'EOF'

# hvc0 - getty
#
# This service maintains a getty on hvc0 from the point the system is
# started until it is shut down again.

start on stopped rc or RUNLEVEL=[2345]
stop on runlevel [!2345]

respawn
exec /sbin/getty -L 115200 hvc0 vt102
EOF

cat > /etc/apt/apt.conf.d/00InstallRecommends <<'EOF'
APT::Install-Recommends "true";
EOF

# the beta version didn't do this, but release set it to "without-password" which fails
sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config

#
# Clean up
#
apt-get -y clean
apt-get -y autoremove
sed -i '/.*cdrom.*/d' /etc/apt/sources.list
rm -f /etc/ssh/ssh_host_*
rm -f /var/cache/apt/archives/*.deb
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*_Packages
# breaks newest nova-agent if removed
#rm -f /etc/resolv.conf
# this file copies the installer's /etc/network/interfaces to the VM
# but we want to overwrite that with a "clean" file instead
# so we must disable that copying action in kickstart/preseed
rm -f /usr/lib/finish-install.d/55netcfg-copy-config
rm -f /root/.bash_history
rm -f /root/.nano_history
rm -f /root/.lesshst
rm -f /root/.ssh/known_hosts
rm -rf /tmp/tmp
for k in $(find /var/log -type f); do echo > $k; done
for k in $(find /tmp -type f); do rm -f $k; done
for k in $(find /root -type f \( ! -iname ".*" \)); do rm -f $k; done
