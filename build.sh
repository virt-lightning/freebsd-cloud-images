#!/bin/bash
version=$1
if [ -z $version ]; then
    echo "Usage $0 version"
    exit 1
fi
set -eux

function build {
    VERSION=$1
    BASE_URL="ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${VERSION}-RELEASE"
    WORK_DIR="/root/work_dir_${VERSION}"
    mkdir ${WORK_DIR}
    curl -L ${BASE_URL}/base.txz | tar vxf - -C ${WORK_DIR}
    curl -L ${BASE_URL}/kernel.txz | tar vxf - -C ${WORK_DIR}
    curl -L -o ${WORK_DIR}/tmp/netbsd.tar.gz https://github.com/goneri/cloud-init/archive/netbsd.tar.gz
    echo "
export ASSUME_ALWAYS_YES=YES
cd /tmp
pkg install -y ca_root_nss
tar xf netbsd.tar.gz
cd cloud-init-netbsd
touch /etc/rc.conf
mkdir -p /usr/local/etc/rc.d
pkg install -y python3
./tools/build-on-freebsd
#pw mod user root -w no  # Lock root account
" > ${WORK_DIR}/tmp/cloudify.sh
chmod +x ${WORK_DIR}/tmp/cloudify.sh
cp /etc/resolv.conf ${WORK_DIR}/etc/resolv.conf
mount -t devfs devfs ${WORK_DIR}/dev
chroot ${WORK_DIR} /tmp/cloudify.sh
umount ${WORK_DIR}/dev
echo '' > ${WORK_DIR}/etc/resolv.conf
echo '/dev/gpt/rootfs   /       ufs     rw      1       1
/dev/gpt/swapfs  none    swap    sw      0       0
' > ${WORK_DIR}/etc/fstab


    echo 'boot_multicons="YES"' >> ${WORK_DIR}/boot/loader.conf
    echo 'boot_serial="YES"' >> ${WORK_DIR}/boot/loader.conf
    echo 'comconsole_speed="115200"' >> ${WORK_DIR}/boot/loader.conf
    echo 'autoboot_delay="1"' >> ${WORK_DIR}/boot/loader.conf
    echo 'console="comconsole,vidconsole"' >> ${WORK_DIR}/boot/loader.conf
    echo '-P' >> ${WORK_DIR}/boot.config

    echo 'sshd_enable="YES"' >> ${WORK_DIR}/etc/rc.conf
    echo 'sendmail_enable="NONE"' >> ${WORK_DIR}/etc/rc.conf
    makefs -B little -o label=freebsd_root ./ufs ${WORK_DIR}
    mkimg -s gpt -b ${WORK_DIR}/boot/pmbr -p efi:=${WORK_DIR}/boot/boot1.efifat -p freebsd-boot:=${WORK_DIR}/boot/gptboot -p freebsd-swap/swapfs::1G -p freebsd-ufs/rootfs:=./ufs -o final.raw
    chflags -R noschg ${WORK_DIR}
    rm -r ${WORK_DIR}
}

#pkg install -y curl qemu-utils
build $version
