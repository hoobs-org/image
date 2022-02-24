#!/bin/bash

debootstrap_ng()
{
	display_alert "Starting rootfs and image building process for" "${BRANCH} ${BOARD} ${RELEASE}" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	trap unmount_on_exit INT TERM EXIT

	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	if [[ -d "${ARMBIAN_CACHE_ROOTFS_PATH}" ]]; then
		mountpoint -q "${SRC}"/cache/rootfs && umount -l "${SRC}"/cache/toolchain
		mount --bind "${ARMBIAN_CACHE_ROOTFS_PATH}" "${SRC}"/cache/rootfs
	fi

	local phymem=$(( (($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10 ))
	local tmpfs_max_size=1500

	if [[ $FORCE_USE_RAMDISK == no ]]; then
		local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi

	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE
	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	create_rootfs_cache

	call_extension_method "pre_install_distribution_specific" "config_pre_install_distribution_specific" << 'PRE_INSTALL_DISTRIBUTION_SPECIFIC'
*give config a chance to act before install_distribution_specific*
Called after `create_rootfs_cache` (_prepare basic rootfs: unpack cache or create from scratch_) but before `install_distribution_specific` (_install distribution and board specific applications_).
PRE_INSTALL_DISTRIBUTION_SPECIFIC

	install_distribution_specific
	install_common

	[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local
	[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes"

	customize_image

	display_alert "No longer needed packages" "purge" "info"
	chroot $SDCARD /bin/bash -c "apt-get autoremove -y"  >/dev/null 2>&1
	chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > $DEST/${LOG_SUBPATH}/installed-packages-${RELEASE}.list 2>&1

	umount_chroot "$SDCARD"
	post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"

		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	umount $SDCARD 2>&1

	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts
		do
			umount $SDCARD
			sleep 5
		done
	fi

	rm -rf $SDCARD

	trap - INT TERM EXIT
}

create_rootfs_cache()
{
	if [[ "$ROOT_FS_CREATE_ONLY" == "force" ]]; then
		local cycles=1
	else
		local cycles=2
	fi

	for ((n=0;n<${cycles};n++)); do
		[[ -z ${FORCED_MONTH_OFFSET} ]] && FORCED_MONTH_OFFSET=${n}

		local packages_hash=$(get_package_list_hash "$(date -d "$D +${FORCED_MONTH_OFFSET} month" +"%Y-%m-module$ROOTFSCACHE_VERSION" | sed 's/^0*//')")
		local cache_type="cli"
		local cache_type="minimal"
		local cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.lz4
		local cache_fname=${SRC}/cache/rootfs/${cache_name}
		local display_name=${RELEASE}-${cache_type}-${ARCH}.${packages_hash:0:3}...${packages_hash:29}.tar.lz4

		[[ "$ROOT_FS_CREATE_ONLY" == force ]] && break

		if [[ -f ${cache_fname} && -f ${cache_fname}.aria2 ]]; then
			rm ${cache_fname}*

			display_alert "Partially downloaded file. Re-start."
			download_and_verify "_rootfs" "$cache_name"
		fi

		display_alert "Checking local cache" "$display_name" "info"

		if [[ -f ${cache_fname} && -n "$ROOT_FS_CREATE_ONLY" ]]; then
			touch $cache_fname.current
			display_alert "Checking cache integrity" "$display_name" "info"
			sudo lz4 -tqq ${cache_fname}

			[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Please restart!"

			if [[ -n "${GPG_PASS}" && "${SUDO_USER}" && ! -f ${cache_fname}.asc ]]; then
				[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/

				echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
			fi

			break
		elif [[ -f ${cache_fname} ]]; then
			break
		else
			display_alert "searching on servers"
			download_and_verify "_rootfs" "$cache_name"
		fi

		if [[ ! -f $cache_fname ]]; then
			display_alert "not found: try to use previous cache"
		fi
	done

	if [[ -f $cache_fname && ! -f $cache_fname.aria2 ]]; then
		if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
			touch $cache_fname.current
			umount --lazy "$SDCARD"
			rm -rf $SDCARD

			trap - INT TERM EXIT
			exit
		fi

		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))

		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "[ .... ] $display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $SDCARD/

		[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Restart."

		rm $SDCARD/etc/resolv.conf

		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf
		create_sources_list "$RELEASE" "$SDCARD/"
	else
		display_alert "... remote not found" "Creating new rootfs cache for $RELEASE" "info"

		if [[ $NO_APT_CACHER != yes ]]; then
			local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$APT_MIRROR"
		else
			local apt_mirror="http://$APT_MIRROR"
		fi

		[[ -z $OUTPUT_DIALOG ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"

		display_alert "Installing base system" "Stage 1/2" "info"
		cd $SDCARD # this will prevent error sh: 0: getcwd() failed

		eval 'debootstrap --variant=minbase --include=${DEBOOTSTRAP_LIST// /,} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --components=${DEBOOTSTRAP_COMPONENTS} $DEBOOTSTRAP_OPTION --foreign $RELEASE $SDCARD/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 || ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} first stage failed"

		cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/
		mkdir -p $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/*-archive-keyring.gpg $SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 || ! -f $SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} second stage failed"

		mount_chroot "$SDCARD"

		display_alert "Diverting" "initctl/start-stop-daemon" "info"
		printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
		LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl" &> /dev/null
		LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon" &> /dev/null

		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl

		chmod 755 $SDCARD/usr/sbin/policy-rc.d
		chmod 755 $SDCARD/sbin/initctl
		chmod 755 $SDCARD/sbin/start-stop-daemon

		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		if [[ -f $SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save --force"'
		fi

		create_sources_list "$RELEASE" "$SDCARD/"

		if [[ "a${ARMHF_ARCH}" != "askip" ]]; then
			[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'
		fi

		chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'
		display_alert "Updating package list" "$RELEASE" "info"

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && display_alert "Updating package lists" "failed" "wrn"

		display_alert "Upgrading base packages" "Armbian" "info"

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && display_alert "Upgrading base packages" "failed" "wrn"

		display_alert "Installing the main packages for" "Armbian" "info"

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_MAIN_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Installation of Armbian main packages for ${BRANCH} ${BOARD} ${RELEASE} failed"

		display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
			$apt_extra $apt_extra_progress purge $PACKAGE_LIST_UNINSTALL"' \
			${PROGRESS_LOG_TO_FILE:+' >> $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		display_alert "Purging residual packages for" "Armbian" "info"
		PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")

		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress remove --purge $PURGINGPACKAGES"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/${LOG_SUBPATH}/debootstrap.log'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'} ';EVALPIPE=(${PIPESTATUS[@]})'

		[[ ${EVALPIPE[0]} -ne 0 ]] && exit_with_error "Purging of residual Armbian packages failed"

		chroot $SDCARD /bin/bash -c "apt-get -y autoremove; apt-get clean"

		local freespace=$(LC_ALL=C df -h)
		echo $freespace >> $DEST/${LOG_SUBPATH}/debootstrap.log

		display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
		display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

		chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > ${cache_fname}.list 2>&1

		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf

		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync

		umount_chroot "$SDCARD"

		tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$display_name" | lz4 -5 -c > $cache_fname

		if [[ -n "${GPG_PASS}" && "${SUDO_USER}" ]]; then
			[[ -n ${SUDO_USER} ]] && sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DEST}"/images/

			echo "${GPG_PASS}" | sudo -H -u ${SUDO_USER} bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${cache_fname}" || exit 1
		fi

		touch $cache_fname.current
	fi

	if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
		umount --lazy "$SDCARD"
		rm -rf $SDCARD

		trap - INT TERM EXIT
		exit
	fi

	mount_chroot "$SDCARD"
}

prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	declare -A parttype mkopts mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	parttype[xfs]=xfs

	local node_number=1024

	if [[ $HOSTRELEASE =~ bionic|buster|bullseye|cosmic|focal|hirsute|impish|jammy|sid ]]; then
		mkopts[ext4]="-q -m 2 -O ^64bit,^metadata_csum -N $((128*${node_number}))"
	elif [[ $HOSTRELEASE == xenial ]]; then
		mkopts[ext4]="-q -m 2 -N $((128*${node_number}))"
	fi

	mkopts[fat]='-n BOOT'
	mkopts[ext2]='-q'

	mkopts[btrfs]='-m dup'

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	mkfs[xfs]=xfs

	mountopts[ext4]=',commit=600,errors=remount-ro'
	mountopts[btrfs]=',commit=600'

	DEFAULT_BOOTSIZE=256	# MiB
	UEFISIZE=${UEFISIZE:-0}
	BIOSSIZE=${BIOSSIZE:-0}
	UEFI_MOUNT_POINT=${UEFI_MOUNT_POINT:-/boot/efi}
	UEFI_FS_LABEL="${UEFI_FS_LABEL:-armbiefi}"

	call_extension_method "pre_prepare_partitions" "prepare_partitions_custom" <<'PRE_PREPARE_PARTITIONS'
*allow custom options for mkfs*
Good time to change stuff like mkfs opts, types etc.
PRE_PREPARE_PARTITIONS

	if [[ -n $BOOTFS_TYPE ]]; then
		local bootfs=$BOOTFS_TYPE
		local bootpart=1
		local rootpart=2

		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE != ext4 && $ROOTFS_TYPE != nfs ]]; then
		local bootfs=ext4
		local bootpart=1
		local rootpart=2

		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		local bootfs=ext4
		local bootpart=1

		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE} # For cleanup processing only
	elif [[ $CRYPTROOT_ENABLE == yes ]]; then
		local bootfs=ext4
		local bootpart=1
		local rootpart=2

		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $UEFISIZE -gt 0 ]]; then
		if [[ "${IMAGE_PARTITION_TABLE}" == "gpt" ]]; then
			local uefipart=15
			local rootpart=1
		else
			local uefipart=1
			local rootpart=2
		fi
	else
		local rootpart=1
		BOOTSIZE=0
	fi

	export rootfs_size=$(du -sm $SDCARD/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"

	call_extension_method "prepare_image_size" "config_prepare_image_size" << 'PREPARE_IMAGE_SIZE'
*allow dynamically determining the size based on the $rootfs_size*
Called after `${rootfs_size}` is known, but before `${FIXED_IMAGE_SIZE}` is taken into account.
A good spot to determine `FIXED_IMAGE_SIZE` based on `rootfs_size`.
UEFISIZE can be set to 0 for no UEFI partition, or to a size in MiB to include one.
Last chance to set `USE_HOOK_FOR_PARTITION`=yes and then implement create_partition_table hook_point.
PREPARE_IMAGE_SIZE

	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"

		local sdsize=$FIXED_IMAGE_SIZE

		if [[ $ROOTFS_TYPE != nfs && $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE + $UEFISIZE + $EXTRA_ROOTFS_MIB_SIZE)) # MiB
		local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.25) / 1 + 0) / 4 + 1) * 4")
	fi

	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"

	if [[ $FAST_CREATE_IMAGE == yes ]]; then
		truncate --size=${sdsize}M ${SDCARD}.raw # sometimes results in fs corruption, revert to previous know to work solution
		sync
	else
		dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) -N "[ .... ] dd" | dd status=none of=${SDCARD}.raw
	fi

	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048) + ($UEFISIZE * 2048)))
	local bootend=$(($rootstart - 1))

	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s ${SDCARD}.raw -- mklabel ${IMAGE_PARTITION_TABLE}

	if [[ "${USE_HOOK_FOR_PARTITION}" == "yes" ]]; then
		call_extension_method "create_partition_table" <<- 'CREATE_PARTITION_TABLE'
		*only called when USE_HOOK_FOR_PARTITION=yes to create the complete partition table*
		Finally, we can get our own partition table. You have to partition ${SDCARD}.raw
		yourself. Good luck.
		CREATE_PARTITION_TABLE
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s "100%"
	elif [[ $UEFISIZE -gt 0 ]]; then
		if [[ "${IMAGE_PARTITION_TABLE}" == "gpt" ]]; then
			if [[ ${BIOSSIZE} -gt 0 ]]; then
				display_alert "Creating partitions" "BIOS+UEFI+rootfs" "info"

				local biosstart=$(($OFFSET * 2048))
				local uefistart=$(($OFFSET * 2048 + ($BIOSSIZE * 2048)))
				local rootstart=$(($uefistart + ($UEFISIZE * 2048) ))
				local biosend=$(($uefistart - 1))
				local uefiend=$(($rootstart - 1))

				parted -s ${SDCARD}.raw -- mkpart bios fat32 ${biosstart}s ${biosend}s
				parted -s ${SDCARD}.raw -- mkpart efi fat32 ${uefistart}s ${uefiend}s
				parted -s ${SDCARD}.raw -- mkpart rootfs ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"

				sgdisk --transpose 1:14 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 1:14 FAILED"
				sgdisk --transpose 2:15 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 2:15 FAILED"
				sgdisk --transpose 3:1 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 3:1 FAILED"

				parted -s ${SDCARD}.raw -- set 14 bios_grub on || echo "*** SETTING bios_grub ON 14 FAILED"
				parted -s ${SDCARD}.raw -- set 15 esp on || echo "*** SETTING ESP ON 15 FAILED"
			else
				display_alert "Creating partitions" "UEFI+rootfs (no BIOS)" "info"

				parted -s ${SDCARD}.raw -- mkpart efi fat32 ${bootstart}s ${bootend}s
				parted -s ${SDCARD}.raw -- mkpart rootfs ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"

				sgdisk --transpose 1:15 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 1:15 FAILED"
				sgdisk --transpose 2:1 ${SDCARD}.raw &> /dev/null || echo "*** TRANSPOSE 2:1 FAILED"

				parted -s ${SDCARD}.raw -- set 15 esp on || echo "*** SETTING ESP ON 15 FAILED"
			fi
		else
			parted -s ${SDCARD}.raw -- mkpart primary fat32 ${bootstart}s ${bootend}s
			parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
		fi
	elif [[ $BOOTSIZE == 0 ]]; then
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
	else
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s "100%"
	fi

	call_extension_method "post_create_partitions" <<- 'POST_CREATE_PARTITIONS'
	*called after all partitions are created, but not yet formatted*
	POST_CREATE_PARTITIONS

	exec {FD}>/var/lock/armbian-debootstrap-losetup

	flock -x $FD
	LOOP=$(losetup -f)

	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	check_loop_device "$LOOP"
	losetup $LOOP ${SDCARD}.raw
	flock -u $FD
	partprobe $LOOP

	rm -f $SDCARD/etc/fstab

	if [[ -n $rootpart ]]; then
		local rootdevice="${LOOP}p${rootpart}"

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			display_alert "Encrypting root partition with LUKS..." "cryptsetup luksFormat $rootdevice" ""

			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksFormat $CRYPTROOT_PARAMETERS $rootdevice -
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksOpen $rootdevice $ROOT_MAPPER -

			display_alert "Root partition encryption complete." "" "ext"
			rootdevice=/dev/mapper/$ROOT_MAPPER # used by `mkfs` and `mount` commands
		fi

		check_loop_device "$rootdevice"
		display_alert "Creating rootfs" "$ROOTFS_TYPE on $rootdevice"
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} $rootdevice >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1

		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback $rootdevice > /dev/null

		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi

		mount ${fscreateopt} $rootdevice $MOUNT/

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab

			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi

		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	fi

	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"

		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart} >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1
		mkdir -p $MOUNT/boot/
		mount ${LOOP}p${bootpart} $MOUNT/boot/

		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi

	if [[ -n $uefipart ]]; then
		display_alert "Creating EFI partition" "FAT32 ${UEFI_MOUNT_POINT} on ${LOOP}p${uefipart} label ${UEFI_FS_LABEL}"
		check_loop_device "${LOOP}p${uefipart}"

		mkfs.fat -F32 -n "${UEFI_FS_LABEL}" ${LOOP}p${uefipart} >>"${DEST}"/debug/install.log 2>&1
		mkdir -p "${MOUNT}${UEFI_MOUNT_POINT}"
		mount ${LOOP}p${uefipart} "${MOUNT}${UEFI_MOUNT_POINT}"

		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${uefipart}) ${UEFI_MOUNT_POINT} vfat defaults 0 2" >>$SDCARD/etc/fstab
	fi

	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab

	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	call_extension_method "format_partitions" <<- 'FORMAT_PARTITIONS'
	*if you created your own partitions, this would be a good time to format them*
	The loop device is mounted, so ${LOOP}p1 is it's first partition etc.
	FORMAT_PARTITIONS

	if [[ -f $SDCARD/boot/armbianEnv.txt ]]; then
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "rootdev=$rootdevice cryptdevice=UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}):$ROOT_MAPPER" >> $SDCARD/boot/armbianEnv.txt
		else
			echo "rootdev=$rootfs" >> $SDCARD/boot/armbianEnv.txt
		fi

		echo "rootfstype=$ROOTFS_TYPE" >> $SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}

		sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/$bootscript_dst
	fi

	if [[ -f $SDCARD/boot/boot.ini ]]; then
		sed -i -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.ini

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			local rootpart="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"

			sed -i 's/^setenv rootdev .*/setenv rootdev "\/dev\/mapper\/'$ROOT_MAPPER' cryptdevice='$rootpart':'$ROOT_MAPPER'"/' $SDCARD/boot/boot.ini
		else
			sed -i 's/^setenv rootdev .*/setenv rootdev "'$rootfs'"/' $SDCARD/boot/boot.ini
		fi

		if [[  $LINUXFAMILY != meson64 ]]; then
			[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
		fi
	fi

	if [[ -n $DEFAULT_CONSOLE && -f $SDCARD/boot/armbianEnv.txt ]]; then
		if grep -lq "^console=" $SDCARD/boot/armbianEnv.txt; then
			sed -i "s/console=.*/console=$DEFAULT_CONSOLE/" $SDCARD/boot/armbianEnv.txt
		else
			echo "console=$DEFAULT_CONSOLE" >> $SDCARD/boot/armbianEnv.txt
		fi
	fi

	[[ -f $SDCARD/boot/boot.cmd ]] && mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr > /dev/null 2>&1

	if [[ -f $SDCARD/boot/extlinux/extlinux.conf ]]; then
		echo "  append root=$rootfs $SRC_CMDLINE $MAIN_CMDLINE" >> $SDCARD/boot/extlinux/extlinux.conf

		[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
	fi

}

update_initramfs()
{
	local chroot_target=$1

	local target_dir=$(
		find ${chroot_target}/lib/modules/ -maxdepth 1 -type d -name "*${VER}*"
	)

	if [ "$target_dir" != "" ]; then
		update_initramfs_cmd="update-initramfs -uv -k $(basename $target_dir)"
	else
		exit_with_error "No kernel installed for the version" "${VER}"
	fi

	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/"

	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" >> $DEST/${LOG_SUBPATH}/install.log 2>&1 || {
		display_alert "Updating initramfs FAILED, see:" "$DEST/${LOG_SUBPATH}/install.log" "err"
		exit 23
	}

	display_alert "Updated initramfs." "for details see: $DEST/${LOG_SUBPATH}/install.log" "info"
	display_alert "Re-enabling" "initramfs-tools hook for kernel"

	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY

}

create_image()
{
	mkdir -p $DESTIMG

	local output="hoobs-v${BUILD_VERSION}-$(echo "${BOARD}" | sed 's/[A-Z]/\L&/g')-${IMG_TYPE}"

	display_alert "Copying files to" "/"
	echo -e "\nCopying files to [/]" >>"${DEST}"/${LOG_SUBPATH}/install.log
	rsync -aHWXh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" --exclude="/sys/*" --info=progress0,stats1 $SDCARD/ $MOUNT/ >> "${DEST}"/${LOG_SUBPATH}/install.log 2>&1

	display_alert "Copying files to" "/boot"
	echo -e "\nCopying files to [/boot]" >>"${DEST}"/${LOG_SUBPATH}/install.log

	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		rsync -rLtWh --info=progress0,stats1 --log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT
	else
		rsync -aHWXh --info=progress0,stats1 --log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" << 'PRE_UPDATE_INITRAMFS'
*allow config to hack into the initramfs create process*
Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
PRE_UPDATE_INITRAMFS

	[[ -n $KERNELSOURCE ]] && {
		update_initramfs $MOUNT
	}

	local freespace=$(LC_ALL=C df -h)

	echo $freespace >> $DEST/${LOG_SUBPATH}/debootstrap.log

	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	if [[ -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
		 write_uboot $LOOP
	elif [[ "${UPSTREM_VER}" ]]; then
		 write_uboot $LOOP
	fi

	chmod 755 $MOUNT

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" << 'PRE_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image before the unmount*
Called before unmounting both `/root` and `/boot`.
PRE_UMOUNT_FINAL_IMAGE

	sync

	[[ $UEFISIZE != 0 ]] && umount -l "${MOUNT}${UEFI_MOUNT_POINT}"
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" << 'POST_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image after the unmount*
Called after unmounting both `/root` and `/boot`.
POST_UMOUNT_FINAL_IMAGE

	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts
	do
		display_alert "Wait for unmount" "${MOUNT}" "info"
		sleep 5
	done

	losetup -d $LOOP

	rm -rf --one-file-system $MOUNT
	mkdir -p $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${output}.img

	if [[ -z $SEND_TO_SERVER ]]; then
		display_alert "Compressing" "${output}.xz" "info"
		available_cpu=$(grep -c 'processor' /proc/cpuinfo)

		[[ ${available_cpu} -gt 16 ]] && available_cpu=16

		available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}')

		if [[ ${BUILD_ALL} == yes && ( ${available_mem} -lt 15 || $(ps -uax | grep "pixz" | wc -l) -gt 4 )]]; then
			while [[ $(ps -uax | grep "pixz" | wc -l) -gt 2 ]]
				do echo -en "#"
				sleep 20
			done
		fi

		pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < $DESTIMG/${output}.img > ${DESTIMG}/${output}.xz

		cd ${DESTIMG}

		display_alert "SHA256 calculating" "${output}.sha256" "info"
		sha256sum -b ${output}.xz > ${output}.sha256
	fi

	display_alert "Done building" "${output}.xz" "info"

	rm $DESTIMG/${output}.img
	rsync -a --no-owner --no-group --remove-source-files $DESTIMG/${output}* ${FINALDEST}
	rm -rf --one-file-system $DESTIMG
}
