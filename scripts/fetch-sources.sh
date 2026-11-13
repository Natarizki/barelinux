#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/sources/manifests/mlfs-13.1-toolchain.tsv"
DEST="${ROOT_DIR}/sources/cache"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] || fail "Missing source manifest"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

# Validate every row before creating files or starting network transfers.
while IFS=$'\t' read -r package version url digest; do
    [[ -z "${package:-}" || "$package" == \#* ]] && continue
    [[ -n "${version:-}" && -n "${url:-}" ]] || fail "Malformed manifest row"
    [[ "$url" == https://* ]] || fail "Refusing non-HTTPS URL for $package"
    [[ "$digest" =~ ^[[:xdigit:]]{64}$ ]] ||
        fail "Refusing to download: missing or invalid SHA-256 for $package"
done < "$MANIFEST"

mkdir -p "$DEST"
while IFS=$'\t' read -r package version url digest; do
    [[ -z "${package:-}" || "$package" == \#* ]] && continue
    filename="${url##*/}"
    [[ "$filename" =~ ^[A-Za-z0-9._+-]+$ ]] || fail "Unsafe archive filename for $package"
    target="${DEST}/$filename"
    temporary="${target}.part"
    if [[ -f "$target" ]] && printf '%s  %s\n' "$digest" "$target" | sha256sum -c --status; then
        printf 'Verified cached: %s\n' "$filename"
        continue
    fi
    rm -f "$temporary"
    printf 'Downloading and verifying: %s\n' "$filename"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$temporary" "$url"
    printf '%s  %s\n' "$digest" "$temporary" | sha256sum -c -
    mv "$temporary" "$target"
done < "$MANIFEST"

printf 'All source archives passed SHA-256 verification.\n'
