# ![](https://raw.githubusercontent.com/hoobs-org/HOOBS/master/docs/logo.png)

HOOBS OS build utility.

This builds HOOBS images optimized for single board computers. This compiles the latest kernel, bootloader and configures system level utilities.

## Prerequisites
You will need the following to get started
- x64 machine with at least 2GB of memory and ~35GB of disk space.
- Debian 11 x64 for native building.
- superuser rights (configured sudo or root access).

> All other required packages will be installed by the build script

## Building
To build a compressed image run the following.

```text
./project build
```

The project will prepare the workspace by installing necessary dependencies and sources.

## Build Parameters
Add build parameters are prompted if not pre-defined. You can pre-define build options with the following.

```text
./compile 1.0.0 BOARD=bananapim2ultra IMG_TYPE=sdcard BRANCH=current RELEASE=bullseye NODE_REPO=node_16.x
```

Images are saved to the `output/images` directory.

## Legal
HOOBS and the HOOBS logo are registered trademarks of HOOBS Inc. Copyright (C) 2021 HOOBS Inc. All rights reserved.
