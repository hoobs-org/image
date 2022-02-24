#!/bin/bash

mount_chroot()
{
	local target=$1

	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts
}

umount_chroot()
{
	local target=$1

	display_alert "Unmounting" "$target" "info"

	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts
	do
		umount -l --recursive "${target}"/dev >/dev/null 2>&1
		umount -l "${target}"/proc >/dev/null 2>&1
		umount -l "${target}"/sys >/dev/null 2>&1
		sleep 5
	done
}

unmount_on_exit()
{
	trap - INT TERM EXIT

	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	display_alert "unmount_on_exit() called!" "$stacktrace" "err"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		ERROR_DEBUG_SHELL=no # dont do it twice

		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL" "err"

		bash < /dev/tty || true
	fi

	umount_chroot "${SDCARD}/"
	mountpoint -q "${SRC}"/cache/toolchain && umount -l "${SRC}"/cache/toolchain
	mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/rootfs
	umount -l "${SDCARD}"/tmp >/dev/null 2>&1
	umount -l "${SDCARD}" >/dev/null 2>&1
	umount -l "${MOUNT}"/boot >/dev/null 2>&1
	umount -l "${MOUNT}" >/dev/null 2>&1

	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}"

	losetup -d "${LOOP}" >/dev/null 2>&1
	rm -rf --one-file-system "${SDCARD}"
	exit_with_error "debootstrap-ng was interrupted" || true
}

check_loop_device()
{
	local device=$1

	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
}

write_uboot()
{

	local loop=$1 revision

	display_alert "Writing U-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d || exit 1)
	chmod 700 ${TEMP_DIR}
	revision=${REVISION}

	if [[ -n $UPSTREM_VER ]]; then
		revision=${UPSTREM_VER}
		dpkg -x "${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	else
		dpkg -x "${DEB_STORAGE}/${CHOSEN_UBOOT}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	fi

	source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh

	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop"

	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"

	rm -rf ${TEMP_DIR}
}

copy_all_packages_files_for()
{
	local package_name="${1}"

	for package_src_dir in ${PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS};
	do
		local package_dirpath="${package_src_dir}/${package_name}"

		if [ -d "${package_dirpath}" ]; then
			cp -r "${package_dirpath}/"* "${destination}/" 2> /dev/null
			display_alert "Adding files from" "${package_dirpath}"
		fi
	done
}

customize_image()
{

	[[ -f $SRC/install-host.sh ]] && source "$SRC"/install-host.sh

	cp "$SRC"/packages/tzupdate/tzupdate.sh "${SDCARD}"/tmp/tzupdate.sh
	chroot "${SDCARD}" /bin/bash -c "/tmp/tzupdate.sh $BUILD_VERSION $RELEASE $BOARD $NODE_REPO $IMG_TYPE $BOOT_METHOD"
	cp "$SRC"/packages/tzupdate/tzupdate.py "${SDCARD}"/usr/lib/python3.9/tzupdate.py

	call_extension_method "pre_customize_image" "image_tweaks_pre_customize" << 'PRE_CUSTOMIZE_IMAGE'
*run before install.sh*
This hook is called after `install-host.sh` is called, but before the overlay is mounted.
It thus can be used for the same purposes as `install-host.sh`.
PRE_CUSTOMIZE_IMAGE

	cp "$SRC"/install.sh "${SDCARD}"/tmp/install.sh
	cp "$SRC"/config/dialog.conf "${SDCARD}"/tmp/dialog.conf
	chmod +x "${SDCARD}"/tmp/install.sh
	mkdir -p "${SDCARD}"/tmp/overlay

	mount -o bind,ro "$USERPATCHES_PATH"/overlay "${SDCARD}"/tmp/overlay

	display_alert "Calling image customization script" "install.sh" "info"

	chroot "${SDCARD}" /bin/bash -c "/tmp/install.sh $BUILD_VERSION $RELEASE $BOARD $NODE_REPO $IMG_TYPE $BOOT_METHOD"
	CUSTOMIZE_IMAGE_RC=$?
	umount -i "${SDCARD}"/tmp/overlay >/dev/null 2>&1
	mountpoint -q "${SDCARD}"/tmp/overlay || rm -r "${SDCARD}"/tmp/overlay

	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "install.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi

	call_extension_method "post_customize_image" "image_tweaks_post_customize" << 'POST_CUSTOMIZE_IMAGE'
*post install.sh hook*
Run after the install.sh script is run, and the overlay is unmounted.
POST_CUSTOMIZE_IMAGE
}

install_deb_chroot()
{
	local package=$1
	local variant=$2
	local transfer=$3
	local name
	local desc

	if [[ ${variant} != remote ]]; then
		name="/root/"$(basename "${package}")

		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"

		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	display_alert "Installing${desc}" "${name/\/root\//}"

	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	[[ $BUILD_ALL == yes && ${variant} == remote ]] && chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get $apt_extra -yqq update"

	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq $apt_extra --no-install-recommends install $name" >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1

	[[ $? -ne 0 ]] && exit_with_error "Installation of $name failed" "${BOARD} ${RELEASE} ${LINUXFAMILY}"
	[[ ${variant} == remote && ${transfer} == yes ]] && rsync -rq "${SDCARD}"/var/cache/apt/archives/*.deb ${DEB_STORAGE}/
}


run_on_sdcard()
{
	chroot "${SDCARD}" /bin/bash -c "${@}" >> "${DEST}"/${LOG_SUBPATH}/install.log
}
