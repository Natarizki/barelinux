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
while IFS=$'\t' read -r package version url; do
    [[ -z "${package:-}" || "$package" == \#* ]] && continue
    [[ -n "${version:-}" && -n "${url:-}" ]] ||
        fail "Malformed manifest row for package: ${package:-unknown}"
    [[ "$url" == https://* ]] ||
        fail "Non-HTTPS source URL for $package"
    case "$package" in
        binutils) [[ "$version" == "2.47" ]] || fail "Unexpected Binutils version" ;;
        gcc)      [[ "$version" == "16.2.0" ]] || fail "Unexpected GCC version" ;;
        glibc)    [[ "$version" == "2.44" ]] || fail "Unexpected glibc version" ;;
        linux)    [[ "$version" == "7.1.8" ]] || fail "Unexpected Linux version" ;;
        systemd)  [[ "$version" == "261.2" ]] || fail "Unexpected systemd version" ;;
        *) fail "Unexpected package in initial source manifest: $package" ;;
    esac
    count=$((count + 1))
done < "$MANIFEST"

[[ "$count" -eq "$expected" ]] ||
    fail "Expected $expected pinned packages, found $count"

printf 'BareLinux MLFS 13.1 source manifest: OK (%s packages)\n' "$count"
printf 'NOTE: checksum verification is not enabled yet; builds must not download these sources.\n'
