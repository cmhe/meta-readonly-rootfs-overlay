# meta-readonly-rootfs-overlay

This yocto layer provides the necessary scripts and configurations to setup a
writable root file system overlay on top of a read-only root filesystem.

## Why does this exists?

Having a read-only root file system is useful for many scenarios:

- Have a unmodifiable factory root file system
- Seperate user specific changes from system configuration
- Allow factory reset, by deleting the user specfic changes
- Have a fallback image in case the user specific changes made the root file
system no longer bootable.

Because some data on the root file system changes on first boot or while the
system is running, just mounting the complete root file system as read-only
breaks many applications. There are different solutions to this problem:

- Symlinking/Bind mounting files and directories that could potentially change
while the system is running to a writable partition
- Instead of having a read-only root files system, mounting a writable overlay
root file system, that uses a read-only file system as its base and writes
changed data to another writable partition.

To implement the first solution, the developer needs to analyse which file
needs to change and then create symlinks for them. When doing factory reset,
the developer "empties" every file that is linked, to avoid dangling
symlinks/binds. While this is more work on the developer side, it might
increase the security, because only files that are symlinked/bind-mounted can
be changed.

This meta-layer provides the second solution.

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

### Example using initrd:

```
root=/dev/sda1 rootrw=/dev/sda2
```

This cmd line start `/sbin/init` with the `/dev/sda1` partition as the read-only
rootfs and the `/dev/sda2` partition as the read-write persistend state.

```
root=/dev/sda1 rootrw=/dev/sda2 init=/bin/sh
```

The same as before but it now starts `/bin/sh` instead of `/sbin/init`.

### Example without initrd:

```
root=/dev/sda1 rootrw=/dev/sda2 init=/init
```

This cmd line starts `/sbin/init` with `/dev/sda1` partition as the read-only
rootfs and the `/dev/sda2` partition as the read-write persistend state. When
using this init script without an initrd, `init=/init` has to be set.

```
root=/dev/sda1 rootrw=/dev/sda2 init=/init rootinit=/bin/sh
```

The same as before but it now starts `/bin/sh` instead of `/sbin/init`

### Details

`root=` specifies the read-only root filesystem device. If this is not
specified, the current rootfs is used.

`rootfstype=` if support for the-read only filesystem is not build into the
kernel, you can specifiy the required module name here.

`rootinit=` if the `init` parameter was used to specify this init script,
`rootinit` can be used to overwrite the default (`/sbin/init`).

`rootrw=` specifies the read-write filesystem device. If this is not
specified, `tmpfs` is used.

`rootrwfstype=` if support for the read-write filesystem is not build into the
kernel, you can specifiy the required module name here.

`rootrwreset=` set to `yes` if you want to delete all the files in the
read-write filesystem prior to building the overlay root files system.
