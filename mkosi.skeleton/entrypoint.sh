#!/usr/bin/env bash

# This script sets up the container by pivoting the mount namespaces
# root filesystem, creation of terminal multiplexer, device nodes,
# procfs, etc.

set -eo pipefail

# directories
MKOSI_OUTPUT_DIR="$(realpath ./mkosi.output/)"
NEW_ROOTFS_DIR="${MKOSI_OUTPUT_DIR}/container-rootfs"
OLD_ROOTFS_NAME="oldrootfs"

function main() {
	local pid="$$"
	echo "Starting container setup (PID: $pid)"

	mount --make-rprivate /
	# Set up
	cd "${MKOSI_OUTPUT_DIR}"
	mount --bind "${NEW_ROOTFS_DIR}" "${NEW_ROOTFS_DIR}"
	cd "${NEW_ROOTFS_DIR}"
	mkdir -p "${NEW_ROOTFS_DIR}/${OLD_ROOTFS_NAME}"

	/sbin/pivot_root . "${NEW_ROOTFS_DIR}/${OLD_ROOTFS_NAME}"
	cd /

	mount -t proc proc /proc
	mount -t tmpfs -o mode=755,nosuid tmpfs /dev

	mkdir -p /dev/pts
	mount -t devpts devpts /dev/pts/ -o newinstance,ptmxmode=0666,mode=620
	ln -s /dev/pts/ptmx /dev/ptmx

	touch /dev/{null,random,zero}
	mount --bind /${OLD_ROOTFS_NAME}/dev/null /dev/null
	mount --bind /${OLD_ROOTFS_NAME}/dev/random /dev/random
	mount --bind /${OLD_ROOTFS_NAME}/dev/zero /dev/zero

	ln -s /proc/self/fd /dev/fd
	ln -s /proc/self/fd/0 /dev/stdin
	ln -s /proc/self/fd/1 /dev/stdout
	ln -s /proc/self/fd/2 /dev/stderr

	umount -l /${OLD_ROOTFS_NAME}
	rmdir /${OLD_ROOTFS_NAME}

	exec /bin/bash --norc --noprofile
}

main "$@"
