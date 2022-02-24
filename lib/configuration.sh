#!/bin/bash

REVISION=$(cd ${SRC} && ./project version armbian)"$SUBREVISION"

[[ -z $VENDOR ]] && VENDOR="HOOBS"
[[ -z $ROOTPWD ]] && ROOTPWD="hoobsadmin"
[[ -z $MAINTAINER ]] && MAINTAINER="Mike Kellsy"
[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="mkellsy@hoobs.org"
[[ -z $DEB_COMPRESS ]] && DEB_COMPRESS="xz"

TZDATA=$(cat /etc/timezone)
USEALLCORES=yes
HOSTRELEASE=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)

[[ -z $HOSTRELEASE ]] && HOSTRELEASE=$(cut -d'/' -f1 /etc/debian_version)
[[ -z $EXIT_PATCHING_ERROR ]] && EXIT_PATCHING_ERROR=""
[[ -z $HOST ]] && HOST="hoobs"

cd "${SRC}" || exit

[[ -z "${ROOTFSCACHE_VERSION}" ]] && ROOTFSCACHE_VERSION=14
[[ -z "${CHROOT_CACHE_VERSION}" ]] && CHROOT_CACHE_VERSION=7

BUILD_REPOSITORY_URL=$(improved_git remote get-url $(improved_git remote 2>/dev/null | grep origin) 2>/dev/null)
BUILD_REPOSITORY_COMMIT=$(improved_git describe --match=d_e_a_d_b_e_e_f --always --dirty 2>/dev/null)
ROOTFS_CACHE_MAX=200 # max number of rootfs cache, older ones will be cleaned up

if [[ $BETA == yes ]]; then
	DEB_STORAGE=$DEST/debs-beta
	REPO_STORAGE=$DEST/repository-beta
	REPO_CONFIG="aptly-beta.conf"
else
	DEB_STORAGE=$DEST/debs
	REPO_STORAGE=$DEST/repository
	REPO_CONFIG="aptly.conf"
fi

FINALDEST=$DEST/images

if [[ "${MAKE_FOLDERS}" == yes ]]; then
	if [[ "$RC" == yes ]]; then
		FINALDEST=$DEST/images/"${BOARD}"/rc
	elif [[ "$BETA" == yes ]]; then
		FINALDEST=$DEST/images/"${BOARD}"/nightly
	else
		FINALDEST=$DEST/images/"${BOARD}"/archive
	fi

	install -d ${FINALDEST}
fi

ROOT_MAPPER="armbian-root"

[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4
[[ "ext4 f2fs btrfs xfs nfs fel" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

[[ -z $BTRFS_COMPRESSION ]] && BTRFS_COMPRESSION=zlib # default btrfs filesystem compression method is zlib
[[ ! $BTRFS_COMPRESSION =~ zlib|lzo|zstd|none ]] && exit_with_error "Unknown btrfs compression method" "$BTRFS_COMPRESSION"

[[ "f2fs" == *$ROOTFS_TYPE* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE"

if [[ $CRYPTROOT_ENABLE == yes && -z $CRYPTROOT_PASSPHRASE ]]; then
	exit_with_error "Root encryption is enabled but CRYPTROOT_PASSPHRASE is not set"
fi

[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=64

case $REGIONAL_MIRROR in
	china)
		[[ -z $USE_MAINLINE_GOOGLE_MIRROR ]] && [[ -z $MAINLINE_MIRROR ]] && MAINLINE_MIRROR=tuna
		[[ -z $USE_GITHUB_UBOOT_MIRROR ]] && [[ -z $UBOOT_MIRROR ]] && UBOOT_MIRROR=gitee
		[[ -z $GITHUB_MIRROR ]] && GITHUB_MIRROR=cnpmjs
		[[ -z $DOWNLOAD_MIRROR ]] && DOWNLOAD_MIRROR=china
		;;

	*)
		;;
esac

[[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]] && MAINLINE_MIRROR=google

case $MAINLINE_MIRROR in
	google)
		MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		MAINLINE_FIRMWARE_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
		;;

	tuna)
		MAINLINE_KERNEL_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-firmware.git'
		;;

	bfsu)
		MAINLINE_KERNEL_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-firmware.git'
		;;

	*)
		MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
		;;
esac

MAINLINE_KERNEL_DIR='linux-mainline'

[[ $USE_GITHUB_UBOOT_MIRROR == yes ]] && UBOOT_MIRROR=github

case $UBOOT_MIRROR in
	gitee)
		MAINLINE_UBOOT_SOURCE='https://gitee.com/mirrors/u-boot.git'
		;;

	github)
		MAINLINE_UBOOT_SOURCE='https://github.com/u-boot/u-boot'
		;;

	*)
		MAINLINE_UBOOT_SOURCE='https://source.denx.de/u-boot/u-boot.git'
		;;
