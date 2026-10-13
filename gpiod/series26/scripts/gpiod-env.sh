#!/bin/bash
# command-chain for every gpiod app: choose the libgpiod the tools run against.
#   1. the host library on classic Ubuntu (plug host-libgpiod): test what the system ships
#   2. the libgpiod content snap (plug libgpiod): Ubuntu Core
# The snap ships no libgpiod of its own. GPIOD_SONAME comes from snapcraft.yaml.
set -eu

hostfs="${HOSTFS:-/var/lib/snapd/hostfs}"
case "${SNAP_ARCH:-}" in
  amd64) triplet=x86_64-linux-gnu ;;
  arm64) triplet=aarch64-linux-gnu ;;
  armhf) triplet=arm-linux-gnueabihf ;;
  riscv64) triplet=riscv64-linux-gnu ;;
  ppc64el) triplet=powerpc64le-linux-gnu ;;
  s390x) triplet=s390x-linux-gnu ;;
  *) triplet=unknown ;;
esac

host_lib="$hostfs/usr/lib/$triplet/$GPIOD_SONAME"
copy_dir="$SNAP_USER_DATA/host-lib"
tmp="$copy_dir/.$GPIOD_SONAME.$$"
libdir=""

# The loader cannot use the library in place on hostfs under strict confinement: copy it.
# Copy to a temp file and rename it over the old copy, never cp onto it: a tool that is
# already running has the old copy mapped and would crash if the file were rewritten.
if mkdir -p "$copy_dir" 2>/dev/null && cp -L "$host_lib" "$tmp" 2>/dev/null &&
  mv -f "$tmp" "$copy_dir/$GPIOD_SONAME"; then
  libdir="$copy_dir"
fi
rm -f "$tmp"
if [ -z "$libdir" ] && [ -e "$SNAP/libgpiod/$GPIOD_SONAME" ]; then
  libdir="$SNAP/libgpiod"
fi
if [ -z "$libdir" ]; then
  cat >&2 <<EOF
$SNAP_INSTANCE_NAME: $GPIOD_SONAME not found.
  Ubuntu Core: install the libgpiod snap of the same series, then
    sudo snap connect $SNAP_INSTANCE_NAME:libgpiod libgpiod:libgpiod
  Classic: install the library deb, then
    sudo snap connect $SNAP_INSTANCE_NAME:host-libgpiod
  See INSTALL-MATRIX.md: https://github.com/canonical/universe-tool-snaps
EOF
  exit 1
fi

export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$@"
