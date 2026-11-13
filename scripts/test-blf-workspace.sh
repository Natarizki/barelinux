#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export BLF_HOME="$TMP/factory"
LFS="$ROOT/bin/lfs"
DEST="$TMP/stage"
make -s -C "$ROOT" install DESTDIR="$DEST" PREFIX=/usr/local
INSTALLED="$DEST/usr/local/bin/lfs"
[[ -x "$INSTALLED" ]]
"$INSTALLED" help | grep -q "lfs doctor"

bash "$LFS" help | grep -q "lfs doctor"
bash "$LFS" init TestDistro
 grep -Fxq 'BUILD_SYSTEM=mlfs' "$BLF_HOME/workspaces/TestDistro/distro.conf"
[[ -f "$BLF_HOME/workspaces/TestDistro/distro.conf" ]]
for d in sources build rootfs output logs; do
  [[ -d "$BLF_HOME/workspaces/TestDistro/$d" ]]
done
bash "$LFS" TestDistro status | grep -q 'Profile: valid'
bash "$LFS" TestDistro build plan >"$TMP/plan.out"
grep -q 'full-book' "$TMP/plan.out"
if bash "$LFS" TestDistro build full-book >"$TMP/full-book.out" 2>&1; then
  echo 'full-book unexpectedly ran without its verified ALFS checkpoint' >&2; exit 1
fi
grep -q 'requires the verified ALFS Binutils checkpoint' "$TMP/full-book.out"
if bash "$LFS" init '../escape' >/dev/null 2>&1; then
  echo 'unsafe project name was accepted' >&2; exit 1
fi
if bash "$LFS" TestDistro build unknown-stage >"$TMP/build.out" 2>&1; then
  echo 'unsupported build stage was accepted' >&2; exit 1
fi
grep -q 'unsupported build stage' "$TMP/build.out"
if bash "$LFS" TestDistro export >/dev/null 2>&1; then
  echo 'unimplemented export unexpectedly succeeded' >&2; exit 1
fi
if grep -qi 'optional OS-building environment' "$ROOT/docs/BARELINUX-FACTORY.md"; then echo 'core build system must not be documented as optional' >&2; exit 1; fi
echo 'BareLinux core LFS workspace tests: OK'
