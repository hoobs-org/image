#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_FILENAME}.img"

on_chroot << EOF
if [ -x /etc/init.d/fake-hwclock ]; then
	/etc/init.d/fake-hwclock stop
fi

if hash hardlink 2>/dev/null; then
	hardlink -t /usr/share/doc
fi
EOF

if [ -d "${ROOTFS_DIR}/home/hoobs/.config" ]; then
	chmod 700 "${ROOTFS_DIR}/home/hoobs/.config"
fi

rm -f "${ROOTFS_DIR}/usr/bin/qemu-arm-static"

if [ -e "${ROOTFS_DIR}/etc/ld.so.preload.disabled" ]; then
	mv "${ROOTFS_DIR}/etc/ld.so.preload.disabled" "${ROOTFS_DIR}/etc/ld.so.preload"
fi

rm -f "${ROOTFS_DIR}/etc/network/interfaces.dpkg-old"

rm -f "${ROOTFS_DIR}/etc/apt/sources.list~"
rm -f "${ROOTFS_DIR}/etc/apt/trusted.gpg~"

rm -f "${ROOTFS_DIR}/etc/passwd-"
rm -f "${ROOTFS_DIR}/etc/group-"
rm -f "${ROOTFS_DIR}/etc/shadow-"
rm -f "${ROOTFS_DIR}/etc/gshadow-"
rm -f "${ROOTFS_DIR}/etc/subuid-"
rm -f "${ROOTFS_DIR}/etc/subgid-"

rm -f "${ROOTFS_DIR}"/var/cache/debconf/*-old
rm -f "${ROOTFS_DIR}"/var/lib/dpkg/*-old

rm -f "${ROOTFS_DIR}"/usr/share/icons/*/icon-theme.cache

rm -f "${ROOTFS_DIR}/var/lib/dbus/machine-id"

true > "${ROOTFS_DIR}/etc/machine-id"

ln -nsf /proc/mounts "${ROOTFS_DIR}/etc/mtab"

find "${ROOTFS_DIR}/var/log/" -type f -exec cp /dev/null {} \;

rm -f "${ROOTFS_DIR}/root/.vnc/private.key"
rm -f "${ROOTFS_DIR}/etc/vnc/updateid"

mkdir -p "${DEPLOY_DIR}"

rm -f "${DEPLOY_DIR}/${IMG_FILENAME}.xz"
rm -f "${DEPLOY_DIR}/${IMG_FILENAME}.sha256"

ROOT_DEV="$(mount | grep "${ROOTFS_DIR} " | cut -f1 -d' ')"

unmount "${ROOTFS_DIR}"
zerofree "${ROOT_DEV}"

unmount_image "${IMG_FILE}"

display_alert "Compressing" "${IMG_FILENAME}.xz" "info"
available_cpu=$(grep -c 'processor' /proc/cpuinfo)

[[ ${available_cpu} -gt 16 ]] && available_cpu=16

available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}')

if [[ ${BUILD_ALL} == yes && ( ${available_mem} -lt 15 || $(ps -uax | grep "pixz" | wc -l) -gt 4 )]]; then
	while [[ $(ps -uax | grep "pixz" | wc -l) -gt 2 ]]
		do echo -en "#"
		sleep 20
	done
fi

pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < "${IMG_FILE}" > "${DEPLOY_DIR}/${IMG_FILENAME}.xz"

display_alert "SHA256 calculating" "${IMG_FILENAME}.sha256" "info"
(cd "${DEPLOY_DIR}" && sha256sum -b "${IMG_FILENAME}.xz" > "${IMG_FILENAME}.sha256")

display_alert "Done building" "${IMG_FILENAME}.xz" "info"
rm "${IMG_FILE}"
chmod 0644 "${DEPLOY_DIR}/${IMG_FILENAME}.xz" "${DEPLOY_DIR}/${IMG_FILENAME}.sha256"
