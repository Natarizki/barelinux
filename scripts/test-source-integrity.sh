#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/scripts" "$TMP_DIR/sources/manifests"
cp "$ROOT_DIR/scripts/check-sources.sh" "$TMP_DIR/scripts/"
cp "$ROOT_DIR/scripts/fetch-sources.sh" "$TMP_DIR/scripts/"
cp "$ROOT_DIR/sources/manifests/mlfs-13.1-toolchain.tsv" "$TMP_DIR/sources/manifests/"

# Reset every digest in the isolated test copy so this test is independent of
# how many production manifest entries have already been verified.
sed -i '/^[^#]/s/\t[^[:space:]]*$/\t-/' "$TMP_DIR/sources/manifests/mlfs-13.1-toolchain.tsv"

# Missing digests must be reported as blocked and the downloader must refuse.
package_count="$(grep -vcE '^(#|$)' "$TMP_DIR/sources/manifests/mlfs-13.1-toolchain.tsv")"
bash "$TMP_DIR/scripts/check-sources.sh" >"$TMP_DIR/check.out"
grep -q "INTEGRITY GATE: BLOCKED ($package_count SHA-256 digests" "$TMP_DIR/check.out"
if bash "$TMP_DIR/scripts/fetch-sources.sh" >"$TMP_DIR/fetch.out" 2>&1; then
    printf 'ERROR: fetcher accepted a manifest with missing digests\n' >&2
    exit 1
fi
grep -q 'missing or invalid SHA-256' "$TMP_DIR/fetch.out"

# A malformed digest must fail manifest validation.
sed -i 's/\t-$/\txyz/' "$TMP_DIR/sources/manifests/mlfs-13.1-toolchain.tsv"
if bash "$TMP_DIR/scripts/check-sources.sh" >"$TMP_DIR/bad.out" 2>&1; then
    printf 'ERROR: validator accepted a malformed digest\n' >&2
    exit 1
fi
grep -q 'Invalid SHA-256 digest' "$TMP_DIR/bad.out"

printf 'BareLinux source integrity gate tests: OK\n'
