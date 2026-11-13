#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/build-iso.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
for cmd in mksquashfs cpio gzip xorriso sha256sum file readelf grep find install ln rm chmod; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$cmd"
    chmod +x "$tmp/bin/$cmd"
done
if PATH="$tmp/bin:/usr/bin:/bin" BARELINUX_WORK_DIR="$tmp/work" BARELINUX_OUTPUT_DIR="$tmp/out" bash "$SCRIPT" >"$tmp/stdout" 2>"$tmp/stderr"; then
    echo "ERROR: ISO builder unexpectedly accepted an empty workspace" >&2
    exit 1
fi
if ! grep -q 'Root filesystem directory not found' "$tmp/stderr"; then
    cat "$tmp/stderr" >&2
    echo "ERROR: ISO builder failed for an unexpected reason" >&2
    exit 1
fi
echo "ISO builder fail-closed preflight: OK"
