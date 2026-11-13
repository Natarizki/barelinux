#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ARG="${1:-}"
LFS_HOME_ARCHIVE="${LFS_HOME_ARCHIVE:-}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[gcc-pass1-alfs] %s\n' "$*" >&2; }

[[ -n "$WORKSPACE_ARG" ]] || fail "usage: build-gcc-pass1-alfs.sh WORKSPACE"
[[ "$(id -u)" -ne 0 ]] || fail "refusing to build as root"
[[ ! -L "$WORKSPACE_ARG" ]] || fail "workspace must not be a symlink"
[[ -d "$WORKSPACE_ARG" ]] || mkdir -p "$WORKSPACE_ARG"
WORKSPACE="$(realpath -e -- "$WORKSPACE_ARG")"
[[ "$WORKSPACE" != "/" ]] || fail "refusing filesystem root as workspace"
[[ "$(stat -c '%u' "$WORKSPACE")" == "$(id -u)" ]] || fail "workspace must be owned by current build user"

for tool in bash git python3 xsltproc curl sha256sum sha512sum tar make gcc g++ ld as realpath stat df awk grep tee nproc sudo mountpoint script groupadd useradd id getent chown; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

FREE_KB="$(df -Pk "$WORKSPACE" | awk 'NR==2 {print $4}')"
[[ "$FREE_KB" =~ ^[0-9]+$ ]] && (( FREE_KB >= 8388608 )) || fail "at least 8 GiB free space required"

