#!/bin/sh
# Build nlbwmon the way the OpenWrt 25.12 package (packages feed, net/nlbwmon) does:
#   CMAKE_OPTIONS += -DLIBNL_LIBRARY_TINY=ON
#   TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include/libnl-tiny
#
# On OpenWrt: headers are taken from the router's build tree (see defaults
# below). Elsewhere: first run scripts/openwrt-deps.sh; its prefix
# (openwrt-deps/prefix, or DEPS_PREFIX) is picked up automatically.
#
# Overrides (environment):
#   UBOX_INC     directory containing libubox/*.h
#   NL_TINY_INC  directory containing netlink/netlink.h from libnl-tiny
#   LIB_DIR      extra directory holding libubox.so and libnl-tiny.so
#
# Usage: scripts/openwrt-build.sh [build-dir]    (default: build-openwrt)
set -e

SRC=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$SRC/build-openwrt}
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

LDFLAGS_EXTRA=
if [ -n "$LIB_DIR" ]; then
	LDFLAGS_EXTRA="-L$LIB_DIR $RPATH"
	# check_function_exists(uloop_interval_set) ignores CMAKE_EXE_LINKER_FLAGS
	# under cmake_minimum_required(3.0), so point the linker at libubox here.
	LIBRARY_PATH=$LIB_DIR${LIBRARY_PATH:+:$LIBRARY_PATH}
	export LIBRARY_PATH
fi

cmake -S "$SRC" -B "$B" -DLIBNL_LIBRARY_TINY=ON \
	-DCMAKE_C_FLAGS="-I$UBOX_INC -I$NL_TINY_INC" \
	-DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_EXTRA"

grep -q HAVE_ULOOP_INTERVAL "$B/CMakeFiles/nlbwmon.dir/flags.make" &&
	echo "-- uloop_interval_set: yes" || echo "-- uloop_interval_set: no"

make -C "$B" -j"$(nproc 2>/dev/null || echo 1)"
