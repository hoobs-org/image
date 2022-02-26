#!/bin/bash

create_board_package()
{
	display_alert "Creating board support package for CLI" "$CHOSEN_ROOTFS" "info"

	bsptempdir=$(mktemp -d)
	chmod 700 ${bsptempdir}

	trap "rm -rf \"${bsptempdir}\" ; exit 0" 0 1 2 3 15

	local destination=${bsptempdir}/${BSP_CLI_PACKAGE_FULLNAME}

	mkdir -p "${destination}"/DEBIAN

	cd $destination

	copy_all_packages_files_for "bsp-cli"

	if [[ "${BOOTCONFIG}" != "none" ]]; then
		local bootscript_src=${BOOTSCRIPT%%:*}
		local bootscript_dst=${BOOTSCRIPT##*:}

		mkdir -p "${destination}"/usr/share/armbian/

		if [[ $SRC_EXTLINUX != yes ]]; then
			if [ -f "${USERPATCHES_PATH}/bootscripts/${bootscript_src}" ]; then
			  	cp "${USERPATCHES_PATH}/bootscripts/${bootscript_src}" "${destination}/usr/share/armbian/${bootscript_dst}"
			else
			  	cp "${SRC}/config/bootscripts/${bootscript_src}" "${destination}/usr/share/armbian/${bootscript_dst}"
			fi

			[[ -n $BOOTENV_FILE && -f $SRC/config/bootenv/$BOOTENV_FILE ]] && cp "${SRC}/config/bootenv/${BOOTENV_FILE}" "${destination}"/usr/share/armbian/armbianEnv.txt
		fi

		if [[ -n $UBOOT_FW_ENV ]]; then
			UBOOT_FW_ENV=($(tr ',' ' ' <<< "$UBOOT_FW_ENV"))

			mkdir -p "${destination}"/etc

			echo "# Device to access      offset           env size" > "${destination}"/etc/fw_env.config
			echo "/dev/mmcblk0	${UBOOT_FW_ENV[0]}	${UBOOT_FW_ENV[1]}" >> "${destination}"/etc/fw_env.config
		fi
	fi

	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${BSP_CLI_PACKAGE_NAME}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Section: kernel
	Priority: optional
	Depends: bash, linux-base, u-boot-tools, initramfs-tools, lsb-release, fping
	Provides: linux-${RELEASE}-root-legacy-$BOARD, linux-${RELEASE}-root-current-$BOARD, linux-${RELEASE}-root-edge-$BOARD
	Suggests: armbian-config
	Replaces: zram-config, base-files, armbian-tools-$RELEASE, linux-${RELEASE}-root-legacy-$BOARD (<< $REVISION~), linux-${RELEASE}-root-current-$BOARD (<< $REVISION~), linux-${RELEASE}-root-edge-$BOARD (<< $REVISION~)
	Breaks: linux-${RELEASE}-root-legacy-$BOARD (<< $REVISION~), linux-${RELEASE}-root-current-$BOARD (<< $REVISION~), linux-${RELEASE}-root-edge-$BOARD (<< $REVISION~)
	Recommends: bsdutils, parted, util-linux, toilet
	Description: Armbian board support files for $BOARD
	EOF

	cat <<-EOF > "${destination}"/DEBIAN/preinst
	#!/bin/sh

	[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required

	if [ -L "/etc/network/interfaces" ]; then
	    cp /etc/network/interfaces /etc/network/interfaces.tmp
	    rm /etc/network/interfaces
	    mv /etc/network/interfaces.tmp /etc/network/interfaces
	fi

	sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" /etc/initramfs-tools/initramfs.conf
	grep -q vm.swappiness /etc/sysctl.conf

	case \$? in
	    0)
	        sed -i 's/vm\.swappiness.*/vm.swappiness=100/' /etc/sysctl.conf
	        ;;

	    *)
	        echo vm.swappiness=100 >>/etc/sysctl.conf
	        ;;
	esac

	sysctl -p >/dev/null 2>&1

	[ -f "/etc/profile.d/activate_psd_user.sh" ] && rm /etc/profile.d/activate_psd_user.sh
	[ -f "/etc/profile.d/check_first_login.sh" ] && rm /etc/profile.d/check_first_login.sh
	[ -f "/etc/profile.d/check_first_login_reboot.sh" ] && rm /etc/profile.d/check_first_login_reboot.sh
	[ -f "/etc/profile.d/ssh-title.sh" ] && rm /etc/profile.d/ssh-title.sh
	[ -f "/etc/update-motd.d/10-header" ] && rm /etc/update-motd.d/10-header
	[ -f "/etc/update-motd.d/30-sysinfo" ] && rm /etc/update-motd.d/30-sysinfo
	[ -f "/etc/update-motd.d/35-tips" ] && rm /etc/update-motd.d/35-tips
	[ -f "/etc/update-motd.d/40-updates" ] && rm /etc/update-motd.d/40-updates
	[ -f "/etc/update-motd.d/98-autoreboot-warn" ] && rm /etc/update-motd.d/98-autoreboot-warn
	[ -f "/etc/update-motd.d/99-point-to-faq" ] && rm /etc/update-motd.d/99-point-to-faq
	[ -f "/etc/update-motd.d/80-esm" ] && rm /etc/update-motd.d/80-esm
	[ -f "/etc/update-motd.d/80-livepatch" ] && rm /etc/update-motd.d/80-livepatch
	[ -f "/etc/apt/apt.conf.d/02compress-indexes" ] && rm /etc/apt/apt.conf.d/02compress-indexes
	[ -f "/etc/apt/apt.conf.d/02periodic" ] && rm /etc/apt/apt.conf.d/02periodic
	[ -f "/etc/apt/apt.conf.d/no-languages" ] && rm /etc/apt/apt.conf.d/no-languages
	[ -f "/etc/init.d/armhwinfo" ] && rm /etc/init.d/armhwinfo
	[ -f "/etc/logrotate.d/armhwinfo" ] && rm /etc/logrotate.d/armhwinfo
	[ -f "/etc/init.d/firstrun" ] && rm /etc/init.d/firstrun
	[ -f "/etc/init.d/resize2fs" ] && rm /etc/init.d/resize2fs
	[ -f "/lib/systemd/system/firstrun-config.service" ] && rm /lib/systemd/system/firstrun-config.service
	[ -f "/lib/systemd/system/firstrun.service" ] && rm /lib/systemd/system/firstrun.service
	[ -f "/lib/systemd/system/resize2fs.service" ] && rm /lib/systemd/system/resize2fs.service
	[ -f "/usr/lib/armbian/apt-updates" ] && rm /usr/lib/armbian/apt-updates
	[ -f "/usr/lib/armbian/firstrun-config.sh" ] && rm /usr/lib/armbian/firstrun-config.sh
	[ -d "/var/lib/lightdm" ] && (chown -R lightdm:lightdm /var/lib/lightdm ; chmod 0750 /var/lib/lightdm)

	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/preinst

	cat <<-EOF > "${destination}"/DEBIAN/postrm
	#!/bin/sh

	if [ remove = "\$1" ] || [ abort-install = "\$1" ]; then
	    systemctl disable armbian-hardware-monitor.service armbian-hardware-optimize.service >/dev/null 2>&1
	    systemctl disable armbian-zram-config.service armbian-ramlog.service >/dev/null 2>&1
	fi

	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/postrm

	cat <<-EOF > "${destination}"/DEBIAN/postinst
	#!/bin/sh

	[ -f /etc/lib/systemd/system/armbian-ramlog.service ] && systemctl --no-reload enable armbian-ramlog.service

	if [ -n "\$(grep -w '^ENABLED=false' /etc/default/log2ram 2> /dev/null)" ]; then
	    sed -i "s/^ENABLED=.*/ENABLED=false/" /etc/default/armbian-ramlog
	fi

	if [ -f "/etc/initramfs-tools/initramfs.conf" ]; then
	    if ! grep --quiet "RESUME=none" /etc/initramfs-tools/initramfs.conf; then
	        echo "RESUME=none" >> /etc/initramfs-tools/initramfs.conf
	    fi
	fi
	EOF

	if [[ $FORCE_BOOTSCRIPT_UPDATE == yes ]]; then
	    cat <<-EOF >> "${destination}"/DEBIAN/postinst

	    if [ true ]; then
		EOF
	else
	    cat <<-EOF >> "${destination}"/DEBIAN/postinst
	    if [ ! -f /boot/$bootscript_dst ]; then
		EOF
	fi

	cat <<-EOF >> "${destination}"/DEBIAN/postinst
        [ -f /etc/armbian-release ] &&  . /etc/armbian-release
        [ -z \${VERSION} ] && VERSION=$(echo \`date +%s\`)

        if [ -f /boot/$bootscript_dst ]; then
           cp /boot/$bootscript_dst /usr/share/armbian/${bootscript_dst}-\${VERSION} >/dev/null 2>&1
           echo "NOTE: You can find previous bootscript versions in /usr/share/armbian !"
        fi

        ls /usr/share/armbian/boot.cmd-* >/dev/null 2>&1 | head -n -5 | xargs rm -f --
        ls /usr/share/armbian/boot.ini-* >/dev/null 2>&1 | head -n -5 | xargs rm -f --

        echo "Recreating boot script"

        cp /usr/share/armbian/$bootscript_dst /boot  >/dev/null 2>&1

        rootdev=\$(sed -e 's/^.*root=//' -e 's/ .*\$//' < /proc/cmdline)
        rootfstype=\$(sed -e 's/^.*rootfstype=//' -e 's/ .*$//' < /proc/cmdline)

        if [ ! -f /boot/armbianEnv.txt ] && [ ! -f /boot/extlinux/extlinux.conf ]; then
            cp /usr/share/armbian/armbianEnv.txt /boot  >/dev/null 2>&1

            echo "rootdev="\$rootdev >> /boot/armbianEnv.txt
            echo "rootfstype="\$rootfstype >> /boot/armbianEnv.txt
        fi

        [ -f /boot/boot.ini ] && sed -i "s/setenv rootdev.*/setenv rootdev \\"\$rootdev\\"/" /boot/boot.ini
        [ -f /boot/boot.ini ] && sed -i "s/setenv rootfstype.*/setenv rootfstype \\"\$rootfstype\\"/" /boot/boot.ini
        [ -f /boot/boot.cmd ] && mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr  >/dev/null 2>&1
    fi

	[ ! -f "/etc/network/interfaces" ] && [ -f "/etc/network/interfaces.default" ] && cp /etc/network/interfaces.default /etc/network/interfaces

	ln -sf /var/run/motd /etc/motd
	rm -f /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text

	if [ ! -f "/etc/default/armbian-motd" ]; then
		mv /etc/default/armbian-motd.dpkg-dist /etc/default/armbian-motd
	fi

	if [ ! -f "/etc/default/armbian-ramlog" ] && [ -f /etc/default/armbian-ramlog.dpkg-dist ]; then
		mv /etc/default/armbian-ramlog.dpkg-dist /etc/default/armbian-ramlog
	fi

	if [ ! -f "/etc/default/armbian-zram-config" ] && [ -f /etc/default/armbian-zram-config.dpkg-dist ]; then
		mv /etc/default/armbian-zram-config.dpkg-dist /etc/default/armbian-zram-config
	fi

	if [ -L "/usr/lib/chromium-browser/master_preferences.dpkg-dist" ]; then
		mv /usr/lib/chromium-browser/master_preferences.dpkg-dist /usr/lib/chromium-browser/master_preferences
	fi

	if [ -f /etc/lsb-release ]; then
		RELEASE=\$(cat /etc/lsb-release | grep CODENAME | cut -d"=" -f2 | sed 's/.*/\u&/')

		sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${VENDOR} $REVISION "\${RELEASE}"\"/" /etc/os-release

		echo "${VENDOR} ${REVISION} \${RELEASE} \\l \n" > /etc/issue
		echo "${VENDOR} ${REVISION} \${RELEASE}" > /etc/issue.net
	fi

	systemctl --no-reload enable armbian-hardware-monitor.service armbian-hardware-optimize.service armbian-zram-config.service >/dev/null 2>&1
	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/postinst
	rsync -a ${SRC}/packages/bsp/common/* ${destination}

	cat <<-EOF > "${destination}"/DEBIAN/triggers
	activate update-initramfs
	EOF

	local releases=($(find ${SRC}/config/distributions -mindepth 1 -maxdepth 1 -type d))

	for i in ${releases[@]}
	do
		echo "$(echo $i | sed 's/.*\///')=$(cat $i/support)" >> "${destination}"/etc/armbian-distribution-status
	done

	cat <<-EOF > "${destination}"/etc/armbian-release
	BOARD=$BOARD
	BOARD_NAME="$BOARD_NAME"
	BOARDFAMILY=${BOARDFAMILY}
	BUILD_REPOSITORY_URL=${BUILD_REPOSITORY_URL}
	BUILD_REPOSITORY_COMMIT=${BUILD_REPOSITORY_COMMIT}
	VERSION=$REVISION
	LINUXFAMILY=$LINUXFAMILY
	ARCH=$ARCHITECTURE
	IMAGE_TYPE=$IMAGE_TYPE
	BOARD_TYPE=$BOARD_TYPE
	INITRD_ARCH=$INITRD_ARCH
	KERNEL_IMAGE_TYPE=$KERNEL_IMAGE_TYPE
	EOF

	sed -i 's/#no-auto-down/no-auto-down/g' "${destination}"/etc/network/interfaces.default

	[[ $(type -t family_tweaks_bsp) == function ]] && family_tweaks_bsp

	call_extension_method "post_family_tweaks_bsp" << 'POST_FAMILY_TWEAKS_BSP'
*family_tweaks_bsp overrrides what is in the config, so give it a chance to override the family tweaks*
This should be implemented by the config to tweak the BSP, after the board or family has had the chance to.
POST_FAMILY_TWEAKS_BSP

	find "${destination}" -print0 2>/dev/null | xargs -0r chown --no-dereference 0:0
	find "${destination}" ! -type l -print0 2>/dev/null | xargs -0r chmod 'go=rX,u+rw,a-s'

	fakeroot dpkg-deb -b -Z${DEB_COMPRESS} "${destination}" "${destination}.deb" >> "${DEST}"/${LOG_SUBPATH}/output.log 2>&1
	mkdir -p "${DEB_STORAGE}/"
	rsync --remove-source-files -rq "${destination}.deb" "${DEB_STORAGE}/"

	rm -rf ${bsptempdir}
}