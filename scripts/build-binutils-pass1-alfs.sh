#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ARG="${1:-}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[binutils-pass1-alfs] %s\n' "$*"; }

[[ -n "$WORKSPACE_ARG" ]] || fail "usage: build-binutils-pass1-alfs.sh WORKSPACE"
[[ "$(id -u)" -ne 0 ]] || fail "refusing to build as root"
[[ ! -L "$WORKSPACE_ARG" ]] || fail "workspace must not be a symlink"
[[ -d "$WORKSPACE_ARG" ]] || mkdir -p "$WORKSPACE_ARG"
WORKSPACE="$(realpath -e -- "$WORKSPACE_ARG")"
[[ "$WORKSPACE" != "/" ]] || fail "refusing filesystem root as workspace"
[[ "$(stat -c '%u' "$WORKSPACE")" == "$(id -u)" ]] || fail "workspace must be owned by current build user"

for tool in bash git python3 xsltproc curl sha256sum tar make gcc g++ ld as realpath stat df awk grep tee nproc sudo mountpoint script; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

FREE_KB="$(df -Pk "$WORKSPACE" | awk 'NR==2 {print $4}')"
[[ "$FREE_KB" =~ ^[0-9]+$ ]] && (( FREE_KB >= 2097152 )) || fail "at least 2 GiB free space required"

