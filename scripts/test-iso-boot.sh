#!/usr/bin/env bash
set -euo pipefail

ISO="${1:-out/barelinux-x86_64.iso}"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS.fd}"
TIME_LIMIT="${BARELINUX_QEMU_TIMEOUT:-120s}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
for cmd in qemu-system-x86_64 timeout grep cp mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
done
[[ -s "$ISO" ]] || fail "ISO not found: $ISO"
[[ -s "$OVMF_CODE" ]] || fail "OVMF_CODE firmware not found: $OVMF_CODE"
[[ -s "$OVMF_VARS" ]] || fail "OVMF_VARS template not found: $OVMF_VARS"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
run_test() {
    local mode="$1"
    shift
    local log="$tmp/$mode.log"
    set +e
    timeout "$TIME_LIMIT" qemu-system-x86_64 -machine accel=tcg -cpu max -m 2048 -smp 2 \
        -cdrom "$ISO" -boot d -display none -serial stdio -monitor none \
        -no-reboot -no-shutdown "$@" >"$log" 2>&1
    local rc=$?
    set -e
    if ! grep -Eq 'Reached target (Multi-User System|Graphical Interface)|BareLinux: SYSTEMD_BOOT_OK' "$log"; then
        cat "$log" >&2
        fail "$mode boot did not reach the systemd multi-user target (qemu exit: $rc)"
    fi
    printf '%s boot reached systemd multi-user target.\n' "$mode"
}
run_test BIOS
cp "$OVMF_VARS" "$tmp/OVMF_VARS.fd"
run_test UEFI \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$tmp/OVMF_VARS.fd"
