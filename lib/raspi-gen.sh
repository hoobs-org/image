#!/bin/bash

log (){
	date +"[%T] $*" | tee -a "${LOG_FILE}"
}

export -f log

run_sub_stage()
{
	display_alert "Running sub stage" "${SUB_STAGE_DIR}" "info"
	pushd "${SUB_STAGE_DIR}" > /dev/null

	for i in {00..99}; do
		if [ -f "${i}-debconf" ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-debconf" "info"

			on_chroot << EOF
debconf-set-selections <<SELEOF
$(cat "${i}-debconf")
SELEOF
EOF

		fi

		if [ -f "${i}-packages-nr" ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-packages-nr" "info"
			PACKAGES="$(cat "${i}-packages-nr")"

			if [ -n "$PACKAGES" ]; then
				on_chroot << EOF
apt-get -o APT::Acquire::Retries=3 install --no-install-recommends -y $PACKAGES
EOF

			fi
		fi

		if [ -f "${i}-packages" ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-packages" "info"
			PACKAGES="$(cat "${i}-packages")"

			if [ -n "$PACKAGES" ]; then
				on_chroot << EOF
apt-get -o APT::Acquire::Retries=3 install -y $PACKAGES
EOF

			fi
		fi

		if [ -d "${i}-patches" ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-patches" "info"
			pushd "${STAGE_WORK_DIR}" > /dev/null

			rm -rf .pc
			rm -rf ./*-pc

			QUILT_PATCHES="${SUB_STAGE_DIR}/${i}-patches"
			SUB_STAGE_QUILT_PATCH_DIR="$(basename "$SUB_STAGE_DIR")-pc"

			mkdir -p "$SUB_STAGE_QUILT_PATCH_DIR"
			ln -snf "$SUB_STAGE_QUILT_PATCH_DIR" .pc
			quilt upgrade

			if [ -e "${SUB_STAGE_DIR}/${i}-patches/EDIT" ]; then
				display_alert "Dropping into bash to edit patches" "" "info"
				bash
			fi

			RC=0
			quilt push -a || RC=$?

			case "$RC" in
				0|2)
					;;

				*)
					false
					;;
			esac

			popd > /dev/null
		fi

		if [ -x ${i}-run.sh ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-run.sh" "info"
			./${i}-run.sh
		fi

		if [ -f ${i}-run-chroot.sh ]; then
			display_alert "Running" "${SUB_STAGE_DIR}/${i}-run-chroot.sh" "info"
			on_chroot < ${i}-run-chroot.sh
		fi
	done

	popd > /dev/null
}

export -f run_sub_stage

run_stage(){
	display_alert "Running stage" "${STAGE_DIR}" "info"

	STAGE="$(basename "${STAGE_DIR}")"

	pushd "${STAGE_DIR}" > /dev/null

	STAGE_WORK_DIR="${WORK_DIR}/${STAGE}"
	ROOTFS_DIR="${STAGE_WORK_DIR}"/rootfs

	unmount "${WORK_DIR}/${STAGE}"

	if [ -d "${ROOTFS_DIR}" ]; then
		rm -rf "${ROOTFS_DIR}"
	fi

	if [ -x prerun.sh ]; then
		display_alert "Running" "${STAGE_DIR}/prerun.sh" "info"
		./prerun.sh
	fi

	for SUB_STAGE_DIR in "${STAGE_DIR}"/*; do
		if [ -d "${SUB_STAGE_DIR}" ]; then
			run_sub_stage
		fi
	done

	unmount "${WORK_DIR}/${STAGE}"

	PREV_STAGE="${STAGE}"
	PREV_STAGE_DIR="${STAGE_DIR}"
	PREV_ROOTFS_DIR="${ROOTFS_DIR}"

	popd > /dev/null
}

export -f run_stage

bootstrap(){
	local BOOTSTRAP_CMD=debootstrap
	local BOOTSTRAP_ARGS=()

	BOOTSTRAP_ARGS+=(--arch armhf)
	BOOTSTRAP_ARGS+=(--components "main,contrib,non-free")
	BOOTSTRAP_ARGS+=(--keyring "${STAGE_DIR}/files/raspberrypi.gpg")
	BOOTSTRAP_ARGS+=(--exclude=info)
	BOOTSTRAP_ARGS+=(--include=ca-certificates)
	BOOTSTRAP_ARGS+=("$@")
	printf -v BOOTSTRAP_STR '%q ' "${BOOTSTRAP_ARGS[@]}"

	setarch linux32 capsh --drop=cap_setfcap -- -c "'${BOOTSTRAP_CMD}' $BOOTSTRAP_STR" || true

	if [ -d "$2/debootstrap" ] && ! rmdir "$2/debootstrap"; then
		cp "$2/debootstrap/debootstrap.log" "${STAGE_WORK_DIR}"
		display_alert "bootstrap failed please check" "${STAGE_WORK_DIR}/debootstrap.log" "err"
		return 1
	fi
}

export -f bootstrap

copy_previous(){
	if [ ! -d "${PREV_ROOTFS_DIR}" ]; then
		display_alert "Previous stage rootfs not found" "" "err"
		false
	fi

	mkdir -p "${ROOTFS_DIR}"
	rsync -aHAXx --exclude var/cache/apt/archives "${PREV_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
}

export -f copy_previous

unmount(){
	if [ -z "$1" ]; then
		DIR=$PWD
	else
		DIR=$1
	fi

	while mount | grep -q "$DIR"; do
		local LOCS
		LOCS=$(mount | grep "$DIR" | cut -f 3 -d ' ' | sort -r)
		for loc in $LOCS; do
			umount "$loc"
		done
	done
}

export -f unmount

unmount_image(){
	sync
	sleep 1

	local LOOP_DEVICES

	LOOP_DEVICES=$(losetup --list | grep "$(basename "${1}")" | cut -f1 -d' ')

	for LOOP_DEV in ${LOOP_DEVICES}; do
		if [ -n "${LOOP_DEV}" ]; then
			local MOUNTED_DIR

			MOUNTED_DIR=$(mount | grep "$(basename "${LOOP_DEV}")" | head -n 1 | cut -f 3 -d ' ')

			if [ -n "${MOUNTED_DIR}" ] && [ "${MOUNTED_DIR}" != "/" ]; then
				unmount "$(dirname "${MOUNTED_DIR}")" > /dev/null
			fi

			sleep 1
			losetup -d "${LOOP_DEV}"
		fi
	done
}

export -f unmount_image

on_chroot() {
	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/proc)"; then
		mount -t proc proc "${ROOTFS_DIR}/proc"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/dev)"; then
		mount --bind /dev "${ROOTFS_DIR}/dev"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/dev/pts)"; then
		mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
	fi

	if ! mount | grep -q "$(realpath "${ROOTFS_DIR}"/sys)"; then
		mount --bind /sys "${ROOTFS_DIR}/sys"
	fi

	setarch linux32 capsh --drop=cap_setfcap "--chroot=${ROOTFS_DIR}/" -- -e "$@"
}

export -f on_chroot
