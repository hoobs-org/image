#!/bin/bash -e

echo "hoobs" > "${ROOTFS_DIR}/etc/hostname"
echo "127.0.1.1		hoobs" >> "${ROOTFS_DIR}/etc/hosts"

on_chroot << EOF
	SUDO_USER="hoobs" raspi-config nonint do_net_names 1
EOF