LOCK="$ROOT_DIR/sources/locks/alfs-mlfs.lock"
MANIFEST="$ROOT_DIR/sources/manifests/mlfs-13.1-gcc-pass1.tsv"
lock_value() {
  local key="$1" value
  value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; count++} END {if (count != 1) exit 1}' "$LOCK")" || fail "lock must contain exactly one $key entry"
  printf '%s' "$value"
}
MLFS_COMMIT="$(lock_value MLFS_COMMIT)"
JHALFS_COMMIT="$(lock_value JHALFS_COMMIT)"
[[ "$MLFS_COMMIT" =~ ^[0-9a-f]{40}$ && "$JHALFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "source commits are not pinned"

ALFS_WORK="$WORKSPACE/alfs"
TARGET="$WORKSPACE/target"
SOURCES="$TARGET/sources"
TOOLS="$TARGET/tools"
STAGE="$TARGET/build/mlfs-13.1/gcc-pass1"
RECIPE="$TARGET/jhalfs/lfs-commands/chapter05/502-gcc-pass1"
[[ -s "$TARGET/jhalfs/Makefile" ]] || fail "the verified Binutils artifact lacks the generated jhalfs Makefile"
[[ -d "$TOOLS" ]] || fail "Binutils Pass 1 tools prefix is missing; install the verified prerequisite artifact first"
[[ -f "$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS" ]] || fail "Binutils Pass 1 success marker is missing"
grep -Fxq "mlfs_commit=$MLFS_COMMIT" "$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS" || fail "Binutils artifact MLFS commit mismatch"
grep -Fxq "jhalfs_commit=$JHALFS_COMMIT" "$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS" || fail "Binutils artifact jhalfs commit mismatch"
mkdir -p "$SOURCES" "$STAGE"
[[ -f "$RECIPE" && ! -L "$RECIPE" ]] || fail "verified jhalfs build root lacks the GCC Pass 1 recipe"
for required in '--target=$LFS_TGT' '--prefix=$LFS/tools' '--enable-multilib' '--with-multilib-list=m64,m32' 'mpfr-4.2.2.tar.xz' 'gmp-6.3.0.tar.xz' 'mpc-1.4.1.tar.xz'; do
  grep -Fq -- "$required" "$RECIPE" || fail "generated GCC recipe is missing expected MLFS instruction: $required"
done

download_locked() {
  local package="$1" version="$2" url="$3" algorithm="$4" digest="$5"
  local archive="$SOURCES/${url##*/}" part="$SOURCES/${url##*/}.part"
  [[ "$url" == https://* ]] || fail "$package source URL must use HTTPS"
  case "$algorithm" in
    sha256) [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail "$package SHA-256 lock is invalid";;
    sha512) [[ "$digest" =~ ^[0-9a-f]{128}$ ]] || fail "$package SHA-512 lock is invalid";;
    *) fail "unsupported digest algorithm for $package: $algorithm";;
  esac
  if [[ -f "$archive" ]] && ! printf '%s  %s\n' "$digest" "$archive" | "${algorithm}sum" -c - >&2; then
    rm -f "$archive"
  fi
  if [[ ! -f "$archive" ]]; then
    rm -f "$part"
    log "Downloading pinned $package $version source"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$part" "$url"
    printf '%s  %s\n' "$digest" "$part" | "${algorithm}sum" -c - >&2
    mv "$part" "$archive"
  fi
  printf '%s  %s\n' "$digest" "$archive" | "${algorithm}sum" -c - >&2
  printf '%s\n' "$archive"
}

declare -A ARCHIVES=()
while IFS=$'\t' read -r package version url algorithm digest; do
  [[ -z "${package:-}" || "$package" == \#* ]] && continue
  [[ -z "${ARCHIVES[$package]:-}" ]] || fail "duplicate manifest entry: $package"
  ARCHIVES["$package"]="$(download_locked "$package" "$version" "$url" "$algorithm" "$digest")"
done < "$MANIFEST"
for package in gcc mpfr gmp mpc; do
  [[ -n "${ARCHIVES[$package]:-}" ]] || fail "missing pinned source manifest entry: $package"
done

log "Checking all GCC source archive paths and links before extraction"
python3 - "${ARCHIVES[gcc]}" "${ARCHIVES[mpfr]}" "${ARCHIVES[gmp]}" "${ARCHIVES[mpc]}" <<'PY'
import posixpath, sys, tarfile
expected = ["gcc-16.2.0", "mpfr-4.2.2", "gmp-6.3.0", "mpc-1.4.1"]
for archive, root in zip(sys.argv[1:], expected):
    with tarfile.open(archive, "r:*") as tf:
        members = tf.getmembers()
        if not members:
            raise SystemExit(f"empty source archive: {archive}")
        for item in members:
            name = item.name
            if name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/")[:-1]):
                raise SystemExit(f"unsafe archive path: {archive}: {name!r}")
            if name.split("/", 1)[0] != root:
                raise SystemExit(f"unexpected archive root: {archive}: {name!r}")
            if item.issym() or item.islnk():
                target = item.linkname
                if target.startswith("/"):
                    raise SystemExit(f"absolute archive link rejected: {name!r} -> {target!r}")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                if resolved == ".." or resolved.startswith("../") or not resolved.startswith(root + "/"):
                    raise SystemExit(f"archive link escapes package root: {name!r} -> {target!r}")
            elif not (item.isfile() or item.isdir()):
                raise SystemExit(f"unsupported archive member type: {name!r}")
PY

sudo mkdir -p "$TARGET/usr/share"
sudo install -m 0644 /dev/null "$TARGET/usr/share/config.site"
export LFS="$TARGET"
export LFS_TGT=x86_64-lfs-linux-gnu
export CONFIG_SITE="$TARGET/usr/share/config.site"
export LC_ALL=POSIX
export MAKEFLAGS="-j${BLF_BUILD_JOBS:-2}"
JOBS="${BLF_BUILD_JOBS:-2}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || fail "BLF_BUILD_JOBS must be a positive integer"
export PATH="$TOOLS/bin:$TOOLS/$LFS_TGT/bin:$PATH"
command -v "$LFS_TGT-ld" >/dev/null 2>&1 || fail "Binutils prerequisite artifact is missing target linker"
command -v "$LFS_TGT-as" >/dev/null 2>&1 || fail "Binutils prerequisite artifact is missing target assembler"

log "Executing GCC Pass 1 through the generated jhalfs Makefile target"
MOUNTPOINT="/mnt/barelinux-lfs"
sudo mkdir -p "$MOUNTPOINT"
mountpoint -q "$MOUNTPOINT" && fail "ALFS build mountpoint is already mounted"
LFS_UID="$(awk -F= '$1=="lfs_uid" {print $2}' "$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS")"
LFS_GID="$(awk -F= '$1=="lfs_gid" {print $2}' "$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS")"
[[ "$LFS_UID" =~ ^[0-9]+$ && "$LFS_GID" =~ ^[0-9]+$ ]] || fail "Binutils artifact has invalid LFS account IDs"
[[ -n "$LFS_HOME_ARCHIVE" && -s "$LFS_HOME_ARCHIVE" ]] || fail "verified LFS home archive is missing"
getent passwd lfs >/dev/null 2>&1 && fail "unexpected existing host account named lfs"
getent group lfs >/dev/null 2>&1 && fail "unexpected existing host group named lfs"
getent passwd "$LFS_UID" >/dev/null 2>&1 && fail "recorded LFS UID is already in use"
getent group "$LFS_GID" >/dev/null 2>&1 && fail "recorded LFS GID is already in use"
sudo groupadd --gid "$LFS_GID" lfs
sudo useradd --uid "$LFS_UID" --gid "$LFS_GID" --create-home --home-dir /home/lfs --shell /bin/bash --skel /dev/null lfs
sudo tar --no-same-owner -xJf "$LFS_HOME_ARCHIVE" -C /home
sudo chown -R lfs:lfs /home/lfs
sudo mount --bind "$TARGET" "$MOUNTPOINT"
cleanup_build_mount() { mountpoint -q "$MOUNTPOINT" && sudo umount "$MOUNTPOINT"; }
trap cleanup_build_mount EXIT
grep -Fq '502-gcc-pass1:' "$MOUNTPOINT/jhalfs/Makefile" || fail "jhalfs Makefile lacks the GCC Pass 1 target"
set +e
script -q -e -c "stty rows 24 cols 80; make -C '$MOUNTPOINT/jhalfs' BREAKPOINT=502-gcc-pass1" /dev/null 2>&1 | tee "$STAGE/build.log"
BUILD_STATUS="${PIPESTATUS[0]}"
set -e
[[ -e "$MOUNTPOINT/jhalfs/502-gcc-pass1" ]] || fail "jhalfs did not complete 502-gcc-pass1"
if (( BUILD_STATUS != 0 )); then
  sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' "$STAGE/build.log" > "$STAGE/build-clean.log"
  grep -Fq "The build has been stopped at 502-gcc-pass1 as requested" "$STAGE/build-clean.log" || fail "jhalfs Makefile failed before its requested 502-gcc-pass1 checkpoint (exit $BUILD_STATUS)"
  log "jhalfs reached the requested 502-gcc-pass1 breakpoint; its documented stop status is accepted"
fi
cleanup_build_mount
trap - EXIT

CROSS_GCC="$TOOLS/bin/$LFS_TGT-gcc"
CROSS_GXX="$TOOLS/bin/$LFS_TGT-g++"
[[ -x "$CROSS_GCC" && -x "$CROSS_GXX" ]] || fail "generated recipe did not install cross GCC and G++"
GCC_TARGET="$("$CROSS_GCC" -dumpmachine)"
[[ "$GCC_TARGET" == "$LFS_TGT" ]] || fail "cross GCC target mismatch: $GCC_TARGET"
"$CROSS_GCC" --version | head -n 1 | grep -Fq '16.2.0' || fail "cross GCC version is not 16.2.0"
"$CROSS_GCC" -print-file-name=include/limits.h | grep -q "$TOOLS" || fail "GCC limits.h was not installed under the BareLinux tools prefix"
"$CROSS_GCC" -print-multi-lib | grep -q '32' || fail "GCC does not expose the expected 32-bit multilib variant"

RECIPE_SHA="$(sha256sum "$RECIPE" | awk '{print $1}')"
{
  printf 'artifact_schema=2\nstage=gcc-pass1\npackage=gcc\nversion=16.2.0\n'
  awk -F '\t' 'NF == 5 && $1 !~ /^#/ {printf "source_%s_%s=%s\n", $1, $4, $5}' "$MANIFEST"
  printf 'recipe_sha256=%s\nmlfs_commit=%s\njhalfs_commit=%s\n' "$RECIPE_SHA" "$MLFS_COMMIT" "$JHALFS_COMMIT"
  printf 'target=%s\nprefix=%s\nhost_arch=%s\nlfs_uid=%s\nlfs_gid=%s\ncompleted_utc=%s\nstatus=success\n' "$LFS_TGT" "$TOOLS" "$(uname -m)" "$(id -u lfs)" "$(id -g lfs)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$STAGE/BUILD-SUCCESS"

log "PASS: generated ALFS recipe compiled, installed, and validated GCC Pass 1"