esac

MAINLINE_UBOOT_DIR='u-boot'

case $GITHUB_MIRROR in
	fastgit)
		GITHUB_SOURCE='https://hub.fastgit.xyz/'
		;;

	gitclone)
		GITHUB_SOURCE='https://gitclone.com/github.com/'
		;;

	*)
		GITHUB_SOURCE='https://github.com/'
		;;
esac

[[ -z $OFFSET ]] && OFFSET=4 # offset to 1st partition (we use 4MiB boundaries by default)

ARCH=armhf
KERNEL_IMAGE_TYPE=zImage
CAN_BUILD_STRETCH=yes
ATF_COMPILE=yes

[[ -z $CRYPTROOT_SSH_UNLOCK ]] && CRYPTROOT_SSH_UNLOCK=yes
[[ -z $CRYPTROOT_SSH_UNLOCK_PORT ]] && CRYPTROOT_SSH_UNLOCK_PORT=2022
[[ -z $CRYPTROOT_PARAMETERS ]] && CRYPTROOT_PARAMETERS="--pbkdf pbkdf2"
[[ -z $WIREGUARD ]] && WIREGUARD="yes"
[[ -z $EXTRAWIFI ]] && EXTRAWIFI="yes"
[[ -z $SKIP_BOOTSPLASH ]] && SKIP_BOOTSPLASH="no"
[[ -z $AUFS ]] && AUFS="yes"
[[ -z $IMAGE_PARTITION_TABLE ]] && IMAGE_PARTITION_TABLE="msdos"
[[ -z $EXTRA_BSP_NAME ]] && EXTRA_BSP_NAME=""
[[ -z $EXTRA_ROOTFS_MIB_SIZE ]] && EXTRA_ROOTFS_MIB_SIZE=0
[[ ! -f ${SRC}/config/sources/families/$LINUXFAMILY.conf ]] && exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source "${SRC}/config/sources/families/${LINUXFAMILY}.conf"

if [[ -f $USERPATCHES_PATH/sources/families/$LINUXFAMILY.conf ]]; then
	display_alert "Adding user provided $LINUXFAMILY overrides"

	source "$USERPATCHES_PATH/sources/families/${LINUXFAMILY}.conf"
fi

source "${SRC}/config/sources/${ARCH}.conf"

initialize_extension_manager

call_extension_method "post_family_config" "config_tweaks_post_family_config" << 'POST_FAMILY_CONFIG'
*give the config a chance to override the family/arch defaults*
This hook is called after the family configuration (`sources/families/xxx.conf`) is sourced.
Since the family can override values from the user configuration and the board configuration,
it is often used to in turn override those.
POST_FAMILY_CONFIG

show_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3

	DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "$provided_title" --backtitle "${provided_backtitle}" --menu "$provided_menuname" 50 150 $((50 - 8)) "${@:4}"
}

show_select_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3

	DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "${provided_title}" --backtitle "${provided_backtitle}" --checklist "${provided_menuname}" 50 150 $((50 - 8)) "${@:4}"
}

aggregate_content() {
	LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/potential-paths.log"

	echo -e "Potential paths :" >> "${LOG_OUTPUT_FILE}"
	show_checklist_variables potential_paths

	for filepath in ${potential_paths}; do
		if [[ -f "${filepath}" ]]; then
			echo -e "${filepath/"$SRC"\//} yes" >> "${LOG_OUTPUT_FILE}"
			aggregated_content+=$(cat "${filepath}")
			aggregated_content+="${separator}"
		fi
	done

	echo "" >> "${LOG_OUTPUT_FILE}"

	unset LOG_OUTPUT_FILE
}

MOUNT_UUID=$(uuidgen)
SDCARD="${SRC}/.tmp/rootfs-${MOUNT_UUID}"
MOUNT="${SRC}/.tmp/mount-${MOUNT_UUID}"
DESTIMG="${SRC}/.tmp/image-${MOUNT_UUID}"

