# from https://wiki.gentoo.org/wiki/Custom_Initramfs/Examples

INITRAMFS_DIR="/usr/src/initramfs"

# needed to make parsing outputs more reliable
export LC_ALL=C

echo_debug() {
	# remove the next line to enable debug output
	return
	echo -ne "\033[01;32m" # green
	echo $@ >&2
	echo -ne "\033[00m"
}

echo_warn() {
	echo -ne "\033[01;33m" # yellow
	echo $@ >&2
	echo -ne "\033[00m"
}

echo_error() {
	echo -ne "\033[01;31m" # red
	echo $@ >&2
	echo -ne "\033[00m"
	exit 1
}

copy() {
	# Usage:
	# copy &lt;source path&gt; [&lt;destination path&gt;]
	# &lt;source path&gt; can be a file, symlink, device node, ...
	# &lt;destination path&gt; can be a directory or file, relative to $INITRAMFS_DIR
	#  if &lt;destination path&gt; is omitted, the base directory from &lt;source path&gt; is used

	echo_debug "copy $@"

	src=$1
	dst=$2
	if [ -z "${dst}" ]; then
		# $dst is not given, use the base directory of $src
		dst="$(dirname -- "$1")/"
	fi

	# check if the file will be copied into the initrd root
	# realpath will remove trailing / that are needed later on...
	add_slash=false
	if [ "${dst%/}" != "${dst}" ]; then
		# $dst has a trailing /
		add_slash=true
	fi
	dst="$(realpath --canonicalize-missing -- ${INITRAMFS_DIR}/${dst})"
	${add_slash} && dst="${dst}/"

	# check if $src exists
	if [ ! -e "${src}" ]; then
		echo_warn "Cannot copy '${src}'. File not found. Skipping."
		return
	fi
	# check if the destination is really inside ${INITRAMFS_DIR}
	if [ "${dst}" = "${dst##${INITRAMFS_DIR}}" ]; then
		echo_warn "Invalid destination $2 for $1. Skipping."
		return
	fi

	# check if the destination is a file or a directory and 
	# if it already exists
	if [ -e "${dst}" ]; then
		# $dst exists, but that's ok if it is a directory
		if [ -d "${dst}" ]; then
			# $dst is an existing directory
			dst_dir="${dst}"
			if [ -e "${dst_dir}/$(basename -- "${src}")" ]; then
				# the file exists in the destination directory, silently skip it
				echo_debug "Target file exists, skiping."
				return
			fi
		else
			# $dst exists, but it's not a directory, silently skip it
			echo_debug "Target file exists, skiping."
			return
		fi
	else
		if [ "${dst%/}" != "${dst}" ]; then
			# $dst ends in a /, so it must be a directory
			dst_dir="$dst"
		else
			# probably a file
			dst_dir="$(dirname -- "${dst}")"
		fi
		# make sure that the destination directory exists
		mkdir -p -- "${dst_dir}"
	fi

	# copy the file
	echo_debug "cp -a ${src} ${dst}"
	cp -a "${src}" "${dst}" || echo_error "Error: Could not copy ${src}"
	if [ -h "${src}" ]; then
		# $src is a symlink, follow it
		link_target="$(readlink -- "${src}")"
		if [ "${link_target#/}" = "${link_target}" ]; then
			# relative link, make it absolute
			link_target="$(dirname -- "${src}")/${link_target}"
		fi
		# get the canonical path, i.e. without any ../ and such stuff
		link_target="$(realpath --no-symlink -- "${link_target}")"
		echo_debug "Following symlink to $link_target"
		copy "${link_target}"
	elif [ -f "${src}" ]; then
		mime_type="$(file --brief --mime-type -- "${src}")"
		if [ "${mime_type}" = "application/x-sharedlib" ] || \
		   [ "${mime_type}" = "application/x-executable" ] || \
		   [ "${mime_type}" = "application/x-pie-executable" ]; then
			# $src may be dynamically linked, copy the dependencies
			# lddtree -l prints $src as the first line, skip it
			lddtree -l "${src}" | tail -n +2 | while read file; do
				echo_debug "Recursing to dependency $file"
				copy "${file}"
			done
		fi
	fi
}

rm -rf "${INITRAMFS_DIR}"

mkdir -p -- "${INITRAMFS_DIR}/"{bin,dev,etc,lib,lib64,mnt/root,proc,root,run/cryptsetup,sbin,sys}
copy /dev/console /dev/
copy /dev/null /dev/

copy /bin/busybox /bin/
# add symlinks
for applet in $(/bin/busybox --list | grep -Fxv busybox); do
	if [ -e "/sbin/${applet}" ]; then
		ln -s /bin/busybox "${INITRAMFS_DIR}/sbin/${applet}"
	else
		ln -s /bin/busybox "${INITRAMFS_DIR}/bin/${applet}"
	fi
done

# add cryptsetup
copy /sbin/cryptsetup /sbin/

###############################################################################
# CUSTOMIZE HERE!
###############################################################################

# copy the init script
cp /root/init "${INITRAMFS_DIR}/init"
chmod +x "${INITRAMFS_DIR}/init"

# copy the firmwares
cp -r /lib/firmware/intel-ucode "${INITRAMFS_DIR}/lib/firmware/"
cp /lib/firmware/iwlwifi-9000-pu-b0-jf-b0-46.ucode "${INITRAMFS_DIR}/lib/firmware/"
cp /lib/firmware/regulatory.db{,.p7s} "${INITRAMFS_DIR}/lib/firmware/"
mkdir "${INITRAMFS_DIR}/lib/firmware/i915"
# TODO: GuC HuC copy?
cp /lib/firmware/i915/kbl_dmc_ver1_04.bin "${INITRAMFS_DIR}/lib/firmware/i915"

# now build the image file
pushd "${INITRAMFS_DIR}"
#find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.img
find . -print0 | cpio --null -ov --format=newc > ../initramfs.cpio
# set restrictive permissions, it contains a decryption key
chmod 400 ../initramfs.cpio
popd
