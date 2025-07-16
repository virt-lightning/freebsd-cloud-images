#!/bin/sh
# Borrowed from https://github.com/virt-lightning/freebsd-cloud-images/blob/master/build.sh
# and modified.
version="${1:-14.2}"
repo="${2:-canonical/cloud-init}"
ref="${3:-main}"
debug=$4
install_media="${install_media:-http}"

set -euxo pipefail
root_fs="${root_fs:-ufs}"  # ufs or zfs

build() {
    VERSION=$1
    BASE_URL="http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${VERSION}-RELEASE"
    if ! fetch -q $BASE_URL; then
        BASE_URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/${VERSION}-RELEASE"
    fi


    if [ ${root_fs} = "zfs" ]; then
        gptboot=/boot/gptzfsboot
    else
        gptboot=/boot/gptboot
    fi

    dd if=/dev/zero of=final.raw bs=1148576 count=3000
    md_dev=$(mdconfig -a -t vnode -f final.raw)
    gpart create -s gpt ${md_dev}
    gpart add -t freebsd-boot -s 1024 ${md_dev}
    gpart bootcode -b /boot/pmbr -p ${gptboot} -i 1 ${md_dev}
    gpart add -t efi -s 128M ${md_dev}
    gpart add -t freebsd-${root_fs} -l rootfs ${md_dev}
    newfs_msdos -F 32 -c 1 /dev/${md_dev}p2
    mount -t msdosfs /dev/${md_dev}p2 /mnt
    mkdir -p /mnt/EFI/BOOT
    cp /boot/loader.efi /mnt/EFI/BOOT/BOOTX64.efi
    umount /mnt

    if [ ${root_fs} = "zfs" ]; then
        zpool create -o altroot=/mnt zroot ${md_dev}p3
        zfs set compress=on  zroot
        zfs create -o mountpoint=none                                  zroot/ROOT
        zfs create -o mountpoint=/ -o canmount=noauto                  zroot/ROOT/default
        mount -t zfs zroot/ROOT/default /mnt
        zpool set bootfs=zroot/ROOT/default zroot
    else
        newfs -U -L FreeBSD /dev/${md_dev}p3
        tunefs -p /dev/${md_dev}p3
        mount /dev/${md_dev}p3 /mnt
    fi


    fetch -o - ${BASE_URL}/base.txz | tar vxf - -C /mnt
    fetch -o - ${BASE_URL}/kernel.txz | tar vxf - -C /mnt
    fetch -o /mnt/tmp/cloud-init.tar.gz "https://github.com/${repo}/archive/${ref}.tar.gz"
    echo "
PAGER=""
freebsd-update --currently-running ${version}-RELEASE fetch --not-running-from-cron
freebsd-update --currently-running ${version}-RELEASE install
export ASSUME_ALWAYS_YES=YES
cd /tmp
pkg install -y ca_root_nss
tar xf cloud-init.tar.gz
cd cloud-init-*
pkg install -y python3 qemu-guest-agent
touch /etc/rc.conf
./tools/build-on-freebsd
" > /mnt/tmp/cloudify.sh

    if [ -z "${debug}" ]; then # Lock root account
        echo "pw mod user root -w no" >> /mnt/tmp/cloudify.sh
    else
        echo 'echo "!234AaAa56" | pw usermod -n root -h 0' >> /mnt/tmp/cloudify.sh
    fi

    chmod +x /mnt/tmp/cloudify.sh

    cp /etc/resolv.conf /mnt/etc/resolv.conf
    mount -t devfs devfs /mnt/dev
    chroot /mnt /tmp/cloudify.sh
    umount /mnt/dev
    rm /mnt/tmp/cloudify.sh
    echo '' > /mnt/etc/resolv.conf
    if [ ${root_fs} = "ufs" ]; then
        echo '/dev/gpt/rootfs   /       ufs     rw      1       1' >>  /mnt/etc/fstab
    fi

    echo 'boot_multicons="YES"' >> /mnt/boot/loader.conf
    echo 'boot_serial="YES"' >> /mnt/boot/loader.conf
    echo 'comconsole_speed="115200"' >> /mnt/boot/loader.conf
    echo 'autoboot_delay="-1"' >> /mnt/boot/loader.conf
    echo 'console="comconsole,efi"' >> /mnt/boot/loader.conf
    echo 'beastie_disable="YES"' >>/mnt/boot/loader.conf
    echo '-P' >> /mnt/boot.config
    rm -rf /mnt/tmp/*
    echo 'clear_tmp_enable="YES"' >>/mnt/etc/rc.conf
    echo 'sshd_enable="YES"' >> /mnt/etc/rc.conf
    echo 'sendmail_enable="NONE"' >> /mnt/etc/rc.conf

    echo 'qemu_guest_agent_enable="YES"' >> /mnt/etc/rc.conf
    echo 'qemu_guest_agent_flags="-d -v -l /var/log/qemu-ga.log"' >> /mnt/etc/rc.conf

    echo "/etc/rc.conf"
    echo "***"
    cat /mnt/etc/rc.conf
    echo "***"

    if [ ${root_fs} = "zfs" ]; then
        echo 'zfs_load="YES"' >> /mnt/boot/loader.conf
        echo 'vfs.root.mountfrom="zfs:zroot/ROOT/default"' >> /mnt/boot/loader.conf
        echo 'zfs_enable="YES"' >> /mnt/etc/rc.conf

        # make sure the directory exists before creating cloud.cfg
        mkdir -p /mnt/etc/cloud
        echo 'growpart:
   mode: auto
   devices:
      - /dev/vtbd0p3
      - /
' >> /mnt/etc/cloud/cloud.cfg
    fi

    if [ ${root_fs} = "zfs" ]; then
        ls /mnt
        ls /mnt/sbin
        ls /mnt/sbin/init
        zpool export zroot
    else
        umount /dev/${md_dev}p3
    fi
    mdconfig -du ${md_dev}
}

build $version
