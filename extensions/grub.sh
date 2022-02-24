function extension_prepare_config__prepare_flash_kernel() {
	export DISTRO_GENERIC_KERNEL=${DISTRO_GENERIC_KERNEL:-no}
	export UEFI_GRUB_TERMINAL="${UEFI_GRUB_TERMINAL:-serial console}"
	export UEFI_GRUB_DISABLE_OS_PROBER="${UEFI_GRUB_DISABLE_OS_PROBER:-}"
	export UEFI_GRUB_DISTRO_NAME="${UEFI_GRUB_DISTRO_NAME:-Armbian}"
	export UEFI_GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT:-0}
	export UEFI_ENABLE_BIOS_AMD64="${UEFI_ENABLE_BIOS_AMD64:-yes}"
	export UEFI_EXPORT_KERNEL_INITRD="${UEFI_EXPORT_KERNEL_INITRD:-no}"
	export BOOTCONFIG="none"

	unset BOOTSOURCE

	export IMAGE_PARTITION_TABLE="gpt"
	export UEFISIZE=256
	export BOOTSIZE=0
	export CLOUD_INIT_CONFIG_LOCATION="${CLOUD_INIT_CONFIG_LOCATION:-/boot/efi}"
	export EXTRA_BSP_NAME="${EXTRA_BSP_NAME}-grub"
	export UEFI_GRUB_TARGET_BIOS=""
	local uefi_packages="efibootmgr efivar cloud-initramfs-growroot"

	uefi_packages="os-prober grub-efi-${ARCH}-bin ${uefi_packages}"

	if [[ "${ARCH}" == "amd64" ]]; then
		export UEFI_GRUB_TARGET="x86_64-efi"

		if [[ "${UEFI_ENABLE_BIOS_AMD64}" == "yes" ]]; then
			export uefi_packages="${uefi_packages} grub-pc-bin grub-pc"
			export UEFI_GRUB_TARGET_BIOS="i386-pc"
			export BIOSSIZE=4
		else
			export uefi_packages="${uefi_packages} grub-efi-${ARCH}"
		fi
	fi

	[[ "${ARCH}" == "arm64" ]] && export uefi_packages="${uefi_packages} grub-efi-${ARCH}"
	[[ "${ARCH}" == "arm64" ]] && export UEFI_GRUB_TARGET="arm64-efi"

	if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
		DISTRO_KERNEL_PACKAGES="linux-image-generic"
		DISTRO_FIRMWARE_PACKAGES="linux-firmware"
	elif [[ "${DISTRIBUTION}" == "Debian" ]]; then
		DISTRO_KERNEL_PACKAGES="linux-image-${ARCH}"
		DISTRO_FIRMWARE_PACKAGES="firmware-linux-free"

		if [[ "${SERIALCON}" == "hvc0" ]]; then
			display_alert "Debian's kernels don't support hvc0, changing to ttyS0" "${DISTRIBUTION}" "wrn"

			export SERIALCON="ttyS0"
		fi
	fi

	if [[ "${DISTRO_GENERIC_KERNEL}" == "yes" ]]; then
		export VER="generic"

		unset KERNELSOURCE

		export INSTALL_ARMBIAN_FIRMWARE=no
	else
		export KERNELDIR="linux-uefi-${LINUXFAMILY}"

		DISTRO_KERNEL_PACKAGES=""
		DISTRO_FIRMWARE_PACKAGES=""
	fi

	export PACKAGE_LIST_BOARD="${PACKAGE_LIST_BOARD} ${DISTRO_FIRMWARE_PACKAGES} ${DISTRO_KERNEL_PACKAGES}  ${uefi_packages}"

	display_alert "Activating" "GRUB with SERIALCON=${SERIALCON}; timeout ${UEFI_GRUB_TIMEOUT}; BIOS=${UEFI_GRUB_TARGET_BIOS}" ""
}

post_family_tweaks_bsp__remove_uboot_grub() {
	display_alert "Removing uboot from BSP" "${EXTENSION}" "info"
	find "$destination" -type f | grep -e "uboot" -e "u-boot" | xargs rm
}

