# ![](https://raw.githubusercontent.com/hoobs-org/HOOBS/master/docs/logo.png)

HOOBS OS build utility.

## Prerequisites
This build tool requires some packages to be installed. This also only works on a Debian system updated to the latest version.

```
sudo apt install vmdb2 dosfstools qemu-utils qemu-user-static debootstrap binfmt-support time kpartx bmap-tools
```

And just incase you forget sudo when building.

```
sudo apt install fakemachine
```

## Building
To build a compressed image run the following from the project root.

```sh
sudo make blackwing.img.xz
```

## Legal
HOOBS and the HOOBS logo are registered trademarks of HOOBS Inc. Copyright (C) 2021 HOOBS Inc. All rights reserved.
