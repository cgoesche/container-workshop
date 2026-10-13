#!/usr/bin/env bash

# This script sets up the container by pivoting the mount namespaces
# root filesystem, creation of terminal multiplexer, device nodes,
# procfs, etc.

set -eo pipefail

# UID/GID mappings
GID="$(id -g)"
START_HOST_UID=
UID_MAP_RANGE_SIZE=
START_HOST_GID=
GID_MAP_RANGE_SIZE=

# directories
ROOT_DIR="$(dirname "${BASHSOURCE[0]}")"
MKOSI_OUTPUT_DIR="${ROOT_DIR:-.}/mkosi.output"
NEW_ROOTFS_DIR="${MKOSI_OUTPUT_DIR}/container-rootfs"

# Exec
CONTAINER_ENTRYPOINT_CMD="bash --noprofile --norc ${NEW_ROOTFS_DIR}/entrypoint.sh"

function set_id_map() {
	local selection="$1"

	case "$selection" in
	uid)
		START_HOST_UID=$(awk -F':' -v user="$USER" \
			'$0 ~ user {print $2}' /etc/subuid)
		UID_MAP_RANGE_SIZE=$(awk -F':' -v user="$USER" \
			'$0 ~ user {print $3}' /etc/subuid)
		;;
	gid)
		START_HOST_GID=$(awk -F':' -v user="$USER" \
			'$0 ~ user {print $2}' /etc/subgid)
		GID_MAP_RANGE_SIZE=$(awk -F':' -v user="$USER" \
			'$0 ~ user {print $3}' /etc/subgid)
		;;
	*)
		echo "${FUNCNAME[0]}: Invalid argument '$selection'"
		return 1
		;;
	esac
	return 0
}

function do_unshare() {
	unshare --fork --kill-child --pid --net --uts --mount --mount-proc --user --map-users=0:"${UID}":1 --map-users=1:"${START_HOST_UID}":"${UID_MAP_RANGE_SIZE}" \
		--map-groups=0:"${GID}":1 --map-groups=1:"${START_HOST_GID}":"${GID_MAP_RANGE_SIZE}" \
		${CONTAINER_ENTRYPOINT_CMD}
}

function main() {
	# Set uid/gid mappings
	set_id_map "uid"
	set_id_map "gid"
	# Create new namespaces and enter these
	do_unshare
}

main "$@"
