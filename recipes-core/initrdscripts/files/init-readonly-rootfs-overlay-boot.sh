#!/bin/sh

# Enable strict shell mode
set -euo pipefail

PATH=/sbin:/bin:/usr/sbin:/usr/bin

MOUNT="/bin/mount"
UMOUNT="/bin/umount"

INIT="/sbin/init"

ROOT_MOUNT="/mnt"
ROOT_RODEVICE=""
ROOT_RWDEVICE=""
ROOT_ROMOUNT="/media/rfs/ro"
ROOT_RWMOUNT="/media/rfs/rw"
ROOT_RWRESET="no"

# Copied from initramfs-framework. The core of this script probably should be
# turned into initramfs-framework modules to reduce duplication.
udev_daemon() {
	OPTIONS="/sbin/udev/udevd /sbin/udevd /lib/udev/udevd /lib/systemd/systemd-udevd"

	for o in $OPTIONS; do
		if [ -x "$o" ]; then
			echo $o
			return 0
		fi
	done

	return 1
}

_UDEV_DAEMON=`udev_daemon`

early_setup() {
    mkdir -p /proc
    mkdir -p /sys
    $MOUNT -t proc proc /proc
    $MOUNT -t sysfs sysfs /sys
    $MOUNT -t devtmpfs none /dev

    mkdir -p /run
    mkdir -p /var/run

    $_UDEV_DAEMON --daemon
    udevadm trigger --action=add
}

read_args() {
    [ -z "${CMDLINE+x}" ] && CMDLINE=`cat /proc/cmdline`
    for arg in $CMDLINE; do
        optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
        case $arg in
            root=*)
                ROOT_RODEVICE=$optarg ;;
            rootfstype=*)
                modprobe $optarg 2> /dev/null ;;
            rootrw=*)
                ROOT_RWDEVICE=$optarg ;;
            rootrwfstype=*)
                modprobe $optarg 2> /dev/null ;;
            rootrwreset=*)
                ROOT_RWRESET=$optarg ;;
            video=*)
                video_mode=$arg ;;
            vga=*)
                vga_mode=$arg ;;
            init=*)
                INIT=$optarg ;;
            console=*)
                if [ -z "${console_params+x}" ]; then
                    console_params=$arg
                else
                    console_params="$console_params $arg"
                fi ;;
        esac
    done
}

fatal() {
    echo $1 >$CONSOLE
    echo >$CONSOLE
    exec sh
}

early_setup

[ -z "${CONSOLE+x}" ] && CONSOLE="/dev/console"

read_args

mount_and_boot() {
    mkdir -p $ROOT_MOUNT $ROOT_ROMOUNT $ROOT_RWMOUNT

    # Build mount options for read only root filesystem.
    # If no read-only device was specified via kernel commandline, use current
    # rootfs.
    if [ -z "${ROOT_RODEVICE}" ]; then
	ROOT_ROMOUNTOPTIONS="--bind,ro /"
    else
	ROOT_ROMOUNTOPTIONS="-o ro,noatime,nodiratime $ROOT_RODEVICE"
    fi

    # Mount rootfs as read-only to mount-point
    if ! $MOUNT $ROOT_ROMOUNTOPTIONS $ROOT_ROMOUNT ; then
        fatal "Could not mount read-only rootfs"
    fi

    # Build mount options for read write root filesystem.
    # If no read-write device was specified via kernel commandline, use tmpfs.
    if [ -z "${ROOT_RWDEVICE}" ]; then
	ROOT_RWMOUNTOPTIONS="-t tmpfs -o rw,noatime,mode=755 tmpfs"
    else
	ROOT_RWMOUNTOPTIONS="-o rw,noatime,mode=755 $ROOT_RWDEVICE"
    fi

    # Mount read-write filesystem into initram rootfs
    if ! $MOUNT $ROOT_RWMOUNTOPTIONS $ROOT_RWMOUNT ; then
	fatal "Could not mount read-write rootfs"
    fi

    # Reset read-write filesystem if specified
    if [ "yes" == "$ROOT_RWRESET" -a -n "${ROOT_RWMOUNT}" ]; then
	rm -rf $ROOT_RWMOUNT/*
    fi

    # Determine which unification filesystem to use
    union_fs_type=""
    if grep -w "overlay" /proc/filesystems; then
	union_fs_type="overlay"
    elif grep -w "aufs" /proc/filesystems; then
	union_fs_type="aufs"
    else
	union_fs_type=""
    fi

    # Create/Mount overlay root filesystem 
    case $union_fs_type in
	"overlay")
	    mkdir -p $ROOT_RWMOUNT/upperdir $ROOT_RWMOUNT/work
	    $MOUNT -t overlay overlay -o "lowerdir=$ROOT_ROMOUNT,upperdir=$ROOT_RWMOUNT/upperdir,workdir=$ROOT_RWMOUNT/work" $ROOT_MOUNT
	    ;;
	"aufs")
	    $MOUNT -t aufs -o "dirs=$ROOT_RWMOUNT=rw:$ROOT_ROMOUNT=ro" aufs $ROOT_MOUNT
	    ;;
	"")
	    fatal "No overlay filesystem type available"
	    ;;
    esac

    # Move read-only and read-write root filesystem into the overlay filesystem
    mkdir -p $ROOT_MOUNT/$ROOT_ROMOUNT $ROOT_MOUNT/$ROOT_RWMOUNT
    $MOUNT -n --move $ROOT_ROMOUNT ${ROOT_MOUNT}/$ROOT_ROMOUNT
    $MOUNT -n --move $ROOT_RWMOUNT ${ROOT_MOUNT}/$ROOT_RWMOUNT

    # Watches the udev event queue, and exits if all current events are handled
    udevadm settle --timeout=3
    # Kills the current udev running processes, which survived after
    # device node creation events were handled, to avoid unexpected behavior
    killall -9 "${_UDEV_DAEMON##*/}" 2>/dev/null

    # Remove /run /var/run that are created in early_setup
    rm -rf /run /var/run

    # Move the mount points of some filesystems over to
    # the corresponding directories under the real root filesystem.
    for dir in `awk '/\/dev.* \/run\/media/{print $2}' /proc/mounts`; do
        mkdir -p ${ROOT_MOUNT}/media/${dir##*/}
        $MOUNT -n --move $dir ${ROOT_MOUNT}/media/${dir##*/}
    done
    $MOUNT -n --move /proc ${ROOT_MOUNT}/proc
    $MOUNT -n --move /sys ${ROOT_MOUNT}/sys
    $MOUNT -n --move /dev ${ROOT_MOUNT}/dev

    cd $ROOT_MOUNT

    # busybox switch_root supports -c option
    exec chroot $ROOT_MOUNT $INIT ||
        fatal "Couldn't chroot, dropping to shell"
}

mount_and_boot