LOCK="$ROOT_DIR/sources/locks/alfs-mlfs.lock"
MANIFEST="$ROOT_DIR/sources/manifests/mlfs-13.1-toolchain.tsv"
lock_value() {
  local key="$1" value
  value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; count++} END {if (count != 1) exit 1}' "$LOCK")" || fail "lock must contain exactly one $key entry"
  printf '%s' "$value"
}
MLFS_COMMIT="$(lock_value MLFS_COMMIT)"
JHALFS_COMMIT="$(lock_value JHALFS_COMMIT)"
[[ "$MLFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "MLFS commit is not pinned"
[[ "$JHALFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "jhalfs commit is not pinned"

ROW="$(awk -F '\t' '$1=="binutils" {print; found++} END {if (found != 1) exit 1}' "$MANIFEST")" || fail "Binutils must have exactly one source-manifest entry"
IFS=$'\t' read -r PACKAGE VERSION URL DIGEST <<< "$ROW"
[[ "$VERSION" == "2.47" && "$URL" == "https://"* && "$DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail "Binutils source lock is invalid"

ALFS_WORK="$WORKSPACE/alfs"
TARGET="$WORKSPACE/target"
SOURCES="$TARGET/sources"
TOOLS="$TARGET/tools"
STAGE="$TARGET/build/mlfs-13.1/binutils-pass1"
RECIPE="$TARGET/jhalfs/lfs-commands/chapter05/501-binutils-pass1"
ARCHIVE="$SOURCES/${URL##*/}"

[[ ! -e "$ALFS_WORK" && ! -e "$TARGET" ]] || fail "workspace already contains alfs/ or target/; use a fresh workspace"
mkdir -p "$SOURCES" "$TOOLS" "$TARGET/usr/share" "$STAGE"

log "Generating the package recipe from pinned raw MLFS and pinned jhalfs"
bash "$ROOT_DIR/scripts/validate-alfs-mlfs-sources.sh" "$ALFS_WORK"
[[ -f "$RECIPE" && ! -L "$RECIPE" ]] || fail "jhalfs did not generate the Binutils Pass 1 recipe"
grep -Fq -- '--target=$LFS_TGT' "$RECIPE" || fail "generated recipe target does not match the expected MLFS instruction"
grep -Fq -- '--prefix=$LFS/tools' "$RECIPE" || fail "generated recipe prefix does not match the expected MLFS instruction"
grep -Fq -- '--enable-default-hash-style=gnu' "$RECIPE" || fail "generated recipe is missing expected MLFS configure instruction"

if [[ -f "$ARCHIVE" ]] && ! printf '%s  %s\n' "$DIGEST" "$ARCHIVE" | sha256sum -c --status; then
  rm -f "$ARCHIVE"
fi
if [[ ! -f "$ARCHIVE" ]]; then
  PART="$ARCHIVE.part"
  rm -f "$PART"
  log "Downloading verified Binutils $VERSION source"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$PART" "$URL"
  printf '%s  %s\n' "$DIGEST" "$PART" | sha256sum -c -
  mv "$PART" "$ARCHIVE"
fi
printf '%s  %s\n' "$DIGEST" "$ARCHIVE" | sha256sum -c -

log "Checking source archive paths and link entries before ALFS recipe extraction"
python3 - "$ARCHIVE" <<'PY'
import posixpath, sys, tarfile
expected = "binutils-2.47"
with tarfile.open(sys.argv[1], "r:*") as tf:
    members = tf.getmembers()
    if not members:
        raise SystemExit("empty source archive")
    for item in members:
        name = item.name
        if name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/")[:-1]):
            raise SystemExit(f"unsafe archive path: {name!r}")
        if name.split("/", 1)[0] != expected:
            raise SystemExit(f"unexpected archive root: {name!r}")
        if item.issym() or item.islnk():
            target = item.linkname
            if target.startswith("/"):
                raise SystemExit(f"absolute archive link rejected: {name!r} -> {target!r}")
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
            if resolved == ".." or resolved.startswith("../") or not resolved.startswith(expected + "/"):
                raise SystemExit(f"archive link escapes package root: {name!r} -> {target!r}")
        elif not (item.isfile() or item.isdir()):
            raise SystemExit(f"unsupported archive member type: {name!r}")
PY

: > "$TARGET/usr/share/config.site"
export LFS="$TARGET"
export LFS_TGT=x86_64-lfs-linux-gnu
export CONFIG_SITE="$TARGET/usr/share/config.site"
export LC_ALL=POSIX
export MAKEFLAGS="-j${BLF_BUILD_JOBS:-2}"
JOBS="${BLF_BUILD_JOBS:-2}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || fail "BLF_BUILD_JOBS must be a positive integer"

log "Executing Binutils Pass 1 through the generated jhalfs Makefile target"
MOUNTPOINT="/mnt/barelinux-lfs"
sudo mkdir -p "$MOUNTPOINT"
mountpoint -q "$MOUNTPOINT" && fail "ALFS build mountpoint is already mounted"
sudo mount --bind "$TARGET" "$MOUNTPOINT"
cleanup_build_mount() { mountpoint -q "$MOUNTPOINT" && sudo umount "$MOUNTPOINT"; }
trap cleanup_build_mount EXIT
grep -Fq '501-binutils-pass1:' "$MOUNTPOINT/jhalfs/Makefile" || fail "jhalfs Makefile lacks the Binutils Pass 1 target"
set +e
script -q -e -c "stty rows 24 cols 80; make -C '$MOUNTPOINT/jhalfs' BREAKPOINT=501-binutils-pass1" /dev/null 2>&1 | tee "$STAGE/build.log"
BUILD_STATUS="${PIPESTATUS[0]}"
set -e
[[ -e "$MOUNTPOINT/jhalfs/501-binutils-pass1" ]] || fail "jhalfs did not complete 501-binutils-pass1"
if (( BUILD_STATUS != 0 )); then
  sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' "$STAGE/build.log" > "$STAGE/build-clean.log"
  grep -Fq "The build has been stopped at 501-binutils-pass1 as requested" "$STAGE/build-clean.log" || fail "jhalfs Makefile failed before its requested 501-binutils-pass1 checkpoint (exit $BUILD_STATUS)"
  log "jhalfs reached the requested 501-binutils-pass1 breakpoint; its documented stop status is accepted"
fi
cleanup_build_mount
trap - EXIT

CROSS_LD="$TOOLS/$LFS_TGT/bin/ld"
CROSS_AS="$TOOLS/$LFS_TGT/bin/as"
[[ -x "$CROSS_LD" && -x "$CROSS_AS" ]] || fail "generated recipe did not install cross linker and assembler"
LD_VERSION="$("$CROSS_LD" -V 2>&1)"
grep -q 'elf_x86_64' <<< "$LD_VERSION" || fail "cross linker lacks x86_64 ELF support"
"$CROSS_AS" --version >/dev/null
"$CROSS_LD" --version >/dev/null

RECIPE_SHA="$(sha256sum "$RECIPE" | awk '{print $1}')"
{
  printf 'artifact_schema=2\nstage=binutils-pass1\npackage=binutils\nversion=%s\n' "$VERSION"
  printf 'source_sha256=%s\nrecipe_sha256=%s\n' "$DIGEST" "$RECIPE_SHA"
  printf 'mlfs_commit=%s\njhalfs_commit=%s\ntarget=%s\nprefix=%s\n' "$MLFS_COMMIT" "$JHALFS_COMMIT" "$LFS_TGT" "$TOOLS"
  printf 'host_arch=%s\nlfs_uid=%s\nlfs_gid=%s\ncompleted_utc=%s\nstatus=success\n' "$(uname -m)" "$(id -u lfs)" "$(id -g lfs)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$STAGE/BUILD-SUCCESS"

log "PASS: generated ALFS recipe compiled, installed, and validated Binutils Pass 1"
