#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/sources/manifests/mlfs-13.1-toolchain.tsv"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] || fail "Missing MLFS source manifest"

expected=5
count=0
missing_digests=0
while IFS=$'\t' read -r package version url digest; do
    [[ -z "${package:-}" || "$package" == \#* ]] && continue
    [[ -n "${version:-}" && -n "${url:-}" && -n "${digest:-}" ]] ||
        fail "Malformed manifest row for package: ${package:-unknown}"
    [[ "$url" == https://* ]] || fail "Non-HTTPS source URL for $package"
    case "$package" in
        binutils) [[ "$version" == "2.47" ]] || fail "Unexpected Binutils version" ;;
        gcc)      [[ "$version" == "16.2.0" ]] || fail "Unexpected GCC version" ;;
        glibc)    [[ "$version" == "2.44" ]] || fail "Unexpected glibc version" ;;
        linux)    [[ "$version" == "7.1.8" ]] || fail "Unexpected Linux version" ;;
        systemd)  [[ "$version" == "261.2" ]] || fail "Unexpected systemd version" ;;
        *) fail "Unexpected package in initial source manifest: $package" ;;
    esac
    if [[ "$digest" == "-" ]]; then
        missing_digests=$((missing_digests + 1))
    elif [[ ! "$digest" =~ ^[[:xdigit:]]{64}$ ]]; then
        fail "Invalid SHA-256 digest for $package"
    fi
    count=$((count + 1))
done < "$MANIFEST"

[[ "$count" -eq "$expected" ]] || fail "Expected $expected pinned packages, found $count"

printf 'BareLinux MLFS 13.1 source manifest: OK (%s packages)\n' "$count"
if [[ "$missing_digests" -gt 0 ]]; then
    printf 'INTEGRITY GATE: BLOCKED (%s SHA-256 digests still need verification)\n' "$missing_digests"
else
    printf 'INTEGRITY GATE: READY (all SHA-256 digests present)\n'
fi
