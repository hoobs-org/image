#!/bin/bash -e

install -v -m 755 "${SRC}/install.sh" "${ROOTFS_DIR}/tmp/"

on_chroot << EOF
/bin/bash -c "/tmp/install.sh $RELEASE $NODE_REPO $HOOBS_REPO $IMG_TYPE
EOF