pre_umount_final_image__remove_uboot_initramfs_hook_grub() {
	[[ -f "$MOUNT"/etc/initramfs/post-update.d/99-uboot ]] && rm -v "$MOUNT"/etc/initramfs/post-update.d/99-uboot
}

pre_umount_final_image__install_grub() {
	configure_grub

	local chroot_target=$MOUNT

	display_alert "Installing bootloader" "GRUB" "info"
	rm -rf "$MOUNT"/boot/dtb* || true

	cat <<-grubCfgFragHostSide >>"${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg
		GRUB_DISABLE_OS_PROBER=true
	grubCfgFragHostSide

	mount_chroot "$chroot_target/"

	if [[ "${UEFI_GRUB_TARGET_BIOS}" != "" ]]; then
		display_alert "Installing GRUB BIOS..." "${UEFI_GRUB_TARGET_BIOS} device ${LOOP}" ""

		chroot "$chroot_target" /bin/bash -c "grub-install --verbose --target=${UEFI_GRUB_TARGET_BIOS} ${LOOP}" >>"$DEST"/"${LOG_SUBPATH}"/install.log 2>&1 || {
			exit_with_error "${install_grub_cmdline} failed!"
		}
	fi

	local install_grub_cmdline="update-initramfs -c -k all && update-grub && grub-install --verbose --target=${UEFI_GRUB_TARGET} --no-nvram --removable"

	display_alert "Installing GRUB EFI..." "${UEFI_GRUB_TARGET}" ""

	chroot "$chroot_target" /bin/bash -c "$install_grub_cmdline" >>"$DEST"/"${LOG_SUBPATH}"/install.log 2>&1 || {
		exit_with_error "${install_grub_cmdline} failed!"
	}

	rm -f "${MOUNT}"/etc/default/grub.d/99-armbian-host-side.cfg

	local root_uuid

	root_uuid=$(blkid -s UUID -o value "${LOOP}p1")

	cat <<-grubEfiCfg >"${MOUNT}"/boot/efi/EFI/BOOT/grub.cfg
		search.fs_uuid ${root_uuid} root
		set prefix=(\$root)'/boot/grub'
		configfile \$prefix/grub.cfg
	grubEfiCfg

	umount_chroot "$chroot_target/"
}

pre_umount_final_image__900_export_kernel_and_initramfs() {
	if [[ "${UEFI_EXPORT_KERNEL_INITRD}" == "yes" ]]; then
		display_alert "Exporting Kernel and Initrd for" "kexec" "info"
		cp "$MOUNT"/boot/vmlinuz-* "${DESTIMG}/${version}.kernel"
		cp "$MOUNT"/boot/initrd.img-* "${DESTIMG}/${version}.initrd"
	fi
}

configure_grub() {
	display_alert "GRUB EFI kernel cmdline" "console=${SERIALCON} distro=${UEFI_GRUB_DISTRO_NAME} timeout=${UEFI_GRUB_TIMEOUT}" ""

	if [[ "_${SERIALCON}_" != "__" ]]; then
		cat <<-grubCfgFrag >>"${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_CMDLINE_LINUX_DEFAULT="console=${SERIALCON}"
		grubCfgFrag
	fi

	cat <<-grubCfgFrag >>"${MOUNT}"/etc/default/grub.d/98-armbian.cfg
		GRUB_TIMEOUT_STYLE=menu
		GRUB_TIMEOUT=${UEFI_GRUB_TIMEOUT}
		GRUB_DISTRIBUTOR="${UEFI_GRUB_DISTRO_NAME}"
	grubCfgFrag

	if [[ "a${UEFI_GRUB_DISABLE_OS_PROBER}" != "a" ]]; then
		cat <<-grubCfgFragHostSide >>"${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_DISABLE_OS_PROBER=${UEFI_GRUB_DISABLE_OS_PROBER}
		grubCfgFragHostSide
	fi

	if [[ "a${UEFI_GRUB_TERMINAL}" != "a" ]]; then
		cat <<-grubCfgFragTerminal >>"${MOUNT}"/etc/default/grub.d/98-armbian.cfg
			GRUB_TERMINAL="${UEFI_GRUB_TERMINAL}"
		grubCfgFragTerminal
	fi
}
