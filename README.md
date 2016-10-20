This README.md file contains information on the contents of the
readonly-rootfs-overlay layer.

Please see the corresponding sections below for details.

# Dependencies

This layer depends on:

```
  URI: git://git.openembedded.org/bitbake
  branch: krogoth
```

```
  URI: git://git.openembedded.org/openembedded-core
  layers: meta
  branch: krogoth
```

# Patches

Please submit any patches against the readonly-rootfs-overlay layer via pull
request.


# Table of Contents

1. [Adding the readonly-rootfs-overlay layer to your build](#adding-the-readonly-rootfs-overlay-layer-to-your-build)
1. [Read-only root filesystem](#read-only-root-filesystem)
1. [Kernel command line parameters](#kernel-command-line-parameters)


## Adding the readonly-rootfs-overlay layer to your build

In order to use this layer, you need to make the build system aware of
it.

Assuming the readonly-rootfs-overlay layer exists at the top-level of your
yocto build tree, you can add it to the build system by adding the
location of the readonly-rootfs-overlay layer to bblayers.conf, along with any
other layers needed. e.g.:

```
  BBLAYERS ?= " \
    /path/to/yocto/meta \
    /path/to/yocto/meta-poky \
    /path/to/yocto/meta-yocto-bsp \
    /path/to/yocto/meta-readonly-rootfs-overlay \
    "
```

## Read-only root filesystem

If you use this layer you do *not* need to set `read-only-rootfs` in the
`IMAGE_FEATURES` or `EXTRA_IMAGE_FEATURES` variable.

## Kernel command line parameters

Example:

```
root=/dev/sda1 rootfstype=ext4 rootrw=/dev/sda2 rootrwfstype=btrfs
```

`root=` specifies the read-only root filesystem device. If this is not
specified, the current rootfs is used.

`rootfstype=` if support for the-read only filesystem is not build into the
kernel, you can specifiy the required module name here.

`rootrw=` specifies the read-write filesystem device. If this is not
specified, `tmpfs` is used.

`rootrwfstype=` if support for the read-write filesystem is not build into the
kernel, you can specifiy the required module name here.

`rootrwreset=` set to `yes` if you want to delete all the files in the
read-write filesystem prior to building the overlay root files system.
