#!/bin/bash

export PROGRESS_DISPLAY=dialog
export OUTPUT_DIALOG=yes
export SHOW_WARNING=yes

cleanup_list() {
	local varname="${1}"
	local list_to_clean="${!varname}"

	list_to_clean="${list_to_clean#"${list_to_clean%%[![:space:]]*}"}"
	list_to_clean="${list_to_clean%"${list_to_clean##*[![:space:]]}"}"

	echo ${list_to_clean}
}

if [[ $(basename "$0") == main.sh ]]; then
	echo "Please use compile to start the build process"
	exit 255
fi

umask 002

if [ -d "$CONFIG_PATH/output" ]; then
	export DEST="${CONFIG_PATH}"/output
else
	export DEST="${SRC}"/output
fi

if [[ $BUILD_ALL != "yes" && -z $ROOT_FS_CREATE_ONLY ]]; then
	[[ -n $COLUMNS ]] && stty cols $COLUMNS
	[[ -n $LINES ]] && stty rows $LINES

	export TTY_X=$(($(stty size | awk '{print $2}')-6))
	export TTY_Y=$(($(stty size | awk '{print $1}')-6))
fi

export BUILD_VERSION
export BACKTITLE="HOOBS ${BUILD_VERSION} Image Build Utility"

[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"

source "${SRC}"/lib/debootstrap.sh
source "${SRC}"/lib/image-helpers.sh
source "${SRC}"/lib/distributions.sh
source "${SRC}"/lib/compilation.sh
source "${SRC}"/lib/compilation-prepare.sh
source "${SRC}"/lib/makeboarddeb.sh
source "${SRC}"/lib/general.sh
source "${SRC}"/lib/chroot-buildpackages.sh

export LOG_SUBPATH=${LOG_SUBPATH:=debug}

mkdir -p "${DEST}"/${LOG_SUBPATH}
(cd "${DEST}"/${LOG_SUBPATH} && tar -czf logs-"$(<timestamp)".tgz ./*.log) > /dev/null 2>&1
rm -f "${DEST}"/${LOG_SUBPATH}/*.log > /dev/null 2>&1
date +"%d_%m_%Y-%H_%M_%S" > "${DEST}"/${LOG_SUBPATH}/timestamp

(cd "${DEST}"/${LOG_SUBPATH} && find . -name '*.tgz' -mtime +7 -delete) > /dev/null

if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

if [[ $USE_CCACHE != no ]]; then
	export CCACHE=ccache
	export PATH="/usr/lib/ccache:$PATH"

	[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache
else
	export CCACHE=""
fi

if [[ -n $REPOSITORY_UPDATE ]]; then
	if [[ $BETA == yes ]]; then
		export DEB_STORAGE=$DEST/debs-beta
		export REPO_STORAGE=$DEST/repository-beta
		export REPO_CONFIG="aptly-beta.conf"
	else
		export DEB_STORAGE=$DEST/debs
		export REPO_STORAGE=$DEST/repository
		export REPO_CONFIG="aptly.conf"
	fi

	if [[ -f "${USERPATCHES_PATH}"/lib.config ]]; then
		display_alert "Using user configuration override" "userpatches/lib.config" "info"

		source "${USERPATCHES_PATH}"/lib.config
	fi

	repo-manipulate "$REPOSITORY_UPDATE"
	exit
fi

if [[ -z $BOARD ]]; then
	options=()

	for board in "${SRC}"/config/boards/*.conf; do
		options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z2$(head -2 "${board}" | tail -1 | sed 's/export //' | sed 's/BOARD_NAME="//' | sed 's/"//') \Zn$(head -1 "${board}" | cut -d'#' -f2)")
	done

	BOARD=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "Choose a board" --backtitle "$BACKTITLE" --scrollbar --colors --menu "Select the target board" 50 150 $((50 - 8)) "${options[@]}")

	STATUS=$?

	unset options

	[[ -z $BOARD ]] && exit_with_error "No board selected"
fi

export BOARD

source "${SRC}/config/boards/${BOARD}.conf"

export LINUXFAMILY="${BOARDFAMILY}"

[[ -z $KERNEL_TARGET && $BOOT_METHOD == uboot ]] && exit_with_error "Board configuration does not define valid kernel config"

if [[ -z $IMG_TYPE ]]; then
	options+=("sdcard" "Build image for SD cards")
	options+=("box" "Build image for the HOOBS Box")

	IMG_TYPE=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "Choose a build option" --backtitle "$BACKTITLE" --menu "Select the image build type" 50 150 $((50 - 8)) "${options[@]}")

	unset options

	[[ -z $IMG_TYPE ]] && exit_with_error "No option selected"
fi

export IMG_TYPE

if [[ -z $BRANCH && $BOOT_METHOD == uboot ]]; then
	options=()

	[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Recommended")
	[[ $KERNEL_TARGET == *legacy* ]] && options+=("legacy" "Old stable")
	[[ $KERNEL_TARGET == *edge* ]] && options+=("edge" "Bleeding edge")

	if [[ "${#options[@]}" == 2 ]]; then
		BRANCH="${options[0]}"
	else
		BRANCH=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "Choose a kernel" --backtitle "$BACKTITLE" --colors --menu "Select the target kernel branch\nExact kernel versions depend on selected board" 50 150 $((50 - 8)) "${options[@]}")
	fi

	unset options

	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected"
	[[ $BRANCH == dev && $SHOW_WARNING == yes ]] && show_developer_warning
elif [[ $BOOT_METHOD == uboot ]]; then
	[[ $BRANCH == next ]] && KERNEL_TARGET="next"
	[[ $KERNEL_TARGET != *$BRANCH* ]] && exit_with_error "Kernel branch not defined for this board" "$BRANCH"
fi

export BRANCH

if [[ -z $RELEASE ]]; then
	options=()
	distros_options

	RELEASE=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "Choose a release package base" --backtitle "$BACKTITLE" --menu "Select the target OS release package base" 50 150 $((50 - 8)) "${options[@]}")

	[[ -z $RELEASE ]] && exit_with_error "No release selected"

	unset options
fi

export RELEASE

if [[ -z $NODE_REPO ]]; then
	options=()
	nodesource_options

	NODE_REPO=$(DIALOGRC="${SRC}/config/dialog.conf" dialog --stdout --keep-tite --title "Choose a Node release" --backtitle "$BACKTITLE" --menu "Select the desired Node release branch" 50 150 $((50 - 8)) "${options[@]}")

	[[ -z $NODE_REPO ]] && exit_with_error "No node branch selected"

	unset options
fi

export NODE_REPO

if [[ $BOOT_METHOD == uboot ]]; then
	source "${SRC}"/lib/configuration.sh

	CPUS=$(grep -c 'processor' /proc/cpuinfo)

	if [[ $USEALLCORES != no ]]; then
		CTHREADS="-j$((CPUS + CPUS/2))"
	else
		CTHREADS="-j1"
	fi

	call_extension_method "post_determine_cthreads" "config_post_determine_cthreads" << 'POST_DETERMINE_CTHREADS'
*give config a chance modify CTHREADS programatically. A build server may work better with hyperthreads-1 for example.*
Called early, before any compilation work starts.
POST_DETERMINE_CTHREADS

	if [[ $BETA == yes ]]; then
		IMAGE_TYPE=nightly
	elif [[ $BETA != "yes" && $BUILD_ALL == yes && -n $GPG_PASS ]]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	branch2dir() {
		[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
	}

	BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	LINUXSOURCEDIR="${KERNELDIR}/$(branch2dir "${KERNELBRANCH}")"

	[[ -n $ATFSOURCE ]] && ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

	BSP_CLI_PACKAGE_NAME="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}"
	BSP_CLI_PACKAGE_FULLNAME="${BSP_CLI_PACKAGE_NAME}_${REVISION}_${ARCH}"
	BSP_DESKTOP_PACKAGE_NAME="armbian-bsp-desktop-${BOARD}${EXTRA_BSP_NAME}"
	BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_PACKAGE_NAME}_${REVISION}_${ARCH}"

	CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}
	CHOSEN_KERNEL=linux-image-${BRANCH}-${LINUXFAMILY}
	CHOSEN_ROOTFS=${BSP_CLI_PACKAGE_NAME}
	CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}
fi

do_uboot() {
	start=$(date +%s)

	prepare_host

	[[ "${JUST_INIT}" == "yes" ]] && exit 0
	[[ $CLEAN_LEVEL == *sources* ]] && cleaning "sources"

	if [[ $IGNORE_UPDATES != yes ]]; then
		display_alert "Downloading sources" "" "info"

		[[ -n $BOOTSOURCE ]] && fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes"
		[[ -n $ATFSOURCE ]] && fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"

		if [[ -n $KERNELSOURCE ]]; then
			if $(declare -f var_origin_kernel >/dev/null); then
				unset LINUXSOURCEDIR

				LINUXSOURCEDIR="linux-mainline/$KERNEL_VERSION_LEVEL"
				VAR_SHALLOW_ORIGINAL=var_origin_kernel
				waiter_local_git "url=$KERNELSOURCE $KERNELSOURCENAME $KERNELBRANCH dir=$LINUXSOURCEDIR $KERNELSWITCHOBJ"

				unset VAR_SHALLOW_ORIGINAL
			else
				fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
			fi
		fi

		call_extension_method "fetch_sources_tools"  <<- 'FETCH_SOURCES_TOOLS'
		*fetch host-side sources needed for tools and build*
		Run early to fetch_from_repo or otherwise obtain sources for needed tools.
		FETCH_SOURCES_TOOLS

		call_extension_method "build_host_tools"  <<- 'BUILD_HOST_TOOLS'
		*build needed tools for the build, host-side*
		After sources are fetched, build host-side tools needed for the build.
		BUILD_HOST_TOOLS

		for option in $(tr ',' ' ' <<< "$CLEAN_LEVEL"); do
			[[ $option != sources ]] && cleaning "$option"
		done
	fi

	[[ "${BOOTCONFIG}" != "none" ]] && {
		if [[ ! -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then
			if [[ -n "${ATFSOURCE}" && "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
				compile_atf
			fi

			[[ "${REPOSITORY_INSTALL}" != *u-boot* ]] && compile_uboot
		fi
	}

	if [[ ! -f ${DEB_STORAGE}/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb ]]; then
		KDEB_CHANGELOG_DIST=$RELEASE

		[[ -n $KERNELSOURCE ]] && [[ "${REPOSITORY_INSTALL}" != *kernel* ]] && compile_kernel
	fi

	if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then
		[[ "${REPOSITORY_INSTALL}" != *armbian-config* ]] && compile_armbian-config
	fi

	if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then
		[[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]] && compile_armbian-zsh
	fi

	if ! ls "${DEB_STORAGE}/armbian-firmware_${REVISION}_all.deb" 1> /dev/null 2>&1 || ! ls "${DEB_STORAGE}/armbian-firmware-full_${REVISION}_all.deb" 1> /dev/null 2>&1; then
		if [[ "${REPOSITORY_INSTALL}" != *armbian-firmware* ]]; then
			[[ "${INSTALL_ARMBIAN_FIRMWARE:-yes}" == "yes" ]] && { # Build firmware by default.
				FULL=""
				REPLACE="-full"
				compile_firmware
				FULL="-full"
				REPLACE=""
				compile_firmware
			}
		fi
	fi

	overlayfs_wrapper "cleanup"

	[[ -n "${RELEASE}" && ! -f "${DEB_STORAGE}/${BSP_CLI_PACKAGE_FULLNAME}.deb" && "${REPOSITORY_INSTALL}" != *armbian-bsp-cli* ]] && create_board_package

	if [ "$IMAGE_PRESENT" == yes ] && ls "${FINALDEST}/${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"*.xz 1> /dev/null 2>&1; then
		display_alert "Skipping image creation" "image already made - IMAGE_PRESENT is set" "wrn"
		exit
	fi

	[[ $EXTERNAL_NEW == compile ]] && chroot_build_packages

	debootstrap_ng

	call_extension_method "run_after_build"  << 'RUN_AFTER_BUILD'
*hook for function to run after build, i.e. to change owner of `$SRC`*
Really one of the last hooks ever called. The build has ended. Congratulations.
- *NOTE:* this will run only if there were no errors during build process.
RUN_AFTER_BUILD

	end=$(date +%s)
	runtime=$(((end-start)/60))
	display_alert "Runtime" "$runtime min" "ext"
}

do_raspi() {
	start=$(date +%s)

	prepare_host_raspi

	export IMG_FILENAME="hoobs-v${BUILD_VERSION}-$(echo "${BOARD}" | sed 's/[A-Z]/\L&/g')-${IMG_TYPE}"
	export WORK_DIR="${SRC}/cache/work/${BOARD}-${RELEASE}"
	export DEPLOY_DIR="${DEST}/images"
	export LOG_FILE="${DEST}/${LOG_SUBPATH}/${BOARD}-${RELEASE}.log"

	export STAGE
	export STAGE_DIR
	export STAGE_WORK_DIR
	export PREV_STAGE
	export PREV_STAGE_DIR
	export ROOTFS_DIR
	export PREV_ROOTFS_DIR
	export EXPORT_DIR
	export EXPORT_ROOTFS_DIR
	export BOOT_METHOD

	source "${SRC}/lib/raspi-gen.sh"

	mkdir -p "${WORK_DIR}"

	STAGE_DIR=$(realpath "${SRC}/config/stages/firmware")
	run_stage

	STAGE_DIR=$(realpath "${SRC}/config/stages/system")
	run_stage

	STAGE_DIR=$(realpath "${SRC}/config/stages/packages")
	run_stage

	STAGE_DIR=$(realpath "${SRC}/config/stages/customize")
	run_stage

	STAGE_DIR=$(realpath "${SRC}/config/stages/image")
	EXPORT_ROOTFS_DIR=${WORK_DIR}/customize/rootfs
	run_stage

	display_alert "Cleaning up" "${WORK_DIR}" "info"
	rm -fR ${WORK_DIR}
}

case $BOOT_METHOD in
	raspi)
		do_raspi
		;;

	uboot)
		do_uboot
		;;
esac
