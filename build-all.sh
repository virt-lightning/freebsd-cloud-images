#!/bin/bash
set -eux
pkg install -y curl qemu-utils
function build {
    VERSION=$1
    BASE_URL="ftp://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/${VERSION}-RELEASE"
    WORK_DIR="/root/work_dir_${VERSION}"
    mkdir ${WORK_DIR}
    curl -L ${BASE_URL}/base.txz | tar vxf - -C ${WORK_DIR}
    curl -L ${BASE_URL}/kernel.txz | tar vxf - -C ${WORK_DIR}
    curl -L -o ${WORK_DIR}/tmp/freebsd.tar.gz https://github.com/goneri/cloud-init/archive/freebsd.tar.gz
    echo "
export ASSUME_ALWAYS_YES=YES
cd /tmp
pkg install -y ca_root_nss
tar xf freebsd.tar.gz
cd cloud-init-freebsd
mkdir -p /usr/local/etc/rc.d
./tools/build-on-freebsd
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
    mkimg -s gpt -b ${WORK_DIR}/boot/pmbr -p efi:=${WORK_DIR}/boot/boot1.efifat -p freebsd-boot:=${WORK_DIR}/boot/gptboot -p freebsd-swap/swapfs::1G -p freebsd-ufs/rootfs:=./ufs -o freebsd-${VERSION}.raw
    qemu-img convert -c -f raw -O qcow2 freebsd-${VERSION}.raw freebsd-${VERSION}.qcow2
    chflags -R noschg ${WORK_DIR}
    rm -r ${WORK_DIR} freebsd-${VERSION}.raw
}

build 12.0
build 11.2
build 10.4
