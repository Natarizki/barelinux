#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-kernel-config.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
while IFS= read -r symbol; do
    [[ -z "$symbol" || "$symbol" == \#* ]] && continue
    printf '%s=y\n' "$symbol"
done < "$ROOT_DIR/config/kernel-live.required" > "$tmp/good.config"
bash "$CHECK" "$tmp/good.config"
sed '/^CONFIG_OVERLAY_FS=y$/d' "$tmp/good.config" > "$tmp/bad.config"
if bash "$CHECK" "$tmp/bad.config" >"$tmp/stdout" 2>"$tmp/stderr"; then
    echo "ERROR: kernel validator accepted a missing required option" >&2
    exit 1
fi
grep -q 'CONFIG_OVERLAY_FS' "$tmp/stderr"
echo "Kernel config validator regression test: OK"
