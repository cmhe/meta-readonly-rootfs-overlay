#!/bin/sh

# Enable strict shell mode
set -euo pipefail

PATH=/sbin:/bin:/usr/sbin:/usr/bin

MOUNT="/bin/mount"
UMOUNT="/bin/umount"

INIT="/sbin/init"
ROOT_ROINIT="/sbin/init"

ROOT_MOUNT="/mnt"
ROOT_RODEVICE=""
ROOT_RWDEVICE=""
ROOT_ROMOUNT="/media/rfs/ro"
ROOT_RWMOUNT="/media/rfs/rw"
ROOT_RWRESET="no"

ROOT_ROFSTYPE=""
ROOT_ROMOUNTOPTIONS="bind"
ROOT_ROMOUNTOPTIONS_DEVICE="noatime,nodiratime"

ROOT_RWFSTYPE=""
ROOT_RWMOUNTOPTIONS="rw,noatime tmpfs"
ROOT_RWMOUNTOPTIONS_DEVICE="rw,noatime"

early_setup() {
	mkdir -p /proc
	mkdir -p /sys
	$MOUNT -t proc proc /proc
	$MOUNT -t sysfs sysfs /sys
	grep -w "/dev" /proc/mounts >/dev/null || $MOUNT -t devtmpfs none /dev
}

read_args() {
	[ -z "${CMDLINE+x}" ] && CMDLINE=`cat /proc/cmdline`
	for arg in $CMDLINE; do
		# Set optarg to option parameter, and '' if no parameter was
		# given
		optarg=`expr "x$arg" : 'x[^=]*=\(.*\)' || echo ''`
		case $arg in
			root=*)
				ROOT_RODEVICE=$optarg ;;
			rootfstype=*)
				ROOT_ROFSTYPE="$optarg"
				modprobe $optarg 2> /dev/null || \
					log "Could not load $optarg module";;
			rootinit=*)
				ROOT_ROINIT=$optarg ;;
			rootoptions=*)
				ROOT_ROMOUNTOPTIONS_DEVICE="$optarg" ;;
			rootrw=*)
				ROOT_RWDEVICE=$optarg ;;
			rootrwfstype=*)
				ROOT_RWFSTYPE="$optarg"
				modprobe $optarg 2> /dev/null || \
					log "Could not load $optarg module";;
			rootrwreset=*)
				ROOT_RWRESET=$optarg ;;
			rootrwoptions=*)
				ROOT_RWMOUNTOPTIONS_DEVICE="$optarg" ;;
			init=*)
			INIT=$optarg ;;
		esac
	done
}

fatal() {
	echo "rorootfs-overlay: $1" >$CONSOLE
	echo >$CONSOLE
	exec sh
}

log() {
	echo "rorootfs-overlay: $1" >$CONSOLE
}

early_setup

[ -z "${CONSOLE+x}" ] && CONSOLE="/dev/console"

read_args

