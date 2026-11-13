#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export BLF_HOME="$TMP/factory"
LFS="$ROOT/bin/lfs"

"$LFS" init TestDistro
[[ -f "$BLF_HOME/workspaces/TestDistro/distro.conf" ]]
for d in sources build rootfs output logs; do
  [[ -d "$BLF_HOME/workspaces/TestDistro/$d" ]]
done
"$LFS" TestDistro status | grep -q 'Profile: valid'
if "$LFS" init '../escape' >/dev/null 2>&1; then
  echo 'unsafe project name was accepted' >&2; exit 1
fi
if "$LFS" TestDistro build >/dev/null 2>&1; then
  echo 'unimplemented build unexpectedly succeeded' >&2; exit 1
fi
if "$LFS" TestDistro export >/dev/null 2>&1; then
  echo 'unimplemented export unexpectedly succeeded' >&2; exit 1
fi
echo 'BareLinux Factory workspace tests: OK'
