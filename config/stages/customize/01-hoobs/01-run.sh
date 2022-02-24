#!/bin/bash -e

install -v -m 755 "${SRC}/install.sh" "${ROOTFS_DIR}/tmp/"

on_chroot << EOF
/bin/bash -c "/tmp/install.sh $BUILD_VERSION $RELEASE $BOARD $NODE_REPO $IMG_TYPE $BOOT_METHOD"
EOF
