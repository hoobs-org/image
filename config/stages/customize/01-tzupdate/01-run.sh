#!/bin/bash -e

install -v -m 755 "${SRC}/packages/tzupdate/tzupdate.sh" "${ROOTFS_DIR}/tmp/"
install -v -m 755 "${SRC}/packages/tzupdate/tzupdate.py" "${ROOTFS_DIR}/usr/lib/python3.9/"

on_chroot << EOF
/bin/bash -c "/tmp/tzupdate.sh $BUILD_VERSION $RELEASE $BOARD $NODE_REPO $IMG_TYPE $BOOT_METHOD"
EOF
