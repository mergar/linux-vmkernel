#!/bin/sh

kernel_version="linux-6.1.106"
kernel_archive_file="${kernel_version}.tar.xz"
kernel_download_url="https://cdn.kernel.org/pub/linux/kernel/v6.x/${kernel_archive_file}"

err() {
	exitval=$1
	shift
	echo "$*" 1>&2
	exit ${exitval}
}

kernel_archive()
{
	[ ! -d "${build_dir}" ] && ${MKDIR_CMD} -p ${build_dir}

	# check by size
	[ -r ${kernel_archive} ] && return 0
	${CURL_CMD} -s ${kernel_download_url} -o ${kernel_archive}
}

kernel_src_dir()
{
	kernel_archive

	# check content
	[ -r ${kernel_src_dir}/Makefile ] && return 0
	${TAR_CMD} -C ${build_dir} -xf ${kernel_archive}
}

kernel_src_dir_config()
{
	${CP_CMD} config-x86_64 ${kernel_src_dir}/.config
	echo "${MAKE_CMD} -C ${kernel_src_dir} olddefconfig"

	export ARCH="x86"
	export SRCARCH="${ARCH}"

	${MAKE_CMD} -C ${kernel_src_dir} olddefconfig
}


## MAIN
## init external CMD_MACROS (dependencies)
WHICH_CMD=$( which which 2>/dev/null )
[ -z "${WHICH_CMD}" ] && err 1 "${pgm} error: no such executable dependency/requirement: which"

TR_CMD=$( ${WHICH_CMD} tr 2>/dev/null )
[ -z "${TR_CMD}" ] && err 1 "${pgm} error: no such executable dependency/requirement: tr"

UNAME_CMD=$( which uname 2>/dev/null )
[ -z "${UNAME_CMD}" ] && err 1 "${pgm} error: no such executable dependency/requirement: uname"

# 'uname' before macros here
OS=$( ${UNAME_CMD} -s )

# generic mandatory tools/script
## bison - kernel Makefile deps
MAIN_CMD="
bison
cp
curl
make
mkdir
tar
uname
"

case "${OS}" in
	Linux)
		MAIN_CMD="${MAIN_CMD} nproc"
		;;
	FreeBSD)
		MAIN_CMD="${MAIN_CMD} sysctl"
		;;
esac

for i in ${MAIN_CMD} ${MAIN_EXTRA_CMD}; do
	mycmd=
	mycmd=$( ${WHICH_CMD} ${i} || true )            # true for 'set -e' case
	[ ! -x "${mycmd}" ] && err 1 "${pgm} error: no such executable dependency/requirement: ${i}"
	MY_CMD=$( echo ${i} | ${TR_CMD} '\-[:lower:]' '_[:upper:]' )
	MY_CMD="${MY_CMD}_CMD"
	eval "${MY_CMD}=\"${mycmd}\""
done

case "${OS}" in
	Linux)
		nproc=$( ${NPROC_CMD} )
		;;
	FreeBSD)
		nproc=$( ${SYSCTL_CMD} -qn hw.ncpu )
		;;
esac


# other defines
# Disabled because there are many undefined variables in the kernel's
# `scripts/Makefile.build` file
MAKEFLAGS="--warn-undefined-variables"
BUNDLE="/tmp/build-linux-kernel"
BUILD_DIR="./build"

build_dir="${BUILD_DIR}"
kernel_src_dir="${build_dir}/${kernel_version}"
kernel_archive="${build_dir}/${kernel_archive_file}"
vmlinux="${kernel_src_dir}/vmlinux"
rootfs="${BUNDLE}/rootfs"
init="${build_dir}/init"
virtiofsd="/usr/local/bin/virtiofsd"
virtiofsd_sock="${build_dir}/virtiofsd.sock"
qemu_mem="512m"

werrors="-Wall -Wextra -Werror"
werrors="${werrors} -Wformat=2"
werrors="${werrors} -Wno-null-pointer-arithmetic"
cflags="-static"
cflags="${cflags} ${werrors}"


kernel_src_dir
kernel_src_dir_config

# extra patch
#	cd ${kernel_src_dir) && for patch_file in ${CURDIR)/patches/*.patch; do patch -N -p0 < "$$patch_file" || true; done

${MAKE_CMD} -C ${kernel_src_dir} -j$(nproc)
#cp ${vmlinux} ${build_dir}/vmlinux
