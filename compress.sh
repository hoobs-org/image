set -e

qemu-img create -f raw compr.img 1100M

sfdisk --quiet --dump raspi3.img | sfdisk --quiet compr.img

readarray rmappings < <(sudo kpartx -asv raspi3.img)
readarray cmappings < <(sudo kpartx -asv compr.img)

set -- ${rmappings[0]}

rboot="$3"

set -- ${cmappings[0]}

cboot="$3"
sudo dd if=/dev/mapper/${rboot?} of=/dev/mapper/${cboot?} bs=5M status=none

set -- ${rmappings[1]}

rroot="$3"

set -- ${cmappings[1]}

croot="$3"

sudo e2fsck -y -f /dev/mapper/${rroot?}
sudo resize2fs /dev/mapper/${rroot?} 800M
sudo e2image -rap /dev/mapper/${rroot?} /dev/mapper/${croot?}

sudo kpartx -ds raspi3.img
sudo kpartx -ds compr.img

xz -8 -f compr.img