mount_and_boot() {
	mkdir -p $ROOT_MOUNT $ROOT_ROMOUNT $ROOT_RWMOUNT

	# Build mount options for read only root file system.
	# If no read-only device was specified via kernel command line, use
	# current root file system via bind mount.
	ROOT_ROMOUNTPARAMS_BIND="-o ${ROOT_ROMOUNTOPTIONS} /"
	if [ -n "${ROOT_RODEVICE}" ]; then
		ROOT_ROMOUNTPARAMS="-o ${ROOT_ROMOUNTOPTIONS_DEVICE} $ROOT_RODEVICE"
		if [ -n "${ROOT_ROFSTYPE}" ]; then
			ROOT_ROMOUNTPARAMS="-t $ROOT_ROFSTYPE $ROOT_ROMOUNTPARAMS"
		fi
	else
		ROOT_ROMOUNTPARAMS="$ROOT_ROMOUNTPARAMS_BIND"
	fi

	# Mount root file system to new mount-point, if unsuccessful, try bind
	# mounting current root file system.
	if ! $MOUNT $ROOT_ROMOUNTPARAMS "$ROOT_ROMOUNT" 2>/dev/null && \
		[ "x$ROOT_ROMOUNTPARAMS_BIND" == "x$ROOT_ROMOUNTPARAMS" ] || \
		log "Could not mount $ROOT_RODEVICE, bind mounting..." && \
		! $MOUNT $ROOT_ROMOUNTPARAMS_BIND "$ROOT_ROMOUNT"; then
		fatal "Could not mount read-only rootfs"
	fi

	# Remounting root file system as read only.
	if ! $MOUNT -o remount,ro "$ROOT_ROMOUNT"; then
		fatal "Could not remount read-only rootfs as read only"
	fi

	# If future init is the same as current file, use $ROOT_ROINIT
	# Tries to avoid loop to infinity if init is set to current file via
	# kernel command line
	if cmp -s "$0" "$INIT"; then
		INIT="$ROOT_ROINIT"
	fi

	# Build mount options for read write root file system.
	# If a read-write device was specified via kernel command line, use
	# it, otherwise default to tmpfs.
	if [ -n "${ROOT_RWDEVICE}" ]; then
		
		ROOT_RWMOUNTPARAMS="-o $ROOT_RWMOUNTOPTIONS_DEVICE $ROOT_RWDEVICE"
		if [ -n "${ROOT_RWFSTYPE}" ]; then
			ROOT_RWMOUNTPARAMS="-t $ROOT_RWFSTYPE $ROOT_RWMOUNTPARAMS"
		fi
	else
		ROOT_RWMOUNTPARAMS="-t tmpfs -o $ROOT_RWMOUNTOPTIONS"
	fi

	# Mount read-write file system into initram root file system
	if ! $MOUNT $ROOT_RWMOUNTPARAMS $ROOT_RWMOUNT ; then
		fatal "Could not mount read-write rootfs"
	fi

	# Reset read-write file system if specified
	if [ "yes" == "$ROOT_RWRESET" -a -n "${ROOT_RWMOUNT}" ]; then
		rm -rf $ROOT_RWMOUNT/*
	fi

	# Determine which unification file system to use
	union_fs_type=""
	if grep -w "overlay" /proc/filesystems >/dev/null; then
		union_fs_type="overlay"
	elif grep -w "aufs" /proc/filesystems >/dev/null; then
		union_fs_type="aufs"
	else
		union_fs_type=""
	fi

	# Create/Mount overlay root file system
	case $union_fs_type in
		"overlay")
			mkdir -p $ROOT_RWMOUNT/upperdir $ROOT_RWMOUNT/work
			$MOUNT -t overlay overlay \
				-o "$(printf "%s%s%s" \
					"lowerdir=$ROOT_ROMOUNT," \
					"upperdir=$ROOT_RWMOUNT/upperdir," \
					"workdir=$ROOT_RWMOUNT/work")" \
				$ROOT_MOUNT
			;;
		"aufs")
			$MOUNT -t aufs i\
				-o "dirs=$ROOT_RWMOUNT=rw:$ROOT_ROMOUNT=ro" \
				aufs $ROOT_MOUNT
			;;
		"")
			fatal "No overlay filesystem type available"
			;;
	esac

	# Move read-only and read-write root file system into the overlay
	# file system
	mkdir -p $ROOT_MOUNT/$ROOT_ROMOUNT $ROOT_MOUNT/$ROOT_RWMOUNT
	$MOUNT -n --move $ROOT_ROMOUNT ${ROOT_MOUNT}/$ROOT_ROMOUNT
	$MOUNT -n --move $ROOT_RWMOUNT ${ROOT_MOUNT}/$ROOT_RWMOUNT

	$MOUNT -n --move /proc ${ROOT_MOUNT}/proc
	$MOUNT -n --move /sys ${ROOT_MOUNT}/sys
	$MOUNT -n --move /dev ${ROOT_MOUNT}/dev

	cd $ROOT_MOUNT

	# switch to actual init in the overlay root file system
	exec chroot $ROOT_MOUNT $INIT ||
		fatal "Couldn't chroot, dropping to shell"
}

mount_and_boot
