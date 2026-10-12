#!/bin/bash
# Checks gpiod-env.sh library selection with fake snap and host trees.
# Run as a normal user (root ignores the chmod 000 case): bash gpiod/tests/test-gpiod-env.sh
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
env_sh="${ENV_SH:-$here/series24/scripts/gpiod-env.sh}"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }

for copy in "$here"/series*/scripts/gpiod-env.sh; do
  cmp -s "$copy" "$here/series24/scripts/gpiod-env.sh" || { echo "FAIL $copy differs from the series24 copy"; fail=1; }
done

t="$(mktemp -d)"; trap 'chmod -R u+rw "$t"; rm -rf "$t"' EXIT
export SNAP="$t/snap" SNAP_USER_DATA="$t/user" SNAP_ARCH=amd64 SNAP_INSTANCE_NAME=gpiod \
       GPIOD_SONAME=libgpiod.so.2 HOSTFS="$t/hostfs" LD_LIBRARY_PATH=/keep
host="$HOSTFS/usr/lib/x86_64-linux-gnu"
run() { bash "$env_sh" sh -c 'echo "$LD_LIBRARY_PATH"' 2>"$t/err"; }

mkdir -p "$SNAP/libgpiod" "$host"
check "neither: exit 1" "$(run >/dev/null; echo $?)" "1"
grep -q "snap connect gpiod:libgpiod libgpiod:libgpiod" "$t/err"; check "neither: connect hint" "$?" "0"

echo content > "$SNAP/libgpiod/libgpiod.so.2"
check "content only" "$(run)" "$SNAP/libgpiod:/keep"

echo host > "$host/libgpiod.so.2"
check "host wins" "$(run)" "$SNAP_USER_DATA/host-lib:/keep"
check "host copied" "$(cat "$SNAP_USER_DATA/host-lib/libgpiod.so.2")" "host"

rm "$host/libgpiod.so.2" # the copy from the run above is still there
check "stale copy ignored" "$(run)" "$SNAP/libgpiod:/keep"

echo host > "$host/libgpiod.so.2"; chmod 000 "$host/libgpiod.so.2"
check "host lib unreadable -> content" "$(run)" "$SNAP/libgpiod:/keep"

exit $fail
