USER=`whoami`
VERSION=`node -e 'console.log(require("./package.json").version)'`

ifeq ($(shell id -u),0)
	as_root = 
else
	as_root = sudo
endif

hoobs-box-version-arm64.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__FIRMWARE_PKG__/raspi-firmware/" | \
	grep -v "__OTHER_APT_ENABLE__" | \
	grep -v "__FIX_FIRMWARE_PKG_NAME__" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/arm64/" | \
	sed "s/__LINUX_IMAGE__/linux-image-arm64/" | \
	sed "s/__EXTRA_PKGS__/- firmware-brcm80211/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-arm64\\/broadcom\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyS1,115200/" | \
	sed "s/__HOST__/hoobs/" | \
	sed "s/__FIRST_USER__/hoobs/" | \
	sed "s/__FIRST_USER_PASSWD__/hoobsadmin/" | \
	sed "s/__GIT_USER__/hoobs/" | \
	sed "s/__VENDOR_ID__/box/" | \
	sed "s/__VENDOR_MODEL__/HSLF-1/" | \
	sed "s/__VENDOR_SKU__/7-45114-12419-7/" | \
	grep -v '__EXTRA_SHELL_CMDS__' > cache/$(subst -version-,-,$@)

hoobs-version-arm64.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__FIRMWARE_PKG__/raspi-firmware/" | \
	grep -v "__OTHER_APT_ENABLE__" | \
	grep -v "__FIX_FIRMWARE_PKG_NAME__" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/arm64/" | \
	sed "s/__LINUX_IMAGE__/linux-image-arm64/" | \
	sed "s/__EXTRA_PKGS__/- firmware-brcm80211/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-arm64\\/broadcom\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyS1,115200/" | \
	sed "s/__HOST__/hoobs/" | \
	sed "s/__FIRST_USER__/hoobs/" | \
	sed "s/__FIRST_USER_PASSWD__/hoobsadmin/" | \
	sed "s/__GIT_USER__/hoobs/" | \
	sed "s/__VENDOR_ID__/card/" | \
	sed "s/__VENDOR_MODEL__/HSLF-2/" | \
	sed "s/__VENDOR_SKU__/7-45114-12418-0/" | \
	grep -v '__EXTRA_SHELL_CMDS__' > cache/$(subst -version-,-,$@)

%.img.xz.sha256: paths %.img.xz
	$(eval NAME := $(subst -version-,-v$(VERSION)-,$@))
	sha256sum builds/$(subst .img.xz.sha256,.xz,$(NAME)) > builds/$(subst .img.xz.sha256,.sha256,$(NAME))

%.img.xz: paths %.img
	$(eval NAME := $(subst -version-,-v$(VERSION)-,$@))
	xz -f -k -z -9 builds/$(subst .img.xz,.img,$(NAME))
	mv builds/$(NAME) builds/$(subst .img.xz,.xz,$(NAME))

%.img: paths %.yaml
	$(eval BASE := $(subst -version-,-,$@))
	$(eval NAME := $(subst -version-,-v$(VERSION)-,$@))
	$(eval CACHE := $(subst .img,.tar.gz,$(BASE)))
	$(eval CACHE := $(subst hoobs-,,$(CACHE)))
	$(eval CACHE := $(subst box-,,$(CACHE)))
	time nice $(as_root) vmdb2 --verbose --rootfs-tarball=cache/$(CACHE) --output=builds/$(NAME) cache/$(subst .img,.yaml,$(BASE)) --log build.log
	rm -f cache/$(subst .img,.yaml,$(BASE))
	$(as_root) chown ${USER}:${USER} builds/$(NAME)

paths:
	@echo $(VERSION)
	touch build.log
	mkdir -p builds
	mkdir -p cache

clean:
	rm -fR cache
	rm -f build.log
