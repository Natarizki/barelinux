#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_CONFIG="${ROOT_DIR}/config/architecture.conf"
BUILD_CONFIG="${ROOT_DIR}/config/build.conf"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$ARCH_CONFIG" ]] || fail "Missing config/architecture.conf"
[[ -f "$BUILD_CONFIG" ]] || fail "Missing config/build.conf"

bash -n "$ARCH_CONFIG" || fail "architecture.conf has invalid shell syntax"
bash -n "$BUILD_CONFIG" || fail "build.conf has invalid shell syntax"

grep -qx 'TARGET_ARCH=x86_64' "$ARCH_CONFIG" ||
    fail "TARGET_ARCH must be x86_64"

grep -qx 'X86_64_BASELINE=x86-64' "$ARCH_CONFIG" ||
    fail "The required CPU baseline must remain x86-64"

grep -qx 'AVX2_POLICY=optional' "$ARCH_CONFIG" ||
    fail "AVX2 must remain optional"

grep -qx 'MULTILIB=full' "$ARCH_CONFIG" ||
    fail "Full multilib must remain enabled"

grep -qx 'BUILD_SYSTEM=mlfs' "$BUILD_CONFIG" ||
    fail "BUILD_SYSTEM must be mlfs"

grep -qx 'MLFS_VERSION=13.1' "$BUILD_CONFIG" ||
    fail "MLFS_VERSION must be 13.1"

grep -qx 'TARGET_ARCH=x86_64' "$BUILD_CONFIG" ||
    fail "Build target must be x86_64"

printf 'BareLinux foundation configuration: OK\n'
