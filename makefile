card-%: paths
	$(eval BUILD_VERSION := $(shell project version))
	$(eval NODE_REPO := $(shell project version nodesource))
	./compile $(BUILD_VERSION) BOARD=bananapim2ultra IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=bananapipro IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=orangepizero IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=orangepizeroplus IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=rock64 IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=tinkerboard IMG_TYPE=sdcard BRANCH=legacy RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)
	./compile $(BUILD_VERSION) BOARD=rpi IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst card-,,$@)

box-%: paths
	$(eval BUILD_VERSION := $(shell project version))
	$(eval NODE_REPO := $(shell project version nodesource))
	./compile $(BUILD_VERSION) BOARD=bananapim2ultra IMG_TYPE=box BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst box-,,$@)
	./compile $(BUILD_VERSION) BOARD=rpi IMG_TYPE=box BRANCH=current RELEASE=bullseye NODE_REPO=$(NODE_REPO) HOOBS_REPO=$(subst box-,,$@)

darwin: paths
	$(eval BUILD_VERSION := $(shell project version))
	$(eval NODE_VERSION := $(shell project version node))
	$(eval CLI_VERSION := $(shell ../cli/project version))
	$(eval HOOBSD_VERSION := $(shell ../hoobsd/project version))
	$(eval GUI_VERSION := $(shell ../gui/project version))
	cp -r config/darwin/rootfs cache/macos/darwin
	chmod -R 755 cache/macos/darwin/scripts
	chmod -R 755 cache/macos/darwin/
	mkdir -p cache/macos/packages
	cat config/darwin/distribution | \
	sed "s/__NODE_VERSION__/$(NODE_VERSION)/g" | \
	sed "s/__CLI_VERSION__/$(CLI_VERSION)/g" | \
	sed "s/__HOOBSD_VERSION__/$(HOOBSD_VERSION)/g" | \
	sed "s/__GUI_VERSION__/$(GUI_VERSION)/g" > cache/macos/darwin/Distribution
	chmod 755 cache/macos/darwin/Distribution
	mkdir -p cache/macos/node-$(NODE_VERSION).pkg
	mkdir -p cache/macos/node-$(NODE_VERSION).pkg/usr
	mkdir -p cache/macos/node-$(NODE_VERSION).pkg/usr/local
	curl https://nodejs.org/dist/v$(NODE_VERSION)/node-v$(NODE_VERSION)-darwin-x64.tar.xz --output cache/macos/node-$(NODE_VERSION).pkg/usr/local/node.xz
	(cd cache/macos/node-$(NODE_VERSION).pkg/usr/local && tar -xvf node.xz --strip-components=1 --no-same-owner)
	rm -f cache/macos/node-$(NODE_VERSION).pkg/usr/local/node.xz
	rm -f cache/macos/node-$(NODE_VERSION).pkg/usr/local/CHANGELOG.md
	rm -f cache/macos/node-$(NODE_VERSION).pkg/usr/local/LICENSE
	rm -f cache/macos/node-$(NODE_VERSION).pkg/usr/local/README.md
	pkgbuild --identifier org.nodejs.node.pkg --version $(NODE_VERSION) --root cache/macos/node-$(NODE_VERSION).pkg cache/macos/packages/node-$(NODE_VERSION).pkg
	mkdir -p cache/macos/hbs-$(CLI_VERSION).pkg
	mkdir -p cache/macos/hbs-$(CLI_VERSION).pkg/usr
	mkdir -p cache/macos/hbs-$(CLI_VERSION).pkg/usr/local
	mkdir -p cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/lib
	mkdir -p cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/bin
	(cd ../cli && make hbs-darwin)
	cp -R ../cli/cache/hbs cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/lib/
	cp ../cli/cache/package.json cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/lib/hbs/
	cp ../cli/main cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/bin/hbs
	chmod 755 cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/bin/hbs
	(cd cache/macos/hbs-$(CLI_VERSION).pkg/usr/local/lib/hbs && yarn install)
	pkgbuild --identifier org.hoobs.hbs.pkg --version $(CLI_VERSION) --root cache/macos/hbs-$(CLI_VERSION).pkg cache/macos/packages/hbs-$(CLI_VERSION).pkg
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/Library
	mkdir -p cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/Library/LaunchDaemons
	(cd ../hoobsd && make hoobsd-darwin)
	cp -R ../hoobsd/cache/hoobsd cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/
	cp ../hoobsd/cache/package.json cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd/
	cp config/darwin/org.hoobsd.plist cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/Library/LaunchDaemons/
	cp config/darwin/restart cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd/
	cp ../hoobsd/main cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin/hoobsd
	chmod 755 cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd/restart
	chmod 755 cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin/hoobsd
	(cd cache/macos/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd && yarn install)
	pkgbuild --identifier org.hoobs.hoobsd.pkg --version $(HOOBSD_VERSION) --scripts cache/macos/darwin/scripts --root cache/macos/hoobsd-$(HOOBSD_VERSION).pkg cache/macos/packages/hoobsd-$(HOOBSD_VERSION).pkg
	mkdir -p cache/macos/gui-$(GUI_VERSION).pkg
	mkdir -p cache/macos/gui-$(GUI_VERSION).pkg/usr
	mkdir -p cache/macos/gui-$(GUI_VERSION).pkg/usr/local
	mkdir -p cache/macos/gui-$(GUI_VERSION).pkg/usr/local/lib
	(cd ../lang && ./build)
	(cd ../gui && make locals)
	(cd ../gui && make deploy)
	cp -R ../gui/dist/usr/lib/hoobs cache/macos/gui-$(GUI_VERSION).pkg/usr/local/lib/
	pkgbuild --identifier org.hoobs.gui.pkg --version $(GUI_VERSION) --root cache/macos/gui-$(GUI_VERSION).pkg cache/macos/packages/gui-$(GUI_VERSION).pkg
	productbuild --distribution cache/macos/darwin/Distribution --resources cache/macos/darwin/Resources --package-path cache/macos/packages cache/macos/hoobs-v$(BUILD_VERSION)-darwin.pkg
	productsign --sign "Developer ID Installer: HOOBS Inc (SC929T2GA9)" cache/macos/hoobs-v$(BUILD_VERSION)-darwin.pkg output/images/hoobs-v$(BUILD_VERSION)-darwin.pkg
	(cd output/images && openssl sha256 hoobs-v$(BUILD_VERSION)-darwin.pkg | awk '{print $2}' > hoobs-v$(BUILD_VERSION)-darwin.sha265)

