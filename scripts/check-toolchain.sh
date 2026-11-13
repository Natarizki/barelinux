#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_CONFIG="${ROOT_DIR}/config/architecture.conf"
BUILD_CONFIG="${ROOT_DIR}/config/build.conf"
TOOLCHAIN_CONFIG="${ROOT_DIR}/config/toolchain.conf"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

for file in "$ARCH_CONFIG" "$BUILD_CONFIG" "$TOOLCHAIN_CONFIG"; do
    [[ -f "$file" ]] || fail "Missing configuration: ${file#"$ROOT_DIR"/}"
    bash -n "$file" || fail "Invalid shell syntax: ${file#"$ROOT_DIR"/}"
done

grep -qx 'TARGET_ARCH=x86_64' "$ARCH_CONFIG" || fail "Target architecture must be x86_64"
grep -qx 'MULTILIB=full' "$ARCH_CONFIG" || fail "Full multilib is required"
grep -qx 'BUILD_SYSTEM=mlfs' "$BUILD_CONFIG" || fail "MLFS must remain the build system"
grep -qx 'MLFS_VERSION=13.1' "$BUILD_CONFIG" || fail "MLFS 13.1 is required"
grep -qx 'TOOLCHAIN_MODEL=mlfs-cross' "$TOOLCHAIN_CONFIG" || fail "Unexpected toolchain model"
grep -qx 'PRIMARY_ABI=x86_64' "$TOOLCHAIN_CONFIG" || fail "Primary ABI must be x86_64"
grep -qx 'SECONDARY_ABI=i686' "$TOOLCHAIN_CONFIG" || fail "Secondary ABI must be i686"
grep -qx 'MULTILIB_MODE=full' "$TOOLCHAIN_CONFIG" || fail "Toolchain must use full multilib"

printf 'BareLinux cross-toolchain policy: OK (x86_64 + i686)\n'
printf 'NOTE: this validates policy only; no compiler or sysroot has been built.\n'