[[ $CRYPTROOT_ENABLE == yes && $RELEASE == xenial ]] && exit_with_error "Encrypted rootfs is not supported in Xenial"
[[ $RELEASE == stretch && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Debian Stretch images with selected kernel is not supported"
[[ $RELEASE == bionic && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Ubuntu Bionic images with selected kernel is not supported"
[[ $RELEASE == hirsute && $HOSTRELEASE == focal ]] && exit_with_error "Building Ubuntu Hirsute images requires Hirsute build host. Please upgrade your host or select a different target OS"

[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

BOOTCONFIG_VAR_NAME=BOOTCONFIG_${BRANCH^^}

[[ -n ${!BOOTCONFIG_VAR_NAME} ]] && BOOTCONFIG=${!BOOTCONFIG_VAR_NAME}
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
[[ -z $BOOTPATCHDIR ]] && BOOTPATCHDIR="u-boot-$LINUXFAMILY"
[[ -z $ATFPATCHDIR ]] && ATFPATCHDIR="atf-$LINUXFAMILY"
[[ -z $KERNELPATCHDIR ]] && KERNELPATCHDIR="$LINUXFAMILY-$BRANCH"

if [[ "$RELEASE" =~ ^(xenial|bionic|focal|hirsute|impish|jammy)$ ]]; then
	DISTRIBUTION="Ubuntu"
else
	DISTRIBUTION="Debian"
fi

CLI_CONFIG_PATH="${SRC}/config/cli/${RELEASE}"
DEBOOTSTRAP_CONFIG_PATH="${CLI_CONFIG_PATH}/debootstrap"

AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS="
${SRC}/config
${SRC}/config/optional/_any_board/_config
${SRC}/config/optional/architectures/${ARCH}/_config
${SRC}/config/optional/families/${LINUXFAMILY}/_config
${SRC}/config/optional/boards/${BOARD}/_config
${USERPATCHES_PATH}
"

DEBOOTSTRAP_SEARCH_RELATIVE_DIRS="
cli/_all_distributions/debootstrap
cli/${RELEASE}/debootstrap
"

CLI_SEARCH_RELATIVE_DIRS="
cli/_all_distributions/main
cli/${RELEASE}/main
"

PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS="
${SRC}/packages
${SRC}/config/optional/_any_board/_packages
${SRC}/config/optional/architectures/${ARCH}/_packages
${SRC}/config/optional/families/${LINUXFAMILY}/_packages
${SRC}/config/optional/boards/${BOARD}/_packages
"

get_all_potential_paths() {
	local root_dirs="${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}"
	local rel_dirs="${1}"
	local sub_dirs="${2}"
	local looked_up_subpath="${3}"

	for root_dir in ${root_dirs}; do
		for rel_dir in ${rel_dirs}; do
			for sub_dir in ${sub_dirs}; do
				potential_paths+="${root_dir}/${rel_dir}/${sub_dir}/${looked_up_subpath} "
			done
		done
	done
}

aggregate_all_root_rel_sub() {
	local separator="${2}"
	local potential_paths=""

	get_all_potential_paths "${3}" "${4}" "${1}"
	aggregate_content
}

aggregate_all_debootstrap() {
	local sub_dirs_to_check=". "

	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi

	aggregate_all_root_rel_sub "${1}" "${2}" "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

aggregate_all_cli() {
	local sub_dirs_to_check=". "

	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi

	aggregate_all_root_rel_sub "${1}" "${2}" "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

one_line() {
	local aggregate_func_name="${1}"
	local aggregated_content=""

	shift 1

	$aggregate_func_name "${@}"

	cleanup_list aggregated_content
}

DEBOOTSTRAP_LIST="$(one_line aggregate_all_debootstrap "packages" " ")"
DEBOOTSTRAP_COMPONENTS="$(one_line aggregate_all_debootstrap "components" " ")"
DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS// /,}"
PACKAGE_LIST="$(one_line aggregate_all_cli "packages" " ")"
PACKAGE_LIST_ADDITIONAL="$(one_line aggregate_all_cli "packages.additional" " ")"

LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/debootstrap-list.log"

show_checklist_variables "DEBOOTSTRAP_LIST DEBOOTSTRAP_COMPONENTS PACKAGE_LIST PACKAGE_LIST_ADDITIONAL PACKAGE_LIST_UNINSTALL"

unset LOG_OUTPUT_FILE

DEBIAN_MIRROR='deb.debian.org/debian'
DEBIAN_SECURTY='security.debian.org/'
UBUNTU_MIRROR='ports.ubuntu.com/'

if [[ $DOWNLOAD_MIRROR == "china" ]] ; then
	DEBIAN_MIRROR='mirrors.tuna.tsinghua.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.tuna.tsinghua.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/'
fi

if [[ $DOWNLOAD_MIRROR == "bfsu" ]] ; then
	DEBIAN_MIRROR='mirrors.bfsu.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.bfsu.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.bfsu.edu.cn/ubuntu-ports/'
fi

if [[ "${ARCH}" == "amd64" ]]; then
	UBUNTU_MIRROR='archive.ubuntu.com/ubuntu'

	if [[ -n ${CUSTOM_UBUNTU_MIRROR} ]]; then
		UBUNTU_MIRROR="${CUSTOM_UBUNTU_MIRROR}"
	fi
fi

if [[ -z ${ARMBIAN_MIRROR} ]]; then
	while true; do
		ARMBIAN_MIRROR=$(wget -SO- -T 1 -t 1 https://redirect.armbian.com 2>&1 | egrep -i "Location" | awk '{print $2}' | head -1)

		[[ ${ARMBIAN_MIRROR} != *armbian.hosthatch* ]] && break
	done
fi

if [[ -f $USERPATCHES_PATH/lib.config ]]; then
	display_alert "Using user configuration override" "$USERPATCHES_PATH/lib.config" "info"

	source "$USERPATCHES_PATH"/lib.config
fi

call_extension_method "user_config" << 'USER_CONFIG'
*Invoke function with user override*
Allows for overriding configuration values set anywhere else.
It is called after sourcing the `lib.config` file if it exists,
but before assembling any package lists.
USER_CONFIG

call_extension_method "extension_prepare_config" << 'EXTENSION_PREPARE_CONFIG'
*allow extensions to prepare their own config, after user config is done*
Implementors should preserve variable values pre-set, but can default values an/or validate them.
This runs *after* user_config. Don't change anything not coming from other variables or meant to be configured by the user.
EXTENSION_PREPARE_CONFIG

if [[ $DISTRIBUTION == Ubuntu ]]; then
	APT_MIRROR=$UBUNTU_MIRROR
else
	APT_MIRROR=$DEBIAN_MIRROR
fi

[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"
PACKAGE_MAIN_LIST="$(cleanup_list PACKAGE_LIST)"
PACKAGE_LIST="$(cleanup_list PACKAGE_LIST)"

aggregated_content="${PACKAGE_LIST_RM} "
aggregate_all_cli "packages.remove" " "

PACKAGE_LIST_RM="$(cleanup_list aggregated_content)"

unset aggregated_content

aggregated_content=""
aggregate_all_cli "packages.uninstall" " "

PACKAGE_LIST_UNINSTALL="$(cleanup_list aggregated_content)"

unset aggregated_content

if [[ -n $PACKAGE_LIST_RM ]]; then
	display_alert "Package remove list ${PACKAGE_LIST_RM}"

	DEBOOTSTRAP_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${DEBOOTSTRAP_LIST} ")
	PACKAGE_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST} ")
	PACKAGE_MAIN_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_MAIN_LIST} ")

	DEBOOTSTRAP_LIST="$(echo ${DEBOOTSTRAP_LIST})"
	PACKAGE_LIST="$(echo ${PACKAGE_LIST})"
	PACKAGE_MAIN_LIST="$(echo ${PACKAGE_MAIN_LIST})"
fi

LOG_OUTPUT_FILE="$SRC/output/${LOG_SUBPATH}/debootstrap-list.log"

echo -e "\nVariables after manual configuration" >>$LOG_OUTPUT_FILE

show_checklist_variables "DEBOOTSTRAP_COMPONENTS DEBOOTSTRAP_LIST PACKAGE_LIST PACKAGE_MAIN_LIST"

unset LOG_OUTPUT_FILE

[[ -z $NAMESERVER ]] && NAMESERVER="1.0.0.1" # default is cloudflare alternate

call_extension_method "post_aggregate_packages" "user_config_post_aggregate_packages" << 'POST_AGGREGATE_PACKAGES'
*For final user override, using a function, after all aggregations are done*
Called after aggregating all package lists, before the end of `compilation.sh`.
Packages will still be installed after this is called, so it is the last chance
to confirm or change any packages.
POST_AGGREGATE_PACKAGES

cat <<-EOF >> "${DEST}"/${LOG_SUBPATH}/output.log

## BUILD SCRIPT ENVIRONMENT

Repository: $REPOSITORY_URL
Version: $REPOSITORY_COMMIT

Host OS: $HOSTRELEASE
Host arch: $(dpkg --print-architecture)
Host system: $(uname -a)
Virtualization type: $(systemd-detect-virt)

## Build script directories
Build directory is located on:
$(findmnt -o TARGET,SOURCE,FSTYPE,AVAIL -T "${SRC}")

Build directory permissions:
$(getfacl -p "${SRC}")

Temp directory permissions:
$(getfacl -p "${SRC}"/.tmp 2> /dev/null)

## BUILD CONFIGURATION

Build target:
Board: $BOARD
Branch: $BRANCH

Kernel configuration:
Repository: $KERNELSOURCE
Branch: $KERNELBRANCH
Config file: $LINUXCONFIG

U-boot configuration:
Repository: $BOOTSOURCE
Branch: $BOOTBRANCH
Config file: $BOOTCONFIG

Partitioning configuration: $IMAGE_PARTITION_TABLE offset: $OFFSET
Boot partition type: ${BOOTFS_TYPE:-(none)} ${BOOTSIZE:+"(${BOOTSIZE} MB)"}
Root partition type: $ROOTFS_TYPE ${FIXED_IMAGE_SIZE:+"(${FIXED_IMAGE_SIZE} MB)"}

CPU configuration: $CPUMIN - $CPUMAX with $GOVERNOR
EOF