vendor: paths
	mkdir -p cache/vendor/dist
	mkdir -p cache/vendor/dist/DEBIAN
	cat config/motd/control | \
	sed "s/__VERSION__/$(shell project version)/" | \
	sed "s/__ARCH__/all/" > cache/vendor/dist/DEBIAN/control
	mkdir -p cache/vendor/dist/etc
	mkdir -p cache/vendor/dist/etc/update-motd.d
	cp config/motd/motd cache/vendor/dist/etc/hbs-motd
	cp config/motd/issue cache/vendor/dist/etc/hbs-issue
	cp config/motd/10-uname cache/vendor/dist/etc/update-motd.d/hbs-uname
	cp config/motd/20-network cache/vendor/dist/etc/update-motd.d/
	cp config/motd/preinst cache/vendor/dist/DEBIAN/
	cp config/motd/postinst cache/vendor/dist/DEBIAN/
	chmod 644 cache/vendor/dist/etc/hbs-motd
	chmod 644 cache/vendor/dist/etc/hbs-issue
	chmod 755 cache/vendor/dist/etc/update-motd.d/hbs-uname
	chmod 755 cache/vendor/dist/etc/update-motd.d/20-network
	chmod 755 cache/vendor/dist/DEBIAN/preinst
	chmod 755 cache/vendor/dist/DEBIAN/postinst
	(cd cache && dpkg-deb --build dist)
	cp cache/vendor/dist.deb output/packages/hbs-vendor-$(shell project version)-hoobs-all.deb
	dpkg-sig --sign builder output/packages/hbs-vendor-$(shell project version)-hoobs-all.deb
	rm -fR cache
	rm -f build.log

paths:
	rm -fR cache/macos
	rm -fR cache/vendor
	mkdir -p output
	mkdir -p output/config
	mkdir -p output/debug
	mkdir -p output/images
	mkdir -p output/patch
	mkdir -p cache
	mkdir -p cache/work
	mkdir -p cache/sources
	mkdir -p cache/hash
	mkdir -p cache/hash-beta
	mkdir -p cache/macos
	mkdir -p cache/packages
	mkdir -p cache/toolchain
	mkdir -p cache/utility
	mkdir -p cache/rootfs
	mkdir -p cache/vendor

clean:
	rm -fR .tmp
	rm -fR atf
	rm -fR output
	rm -fR cache
	rm -fR kernel
	rm -fR misc
	rm -fR overlay
	rm -fR u-boot
	rm -fR userpatches
