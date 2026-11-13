#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRED_FILE="${ROOT_DIR}/config/kernel-live.required"
CONFIG_FILE="${1:-${ROOT_DIR}/work/kernel/.config}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -f "$REQUIRED_FILE" ]] || fail "Missing kernel requirement list: $REQUIRED_FILE"
[[ -f "$CONFIG_FILE" ]] || fail "Kernel .config not found: $CONFIG_FILE"
missing=0
while IFS= read -r symbol; do
    [[ -z "$symbol" || "$symbol" == \#* ]] && continue
    if ! grep -qx "${symbol}=y" "$CONFIG_FILE"; then
        printf 'ERROR: required built-in kernel option missing or not =y: %s\n' "$symbol" >&2
        missing=1
    fi
done < "$REQUIRED_FILE"
(( missing == 0 )) || fail "Kernel configuration does not satisfy the BareLinux live ISO contract"
printf 'BareLinux live kernel configuration: OK\n'
