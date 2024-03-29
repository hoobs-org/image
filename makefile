ifeq ($(shell id -u),0)
	as_root = 
else
	as_root = sudo
endif

hoobs-box-version-arm64.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/arm64/" | \
	sed "s/__LINUX_IMAGE__/linux-image-arm64/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-arm64\\/broadcom\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyS1,115200/" | \
	sed "s/__NODE_REPO__/$(shell project version nodesource)/" | \
	sed "s/__VENDOR_ID__/box/" | \
	sed "s/__VENDOR_MODEL__/HSLF-1/" | \
	sed "s/__VENDOR_SKU__/7-45114-12419-7/" > cache/$(subst -version-,-,$@)

hoobs-version-arm64.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/arm64/" | \
	sed "s/__LINUX_IMAGE__/linux-image-arm64/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-arm64\\/broadcom\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyS1,115200/" | \
	sed "s/__NODE_REPO__/$(shell project version nodesource)/" | \
	sed "s/__VENDOR_ID__/card/" | \
	sed "s/__VENDOR_MODEL__/HSLF-2/" | \
	sed "s/__VENDOR_SKU__/7-45114-12418-0/" > cache/$(subst -version-,-,$@)

hoobs-version-armhf.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/armhf/" | \
	sed "s/__LINUX_IMAGE__/linux-image-armmp/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-armmp\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyAMA0,115200/" | \
	sed "s/__VENDOR_ID__/card/" | \
	sed "s/__NODE_REPO__/$(shell project version nodesource)/" | \
	sed "s/__VENDOR_MODEL__/HSLF-2/" | \
	sed "s/__VENDOR_SKU__/7-45114-12418-0/" > cache/$(subst -version-,-,$@)

%.img.xz.sha256: paths %.img.xz
	$(eval NAME := $(subst -version-,-v$(shell project version)-,$@))
	(cd builds && sha256sum $(subst .img.xz.sha256,.xz,$(NAME)) > $(subst .img.xz.sha256,.sha256,$(NAME)))

%.img.xz: paths %.img
	$(eval NAME := $(subst -version-,-v$(shell project version)-,$@))
	xz -f -k -z -9 builds/$(subst .img.xz,.img,$(NAME))
	rm -f builds/$(subst .img.xz,.img,$(NAME))
	mv builds/$(NAME) builds/$(subst .img.xz,.xz,$(NAME))

%.img: paths %.yaml
	$(eval BASE := $(subst -version-,-,$@))
	$(eval NAME := $(subst -version-,-v$(shell project version)-,$@))
	$(eval CACHE := $(subst .img,.tar.gz,$(BASE)))
	$(eval CACHE := $(subst hoobs-,,$(CACHE)))
	$(eval CACHE := $(subst box-,,$(CACHE)))
	time nice $(as_root) vmdb2 --verbose --rootfs-tarball=cache/$(CACHE) --output=builds/$(NAME) cache/$(subst .img,.yaml,$(BASE)) --log build.log
	rm -f cache/$(subst .img,.yaml,$(BASE))
	$(as_root) chown $(shell whoami):$(shell whoami) builds/$(NAME)

paths:
	@echo $(shell project version)
	touch build.log
	mkdir -p builds
	mkdir -p cache

clean:
	rm -fR cache
	rm -f build.log
