#!/bin/sh
# Build nlbwmon the way the OpenWrt 25.12 package (packages feed, net/nlbwmon) does:
#   CMAKE_OPTIONS += -DLIBNL_LIBRARY_TINY=ON
#   TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include/libnl-tiny
#
# On OpenWrt: run as is, libubox and libnl-tiny come from the system.
# Elsewhere: first run scripts/openwrt-deps.sh, then set DEPS_PREFIX to its
# prefix (default openwrt-deps/prefix is picked up automatically).
#
# Usage: scripts/openwrt-build.sh [build-dir]    (default: build-openwrt)
set -e

SRC=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$SRC/build-openwrt}

if [ -z "$DEPS_PREFIX" ] && [ ! -f /etc/openwrt_release ] && \
   [ -d "$SRC/openwrt-deps/prefix" ]; then
	DEPS_PREFIX=$SRC/openwrt-deps/prefix
fi

if [ -n "$DEPS_PREFIX" ]; then
	INC=$DEPS_PREFIX/include
	CFLAGS_EXTRA="-I$INC"
	LDFLAGS_EXTRA="-L$DEPS_PREFIX/lib -Wl,-rpath,$DEPS_PREFIX/lib"
	# check_function_exists(uloop_interval_set) ignores CMAKE_EXE_LINKER_FLAGS
	# under cmake_minimum_required(3.0), so point the linker at libubox here.
	LIBRARY_PATH=$DEPS_PREFIX/lib${LIBRARY_PATH:+:$LIBRARY_PATH}
	export LIBRARY_PATH
else
	INC=/usr/include
	CFLAGS_EXTRA=
	LDFLAGS_EXTRA=
fi

if [ ! -f "$INC/libnl-tiny/netlink/netlink.h" ]; then
	echo "libnl-tiny headers not found in $INC/libnl-tiny" >&2
	[ -f /etc/openwrt_release ] || echo "run scripts/openwrt-deps.sh first" >&2
	exit 1
fi

cmake -S "$SRC" -B "$B" -DLIBNL_LIBRARY_TINY=ON \
	-DCMAKE_C_FLAGS="$CFLAGS_EXTRA -I$INC/libnl-tiny" \
	-DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_EXTRA"

grep -q HAVE_ULOOP_INTERVAL "$B/CMakeFiles/nlbwmon.dir/flags.make" &&
	echo "-- uloop_interval_set: yes" || echo "-- uloop_interval_set: no"

make -C "$B" -j"$(nproc 2>/dev/null || echo 1)"
