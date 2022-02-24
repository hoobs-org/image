function extension_prepare_config__prepare_flash_kernel() {
	export FK__TOOL_PACKAGE="${FK__TOOL_PACKAGE:-flash-kernel}"
	export FK__PUBLISHED_KERNEL_VERSION="${FK__PUBLISHED_KERNEL_VERSION:-undefined-flash-kernel-version}"
	export FK__EXTRA_PACKAGES="${FK__EXTRA_PACKAGES:-undefined-flash-kernel-kernel-package}"
	export FK__KERNEL_PACKAGES="${FK__KERNEL_PACKAGES:-}"
	export FK__MACHINE_MODEL="${FK__MACHINE_MODEL:-Undefined Flash-Kernel Machine}"
	export BOOTCONFIG="none"

	unset BOOTSOURCE

	export UEFISIZE=256
	export BOOTSIZE=0
	export UEFI_MOUNT_POINT="/boot/firmware"
	export CLOUD_INIT_CONFIG_LOCATION="/boot/firmware"
	export VER="${FK__PUBLISHED_KERNEL_VERSION}"
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-fk${FK__PUBLISHED_KERNEL_VERSION}"

	echo "-- starting" >"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log
}

function post_install_kernel_debs__install_kernel_and_flash_packages() {
	export INSTALL_ARMBIAN_FIRMWARE="no"

	if [[ "${FK__EXTRA_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel extra packages" "${FK__EXTRA_PACKAGES}"

		echo "-- install extra pkgs" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__EXTRA_PACKAGES}" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log || {
			display_alert "Failed to install flash-kernel's extra packages." "${EXTENSION}" "err"
			exit 28
		}
	fi

	if [[ "${FK__KERNEL_PACKAGES}" != "" ]]; then
		display_alert "Installing flash-kernel kernel packages" "${FK__KERNEL_PACKAGES}"

		echo "-- install kernel pkgs" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__KERNEL_PACKAGES}" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log || {
			display_alert "Failed to install flash-kernel's kernel packages." "${EXTENSION}" "err"
			exit 28
		}
	fi

	display_alert "Installing flash-kernel package" "${FK__TOOL_PACKAGE}"
	umount "${SDCARD}"/sys
	mkdir -p "${SDCARD}"/sys/firmware/efi

	echo "-- install flash-kernel package" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get ${APT_EXTRA_DIST_PARAMS} -yqq --no-install-recommends install ${FK__TOOL_PACKAGE}" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log || {
		display_alert "Failed to install flash-kernel package." "${EXTENSION}" "err"
		exit 28
	}

	rm -rf "${SDCARD}"/sys/firmware
}

post_family_tweaks_bsp__remove_uboot_flash_kernel() {
	display_alert "Removing uboot from BSP" "${EXTENSION}" "info"
	find "$destination" -type f | grep -e "uboot" -e "u-boot" | xargs rm
}

pre_umount_final_image__remove_uboot_initramfs_hook_flash_kernel() {
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && rm -v "$MOUNT"/etc/initramfs/post-update.d/99-uboot
}

function pre_update_initramfs__setup_flash_kernel() {
	local chroot_target=$MOUNT
	cp /usr/bin/"$QEMU_BINARY" "$chroot_target"/usr/bin/
	mount_chroot "$chroot_target/"
	umount "$chroot_target/sys"

	echo "--  flash-kernel disabling hooks" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

	chroot "$chroot_target" /bin/bash -c "chmod -v -x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1
	chroot "$chroot_target" /bin/bash -c "chmod -v -x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1

	export FIRMWARE_DIR="${MOUNT}"/boot/firmware

	call_extension_method "pre_initramfs_flash_kernel" <<-'PRE_INITRAMFS_FLASH_KERNEL'
		*prepare to update-initramfs before flashing kernel via flash_kernel*
		A good spot to write firmware config to ${FIRMWARE_DIR} (/boot/firmware) before flash-kernel actually runs.
	PRE_INITRAMFS_FLASH_KERNEL

	local update_initramfs_cmd="update-initramfs -c -k all"

	display_alert "Updating flash-kernel initramfs..." "$update_initramfs_cmd" ""
	echo "--  flash-kernel initramfs" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

	chroot "$chroot_target" /bin/bash -c "$update_initramfs_cmd" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1 || {
		display_alert "Failed to run '$update_initramfs_cmd'" "Check ${DEST}/"${LOG_SUBPATH}"/flash-kernel.log" "err"
		exit 29
	}

	call_extension_method "pre_flash_kernel" <<-'PRE_FLASH_KERNEL'
		*run before running flash-kernel*
		Each board might need different stuff for flash-kernel to work. Implement it here.
		Write to `${MOUNT}`, eg: `"${MOUNT}"/etc/flash-kernel`
	PRE_FLASH_KERNEL

	local flash_kernel_cmd="flash-kernel --machine '${FK__MACHINE_MODEL}'"

	display_alert "flash-kernel" "${FK__MACHINE_MODEL}" "info"
	echo "--  flash-kernel itself" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

	chroot "$chroot_target" /bin/bash -c "${flash_kernel_cmd}" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1 || {
		display_alert "Failed to run '${flash_kernel_cmd}'" "Check ${DEST}/"${LOG_SUBPATH}"/flash-kernel.log" "err"
		exit 29
	}

	display_alert "Re-enabling" "initramfs-tools/flash-kernel hook for kernel"
	echo "--  flash-kernel re-enabling hooks" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log

	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1
	chroot "$chroot_target" /bin/bash -c "chmod -v +x /etc/initramfs/post-update.d/flash-kernel" >>"${DEST}"/"${LOG_SUBPATH}"/flash-kernel.log 2>&1

	umount_chroot "$chroot_target/"
	rm "$chroot_target"/usr/bin/"$QEMU_BINARY"

	display_alert "Disabling Armbian-core update_initramfs, was already done above." "${EXTENSION}"
	unset KERNELSOURCE
}
