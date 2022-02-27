#!/bin/bash -e

mkdir -p "${SDCARD}"/etc/systemd/system/getty@.service.d/
mkdir -p "${SDCARD}"/etc/systemd/system/serial-getty@.service.d/

cat <<-EOF > "${SDCARD}"/etc/systemd/system/serial-getty@.service.d/override.conf
[Service]
ExecStartPre=/bin/sh -c 'exec /bin/sleep 10'
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I \$TERM
Type=idle
EOF

cp "${SDCARD}"/etc/systemd/system/serial-getty@.service.d/override.conf "${SDCARD}"/etc/systemd/system/getty@.service.d/override.conf
