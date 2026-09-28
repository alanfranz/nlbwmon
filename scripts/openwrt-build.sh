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
#   LIB_DIR      extra directory holding libubox.so and libnl-tiny.so
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

# Same probe as check_function_exists(uloop_interval_set ...): does it link?
printf 'char uloop_interval_set(void);\nint main(void) { return uloop_interval_set(); }\n' \
	> "$B/probe.c"
if $CC -o "$B/probe" "$B/probe.c" $LDFLAGS -lubox >"$B/probe.log" 2>&1; then
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
$CC -o "$B/nlbwmon" $objs $LDFLAGS -lnl-tiny -lubox -lz
echo "built $B/nlbwmon"
