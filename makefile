ifeq ($(shell id -u),0)
	as_root = 
else
	as_root = sudo
endif

hoobs-package: clean paths hoobs-package-deploy hoobs-package-control hoobs-package-node hoobs-package-cli hoobs-package-hoobsd hoobs-package-gui
	$(eval VERSION := $(shell project version))
	productbuild --distribution cache/darwin/Distribution --resources cache/darwin/Resources --package-path cache/packages cache/hoobs-$(VERSION)-darwin.pkg
	productsign --sign "Developer ID Installer: HOOBS Inc (SC929T2GA9)" cache/hoobs-$(VERSION)-darwin.pkg builds/hoobs-$(VERSION)-darwin.pkg

hoobs-package-node:
	$(eval NODE_VERSION := $(shell project version node))
	mkdir -p cache/node-$(NODE_VERSION).pkg
	mkdir -p cache/node-$(NODE_VERSION).pkg/usr
	mkdir -p cache/node-$(NODE_VERSION).pkg/usr/local
	curl https://nodejs.org/dist/v$(NODE_VERSION)/node-v$(NODE_VERSION)-darwin-x64.tar.xz --output cache/node-$(NODE_VERSION).pkg/usr/local/node.xz
	(cd cache/node-$(NODE_VERSION).pkg/usr/local && tar -xvf node.xz --strip-components=1 --no-same-owner)
	rm -f cache/node-$(NODE_VERSION).pkg/usr/local/node.xz
	rm -f cache/node-$(NODE_VERSION).pkg/usr/local/CHANGELOG.md
	rm -f cache/node-$(NODE_VERSION).pkg/usr/local/LICENSE
	rm -f cache/node-$(NODE_VERSION).pkg/usr/local/README.md
	pkgbuild --identifier org.nodejs.node.pkg --version $(NODE_VERSION) --root cache/node-$(NODE_VERSION).pkg cache/packages/node-$(NODE_VERSION).pkg

hoobs-package-cli:
	$(eval CLI_VERSION := $(shell ../cli/project version))
	mkdir -p cache/hbs-$(CLI_VERSION).pkg
	mkdir -p cache/hbs-$(CLI_VERSION).pkg/usr
	mkdir -p cache/hbs-$(CLI_VERSION).pkg/usr/local
	mkdir -p cache/hbs-$(CLI_VERSION).pkg/usr/local/lib
	mkdir -p cache/hbs-$(CLI_VERSION).pkg/usr/local/bin
	(cd ../cli && make hbs-darwin)
	cp -R ../cli/cache/hbs cache/hbs-$(CLI_VERSION).pkg/usr/local/lib/
	cp ../cli/cache/package.json cache/hbs-$(CLI_VERSION).pkg/usr/local/lib/hbs/
	cp ../cli/main cache/hbs-$(CLI_VERSION).pkg/usr/local/bin/hbs
	chmod 755 cache/hbs-$(CLI_VERSION).pkg/usr/local/bin/hbs
	(cd cache/hbs-$(CLI_VERSION).pkg/usr/local/lib/hbs && yarn install)
	pkgbuild --identifier org.hoobs.hbs.pkg --version $(CLI_VERSION) --root cache/hbs-$(CLI_VERSION).pkg cache/packages/hbs-$(CLI_VERSION).pkg

hoobs-package-gui:
	$(eval GUI_VERSION := $(shell ../gui/project version))
	mkdir -p cache/gui-$(GUI_VERSION).pkg
	mkdir -p cache/gui-$(GUI_VERSION).pkg/usr
	mkdir -p cache/gui-$(GUI_VERSION).pkg/usr/local
	mkdir -p cache/gui-$(GUI_VERSION).pkg/usr/local/lib
	(cd ../lang && ./build)
	(cd ../gui && make locals)
	(cd ../gui && make deploy)
	cp -R ../gui/dist/usr/lib/hoobs cache/gui-$(GUI_VERSION).pkg/usr/local/lib/
	pkgbuild --identifier org.hoobs.gui.pkg --version $(GUI_VERSION) --root cache/gui-$(GUI_VERSION).pkg cache/packages/gui-$(GUI_VERSION).pkg

hoobs-package-hoobsd:
	$(eval HOOBSD_VERSION := $(shell ../hoobsd/project version))
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/usr
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/Library
	mkdir -p cache/hoobsd-$(HOOBSD_VERSION).pkg/Library/LaunchDaemons
	(cd ../hoobsd && make hoobsd-darwin)
	cp -R ../hoobsd/cache/hoobsd cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/
	cp ../hoobsd/cache/package.json cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd/
	cp rootfs/Library/LaunchDaemons/org.hoobsd.plist cache/hoobsd-$(HOOBSD_VERSION).pkg/Library/LaunchDaemons/
	cp ../hoobsd/main cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin/hoobsd
	chmod 755 cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/bin/hoobsd
	(cd cache/hoobsd-$(HOOBSD_VERSION).pkg/usr/local/lib/hoobsd && yarn install)
	pkgbuild --identifier org.hoobs.hoobsd.pkg --version $(HOOBSD_VERSION) --scripts cache/darwin/scripts --root cache/hoobsd-$(HOOBSD_VERSION).pkg cache/packages/hoobsd-$(HOOBSD_VERSION).pkg

hoobs-package-deploy:
	cp -r darwin cache/
	chmod -R 755 cache/darwin/scripts
	chmod -R 755 cache/darwin/
	mkdir -p cache/packages

hoobs-package-control:
	$(eval NODE_VERSION := $(shell project version node))
	$(eval CLI_VERSION := $(shell ../cli/project version))
	$(eval HOOBSD_VERSION := $(shell ../hoobsd/project version))
	$(eval GUI_VERSION := $(shell ../gui/project version))
	cat distribution | \
	sed "s/__NODE_VERSION__/$(NODE_VERSION)/g" | \
	sed "s/__CLI_VERSION__/$(CLI_VERSION)/g" | \
	sed "s/__HOOBSD_VERSION__/$(HOOBSD_VERSION)/g" | \
	sed "s/__GUI_VERSION__/$(GUI_VERSION)/g" > cache/darwin/Distribution
	chmod 755 cache/darwin/Distribution

hoobs-box-version-armhf.yaml:
	cat build.yaml | \
	sed "s/__RELEASE__/bullseye/" | \
	sed "s/__SECURITY_SUITE__/bullseye-security/" | \
	sed "s/__ARCH__/armhf/" | \
	sed "s/__LINUX_IMAGE__/linux-image-armmp/" | \
	sed "s/__DTB__/\\/usr\\/lib\\/linux-image-*-armmp\\/bcm*rpi*.dtb/" | \
	sed "s/__SERIAL_CONSOLE__/ttyAMA0,115200/" | \
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
	sed "s/__NODE_REPO__/$(shell project version nodesource)/" | \
	sed "s/__VENDOR_ID__/card/" | \
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
	time nice $(as_root) vmdb2 --verbose --output=builds/$(NAME) cache/$(subst .img,.yaml,$(BASE)) --log build.log
	rm -f cache/$(subst .img,.yaml,$(BASE))
	$(as_root) chown $(shell whoami):$(shell whoami) builds/$(NAME)

paths:
	touch build.log
	mkdir -p builds
	mkdir -p cache

clean:
	rm -fR cache
	rm -f build.log
