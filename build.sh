#!/bin/bash
version=$1
repo=$2
ref=$3
debug=$4
if [ -z "$version" ]; then
    version="12.1"
fi
if [ -z "${repo}" ]; then
    repo="canonical/cloud-init"
fi
if [ -z "${debug}" ]; then
    debug=""
fi
set -eux

function build {
    VERSION=$1
    BASE_URL="http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${VERSION}-RELEASE"
    if ! curl --fail --silent $BASE_URL; then
        BASE_URL="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/${VERSION}-RELEASE"
    fi
    WORK_DIR="/root/work_dir_${VERSION}"
    mkdir ${WORK_DIR}
    curl -L ${BASE_URL}/base.txz | tar vxf - -C ${WORK_DIR}
    curl -L ${BASE_URL}/kernel.txz | tar vxf - -C ${WORK_DIR}
    curl -L -o ${WORK_DIR}/tmp/cloud-init.tar.gz "https://github.com/${repo}/archive/${ref}.tar.gz"
    echo "
export ASSUME_ALWAYS_YES=YES
cd /tmp
pkg install -y ca_root_nss
tar xf cloud-init.tar.gz
cd cloud-init-*
touch /etc/rc.conf
mkdir -p /usr/local/etc/rc.d
pkg install -y python3
./tools/build-on-freebsd
" > ${WORK_DIR}/tmp/cloudify.sh
test -z "$debug" || echo "pw mod user root -w no" >> ${WORK_DIR}/tmp/cloudify.sh  # Lock root account

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
