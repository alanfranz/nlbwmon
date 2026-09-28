#!/bin/sh
# Build nlbwmon without CMake (none is available on OpenWrt), with the
# flags the OpenWrt 25.12 package (packages feed, net/nlbwmon) ends up
# using: CMakeLists.txt definitions, -DLIBNL_LIBRARY_TINY=ON (link with
# nl-tiny), the Release build type (-DNDEBUG) and the HAVE_ULOOP_INTERVAL
# check.
#
# On OpenWrt: headers are taken from the router's build tree (see defaults
# below). Elsewhere: first run scripts/openwrt-deps.sh; its prefix
# (openwrt-deps/prefix, or DEPS_PREFIX) is picked up automatically.
#
# Overrides (environment):
#   CC           compiler (default: gcc)
#   UBOX_INC     directory containing libubox/*.h
#   NL_TINY_INC  directory containing netlink/netlink.h from libnl-tiny
#   LIB_DIR      directory searched first for libnl-tiny, libubox and libz
#
# Usage: scripts/openwrt-build.sh [build-dir]    (default: build-openwrt)
set -e

SRC=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$SRC/build-openwrt}
CC=${CC:-gcc}
RPATH=

if [ -f /etc/openwrt_release ]; then
	: "${UBOX_INC:=/mnt/data/build/include}"
	: "${NL_TINY_INC:=/mnt/data/build/libnl-tiny/include}"
else
	: "${DEPS_PREFIX:=$SRC/openwrt-deps/prefix}"
	: "${UBOX_INC:=$DEPS_PREFIX/include}"
	: "${NL_TINY_INC:=$DEPS_PREFIX/include/libnl-tiny}"
	: "${LIB_DIR:=$DEPS_PREFIX/lib}"
	RPATH="-Wl,-rpath,$LIB_DIR"
fi

if [ ! -f "$UBOX_INC/libubox/uloop.h" ]; then
	echo "libubox headers not found in $UBOX_INC/libubox (set UBOX_INC)" >&2
	missing=1
fi
if [ ! -f "$NL_TINY_INC/netlink/netlink.h" ]; then
	echo "libnl-tiny headers not found in $NL_TINY_INC (set NL_TINY_INC)" >&2
	missing=1
fi
if [ -n "$missing" ]; then
	[ -f /etc/openwrt_release ] || echo "run scripts/openwrt-deps.sh first" >&2
	exit 1
fi

# add_definitions() from CMakeLists.txt, then include paths and -DNDEBUG
# (OpenWrt's CMAKE_C_FLAGS_RELEASE).
CFLAGS="-Os -Wall -Werror --std=gnu99 -g3 -Wmissing-declarations -D_GNU_SOURCE"
CFLAGS="$CFLAGS -I$UBOX_INC -I$NL_TINY_INC -DNDEBUG"
LDFLAGS=
[ -z "$LIB_DIR" ] || LDFLAGS="-L$LIB_DIR $RPATH"

mkdir -p "$B"

# OpenWrt runtime packages only ship versioned libraries (e.g.
# /lib/libubox.so.20260213, /usr/lib/libnl-tiny.so.1), so -lubox finds
# nothing there. Link against the library file itself instead, preferring
# the versioned file; fall back to -lNAME if none is found.
LIB_SEARCH=$LIB_DIR
[ ! -f /etc/openwrt_release ] || LIB_SEARCH="$LIB_SEARCH /usr/lib /lib"
find_lib() {
	for d in $LIB_SEARCH; do
		for f in "$d/lib$1.so."* "$d/lib$1.so"; do
			[ -f "$f" ] && { echo "$f"; return; }
		done
	done
	echo "-l$1"
}
LIB_NL=$(find_lib nl-tiny)
LIB_UBOX=$(find_lib ubox)
LIB_Z=$(find_lib z)
echo "-- libraries: $LIB_NL $LIB_UBOX $LIB_Z"

# Same probe as check_function_exists(uloop_interval_set ...): does it link?
# Check that libubox links at all first, so a missing library is an error
# rather than a silent "no".
printf 'char uloop_init(void);\nint main(void) { return uloop_init(); }\n' \
	> "$B/probe.c"
if ! $CC -o "$B/probe" "$B/probe.c" $LDFLAGS "$LIB_UBOX" >"$B/probe.log" 2>&1; then
	cat "$B/probe.log" >&2
	echo "cannot link libubox (set LIB_DIR)" >&2
	exit 1
fi
printf 'char uloop_interval_set(void);\nint main(void) { return uloop_interval_set(); }\n' \
	> "$B/probe.c"
if $CC -o "$B/probe" "$B/probe.c" $LDFLAGS "$LIB_UBOX" >"$B/probe.log" 2>&1; then
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
$CC -o "$B/nlbwmon" $objs $LDFLAGS "$LIB_NL" "$LIB_UBOX" "$LIB_Z"
echo "built $B/nlbwmon"
