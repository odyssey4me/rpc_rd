#!/bin/bash

EXPECTEDARGS=1
if [ $# -lt $EXPECTEDARGS ]; then
    echo "You didn't provide a qcow. Downloading Ubuntu for you instead..."
    echo ""

    # Pull Ubuntu 16.04.2 qcow
    wget \
        https://cloud-images.ubuntu.com/releases/16.04/release-20170330/ubuntu-16.04-server-cloudimg-amd64-disk1.img \
        -O ubuntu-16.04.2-server-cloudimg-amd64-disk1.img
    INPUT_PATH=$(readlink -f ./ubuntu-16.04.2-server-cloudimg-amd64-disk1.img)

else
    INPUT_PATH=$(readlink -f $1)
fi

# find the latest ISO version here:
# http://bootrackspacecom.readthedocs.io/en/latest/image_creation/
XEN_ISO_FILE="xs-tools-6.5.0-20200.iso"

if [[ ! -e "${XEN_ISO_FILE}" ]]; then
    # download the ISO
    wget http://boot.rackspace.com/files/xentools/${XEN_ISO_FILE}
fi

# find the latest version here
# http://bootrackspacecom.readthedocs.io/en/latest/nova_agent/
NOVA_AGENT_FILE="nova-agent-Linux-x86_64-1.39.0.tar.gz"

if [[ ! -e "${NOVA_AGENT_FILE}" ]]; then
    # download the agent
    wget http://boot.rackspace.com/files/nova-agent/${NOVA_AGENT_FILE}
fi

# Mount qcow & give it access to sys resources & Internet
sudo modprobe nbd max_part=14
sudo qemu-nbd -c /dev/nbd0 $INPUT_PATH
sudo mkdir /mnt/image

sudo mount /dev/nbd0p1 /mnt/image
sudo mount --bind /dev /mnt/image/dev
sudo mount --bind /proc /mnt/image/proc
sudo mv /mnt/image/etc/resolv.conf /mnt/image/etc/resolv.conf.bak
sudo cp -f /etc/resolv.conf /mnt/image/etc/resolv.conf

# Ensure that only the base Ubuntu repo from the Rackspace mirror is configured
if [[ "${INPUT_PATH}" == *"14.04"* ]]; then
    echo 'deb http://mirror.rackspace.com/ubuntu trusty main universe' > /mnt/image/etc/apt/sources.list
elif [[ "${INPUT_PATH}" == *"16.04"* ]]; then
    echo 'deb http://mirror.rackspace.com/ubuntu xenial main universe' > /mnt/image/etc/apt/sources.list
fi

# Modify qcow to work for RAX public cloud
pushd distro_scripts
    if [[ "${INPUT_PATH}" == *"14.04"* ]]; then
        sudo cp ubuntu_14.04.sh /mnt/image/tmp/
        sudo chroot /mnt/image /bin/bash -c "su - -c 'cd /tmp ; ./ubuntu_14.04.sh'"
    elif [[ "${INPUT_PATH}" == *"16.04"* ]]; then
        sudo cp ubuntu_16.04.sh /mnt/image/tmp/
        sudo cp ${XEN_ISO_FILE} /mnt/image/tmp/
        sudo cp ${NOVA_AGENT_FILE} /mnt/image/tmp/
        sudo chroot /mnt/image /bin/bash -c "su - -c 'cd /tmp ; ./ubuntu_16.04.sh'"
    fi
popd

# Unmount modified qcow & cleanup
sudo mv /mnt/image/etc/resolv.conf.bak /mnt/image/etc/resolv.conf
sudo rm -rf /mtn/image/tmp/*
sudo umount -l /mnt/image/dev/
sudo umount -l /mnt/image/proc/
sudo umount -l /mnt/image
sudo qemu-nbd -d /dev/nbd0
sudo rm -rf /mnt/image
