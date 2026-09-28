#!/bin/sh
# Build nlbwmon the way the OpenWrt 25.12 package (packages feed, net/nlbwmon)
# does, without CMake (none is available on OpenWrt). Works the same on
# OpenWrt and on other Linux hosts.
#
# The libraries installed on OpenWrt are stripped of section headers and
# cannot be linked against, so libubox and libnl-tiny are fetched at the
# revisions shipped in OpenWrt 25.12.5 and built into openwrt-deps/ with the
# same sonames. The resulting binary loads the system libraries at run time
# on OpenWrt, and the ones in openwrt-deps/lib (via rpath) elsewhere.
#
# Environment:
#   CC        compiler (default: gcc)
#   DEPS_DIR  where dependencies are fetched and built (default: openwrt-deps)
#
# Usage: scripts/openwrt-build.sh [build-dir]    (default: build-openwrt)
set -e

# PKG_SOURCE_VERSION and ABI versions from package/libs/*/Makefile at v25.12.5.
LIBUBOX_REV=7dd127841e82eb1cfb61185da37dde7b9bd9ba6d	# 2026-06-19
LIBUBOX_ABI=20260213
LIBNL_TINY_REV=40493a655d8caa2ccf5206dde1e733abe2920432	# 2025-12-02
LIBNL_TINY_ABI=1

SRC=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$SRC/build-openwrt}
D=${DEPS_DIR:-$SRC/openwrt-deps}
CC=${CC:-gcc}

OPENWRT=
[ ! -f /etc/openwrt_release ] || OPENWRT=1

# On OpenWrt, take the soname from the installed library, and warn if it is
# not the version the sources below correspond to.
soname() { # name default-abi
	for f in /lib/lib$1.so.* /usr/lib/lib$1.so.*; do
		if [ -n "$OPENWRT" ] && [ -e "$f" ]; then
			echo "${f##*/}"
			[ "${f##*/}" = "lib$1.so.$2" ] ||
				echo "warning: system ${f##*/} differs from lib$1.so.$2 built here" >&2
			return
		fi
	done
	echo "lib$1.so.$2"
}

fetch() { # url dir rev
	if [ ! -d "$D/$2/.git" ]; then
		git clone -q "$1" "$D/$2"
	fi
	if [ "$(git -C "$D/$2" rev-parse HEAD)" != "$3" ]; then
		git -C "$D/$2" fetch -q origin
		git -C "$D/$2" checkout -q "$3"
	fi
}

build_lib() { # dir soname rev cflags sources...
	dir=$1 so=$2 rev=$3 cflags=$4
	shift 4
	stamp="$rev $so $CC"
	[ "$(cat "$D/lib/$so.stamp" 2>/dev/null)" != "$stamp" ] || return 0
	echo "LIB $so"
	srcs=
	for s in "$@"; do srcs="$srcs $D/$dir/$s"; done
	$CC -Os -std=gnu99 -fPIC -shared $cflags -Wl,-soname,"$so" \
		-o "$D/lib/$so" $srcs
	echo "$stamp" > "$D/lib/$so.stamp"
}

mkdir -p "$D/lib" "$B"

UBOX_SO=$(soname ubox $LIBUBOX_ABI)
NL_SO=$(soname nl-tiny $LIBNL_TINY_ABI)

fetch https://git.openwrt.org/project/libubox.git libubox $LIBUBOX_REV
fetch https://git.openwrt.org/project/libnl-tiny.git libnl-tiny $LIBNL_TINY_REV

# SOURCES from the respective CMakeLists.txt.
build_lib libubox "$UBOX_SO" $LIBUBOX_REV "-Wno-unused-parameter" \
	avl.c avl-cmp.c blob.c blobmsg.c uloop.c usock.c ustream.c ustream-fd.c \
	vlist.c utils.c safe_list.c runqueue.c md5.c kvlist.c ulog.c base64.c \
	udebug.c udebug-remote.c
build_lib libnl-tiny "$NL_SO" $LIBNL_TINY_REV "-I$D/libnl-tiny/include" \
	attr.c cache.c cache_mngt.c error.c genl.c genl_ctrl.c genl_family.c \
	genl_mngt.c handlers.c msg.c nl.c object.c socket.c unl.c

# zlib: the stripped system libz.so cannot be linked on OpenWrt; fall back
# to a static libz.a.
printf 'char zlibVersion(void);\nint main(void) { return zlibVersion(); }\n' \
	> "$B/probe.c"
if $CC -o "$B/probe" "$B/probe.c" -lz >"$B/probe.log" 2>&1; then
	LIB_Z=-lz
else
	LIB_Z=
	for f in /usr/lib/libz.a /usr/lib64/libz.a /lib/libz.a; do
		[ -f "$f" ] && { LIB_Z=$f; break; }
	done
	if [ -z "$LIB_Z" ]; then
		cat "$B/probe.log" >&2
		echo "cannot link zlib and no libz.a found" >&2
		exit 1
	fi
fi

LIBS="$D/lib/$NL_SO $D/lib/$UBOX_SO $LIB_Z"
LDFLAGS=
[ -n "$OPENWRT" ] || LDFLAGS="-Wl,-rpath,$D/lib"
echo "-- libraries: $LIBS"

# add_definitions() from CMakeLists.txt, the libnl-tiny include path from the
# package Makefile and -DNDEBUG (OpenWrt's CMAKE_C_FLAGS_RELEASE). $D contains
# the libubox checkout, so <libubox/...> resolves to it.
CFLAGS="-Os -Wall -Werror --std=gnu99 -g3 -Wmissing-declarations -D_GNU_SOURCE"
CFLAGS="$CFLAGS -I$D -I$D/libnl-tiny/include -DNDEBUG"

# Same probe as check_function_exists(uloop_interval_set ...): does it link?
printf 'char uloop_interval_set(void);\nint main(void) { return uloop_interval_set(); }\n' \
	> "$B/probe.c"
if $CC -o "$B/probe" "$B/probe.c" "$D/lib/$UBOX_SO" >"$B/probe.log" 2>&1; then
	CFLAGS="$CFLAGS -DHAVE_ULOOP_INTERVAL"
	echo "-- uloop_interval_set: yes"
else
	echo "-- uloop_interval_set: no (see $B/probe.log)"
fi
rm -f "$B/probe" "$B/probe.c"

# Every top-level .c file is a source, as in the SOURCES list of CMakeLists.txt.
objs=
for c in "$SRC"/*.c; do
	o=$B/$(basename "$c" .c).o
	echo "CC $(basename "$c")"
	$CC $CFLAGS -c -o "$o" "$c"
	objs="$objs $o"
done

echo "LD nlbwmon"
$CC -o "$B/nlbwmon" $objs $LDFLAGS $LIBS
echo "built $B/nlbwmon"
