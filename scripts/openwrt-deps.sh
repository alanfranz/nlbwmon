#!/bin/sh
# Build the libubox and libnl-tiny versions shipped with OpenWrt 25.12.5
# into openwrt-deps/prefix, so scripts/openwrt-build.sh can check changes
# against them on a non-OpenWrt host. Not needed on OpenWrt itself.
#
# Versions are PKG_SOURCE_VERSION from package/libs/*/Makefile at v25.12.5.
set -e

LIBUBOX_REV=7dd127841e82eb1cfb61185da37dde7b9bd9ba6d	# 2026-06-19
LIBNL_TINY_REV=40493a655d8caa2ccf5206dde1e733abe2920432	# 2025-12-02
JSONC_TAG=json-c-0.18-20240915	# only required by libubox's CMakeLists

SRC=$(cd "$(dirname "$0")/.." && pwd)
D=${1:-$SRC/openwrt-deps}
P=$D/prefix
J=$(nproc 2>/dev/null || echo 1)

mkdir -p "$D"

fetch() { # url dir rev
	[ -d "$D/$2" ] || git clone -q "$1" "$D/$2"
	git -C "$D/$2" fetch -q --tags origin
	git -C "$D/$2" checkout -q "$3"
}

fetch https://github.com/json-c/json-c.git json-c "$JSONC_TAG"
cmake -S "$D/json-c" -B "$D/json-c/build" -DCMAKE_INSTALL_PREFIX="$P" \
	-DBUILD_TESTING=OFF -DBUILD_APPS=OFF
make -C "$D/json-c/build" -j"$J" install

fetch https://git.openwrt.org/project/libubox.git libubox "$LIBUBOX_REV"
PKG_CONFIG_PATH=$P/lib/pkgconfig cmake -S "$D/libubox" -B "$D/libubox/build" \
	-DCMAKE_INSTALL_PREFIX="$P" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF
make -C "$D/libubox/build" -j"$J" install

fetch https://git.openwrt.org/project/libnl-tiny.git libnl-tiny "$LIBNL_TINY_REV"
cmake -S "$D/libnl-tiny" -B "$D/libnl-tiny/build" -DCMAKE_INSTALL_PREFIX="$P"
make -C "$D/libnl-tiny/build" -j"$J" install

echo "OpenWrt 25.12.5 deps installed in $P"
