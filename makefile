all: shasums

BUILD_FAMILIES := 1 2 3 4
BUILD_RELEASES := bullseye

platforms := $(foreach plat, $(BUILD_FAMILIES),$(foreach rel, $(BUILD_RELEASES),  raspi_$(plat)_$(rel)))

shasums: $(addsuffix .img.sha256,$(platforms)) $(addsuffix .img.xz.sha256,$(platforms))
xzimages: $(addsuffix .img.xz,$(platforms))
images: $(addsuffix .img,$(platforms))
yaml: $(addsuffix .yaml,$(platforms))

ifeq ($(shell id -u),0)
	as_root = 
else
	as_root = sudo
endif

target_platforms:
	@echo $(platforms)

blackwing.yaml: raspi.yaml
	cat raspi.yaml | \
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
	grep -v '__EXTRA_SHELL_CMDS__' > $@

%.sha256: %.img
	echo $@
	sha256sum $(@:sha256=img) > $@

%.img.xz.sha256: %.img.xz
	echo $@
	sha256sum $(@:img.xz.sha256=img.xz) > $@

%.img.xz: %.img
	xz -f -k -z -9 $(@:.xz=)

%.img.bmap: %.img
	bmaptool create -o $@ $<

%.img: %.yaml
	touch $(@:.img=.log)
	time nice $(as_root) vmdb2 --verbose --rootfs-tarball=$(subst .img,.tar.gz,$@) --output=$@ $(subst .img,.yaml,$@) --log $(subst .img,.log,$@)
	chmod 0644 $@ $(@,.img=.log)

_ck_root:
	[ `whoami` = 'root' ] # Only root can summon vmdb2 ☹

_clean_images:
	rm -f $(addsuffix .img,$(platforms))

_clean_xzimages:
	rm -f $(addsuffix .img.xz,$(platforms))

_clean_bmaps:
	rm -f $(addsuffix .img.bmap,$(platforms))

_clean_shasums:
	rm -f $(addsuffix .sha256,$(platforms)) $(addsuffix .img.xz.sha256,$(platforms))

_clean_logs:
	rm -f $(addsuffix .log,$(platforms))

_clean_tarballs:
	rm -f $(addsuffix .tar.gz,$(platforms))

clean: _clean_xzimages _clean_images _clean_shasums _clean_yaml _clean_tarballs _clean_logs _clean_bmaps

.PHONY: _ck_root _build_img clean _clean_images _clean_yaml _clean_tarballs _clean_logs
