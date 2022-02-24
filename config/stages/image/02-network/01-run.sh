#!/bin/bash -e

on_chroot <<EOF
rm /etc/resolv.conf
ln -sf /lib/systemd/resolv.conf /etc/resolv.conf
EOF
