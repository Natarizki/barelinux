#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ARG="${1:-}"
LFS_HOME_ARCHIVE="${LFS_HOME_ARCHIVE:-}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[barelinux-full-mlfs] %s\n' "$*" >&2; }

[[ -n "$WORKSPACE_ARG" ]] || fail "usage: build-mlfs-full-alfs.sh WORKSPACE"
[[ "$(id -u)" -ne 0 ]] || fail "refusing to run the build as root"
[[ ! -L "$WORKSPACE_ARG" ]] || fail "workspace must not be a symlink"
[[ -d "$WORKSPACE_ARG" ]] || mkdir -p "$WORKSPACE_ARG"
WORKSPACE="$(realpath -e -- "$WORKSPACE_ARG")"
[[ "$WORKSPACE" != "/" ]] || fail "refusing filesystem root as workspace"

for tool in bash make tar python3 realpath stat df awk grep find sort sha256sum sudo mountpoint script getent groupadd useradd chown visudo; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

TARGET="$WORKSPACE/target"
MARKER="$TARGET/build/mlfs-13.1/binutils-pass1/BUILD-SUCCESS"
JHALFS="$TARGET/jhalfs"
TOOLS="$TARGET/tools"
SOURCES="$TARGET/sources"
STAGE="$TARGET/build/mlfs-13.1/full-book"
LOCK="$ROOT_DIR/sources/locks/alfs-mlfs.lock"
[[ -s "$MARKER" && -s "$JHALFS/Makefile" ]] || fail "verified Binutils build root or jhalfs Makefile is missing"
[[ -d "$TOOLS" && -d "$SOURCES" ]] || fail "Binutils tools or source directory is missing"
grep -Fxq 'artifact_schema=2' "$MARKER" || fail "unsupported Binutils artifact schema"
grep -Fxq 'stage=binutils-pass1' "$MARKER" || fail "wrong prerequisite stage"
grep -Fxq 'status=success' "$MARKER" || fail "Binutils prerequisite is not marked successful"

lock_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; count++} END {if (count != 1) exit 1}' "$LOCK"
}
MLFS_COMMIT="$(lock_value MLFS_COMMIT)"
JHALFS_COMMIT="$(lock_value JHALFS_COMMIT)"
grep -Fxq "mlfs_commit=$MLFS_COMMIT" "$MARKER" || fail "MLFS source commit mismatch"
grep -Fxq "jhalfs_commit=$JHALFS_COMMIT" "$MARKER" || fail "jhalfs source commit mismatch"

LFS_UID="$(awk -F= '$1=="lfs_uid" {print $2}' "$MARKER")"
LFS_GID="$(awk -F= '$1=="lfs_gid" {print $2}' "$MARKER")"
[[ "$LFS_UID" =~ ^[0-9]+$ && "$LFS_GID" =~ ^[0-9]+$ ]] || fail "invalid LFS account identity"
[[ -n "$LFS_HOME_ARCHIVE" && -s "$LFS_HOME_ARCHIVE" ]] || fail "persisted LFS home archive is missing"
getent passwd lfs >/dev/null 2>&1 && fail "unexpected existing host account named lfs"
getent group lfs >/dev/null 2>&1 && fail "unexpected existing host group named lfs"
getent passwd "$LFS_UID" >/dev/null 2>&1 && fail "recorded LFS UID is already in use"
getent group "$LFS_GID" >/dev/null 2>&1 && fail "recorded LFS GID is already in use"

python3 - "$LFS_HOME_ARCHIVE" <<'PY'
import posixpath, sys, tarfile
with tarfile.open(sys.argv[1], "r:xz") as tf:
    members = tf.getmembers()
    if not members:
        raise SystemExit("empty LFS home archive")
    for item in members:
        name = item.name
        if name.startswith("/") or any(p in ("", ".", "..") for p in name.split("/")[:-1]):
            raise SystemExit(f"unsafe LFS home path: {name!r}")
        if name.split("/", 1)[0] != "lfs":
            raise SystemExit(f"unexpected LFS home root: {name!r}")
        if item.issym() or item.islnk():
            target = item.linkname
            if target.startswith("/"):
                raise SystemExit(f"absolute LFS home link rejected: {name!r}")
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
            if resolved == ".." or resolved.startswith("../") or not resolved.startswith("lfs/"):
                raise SystemExit(f"LFS home link escapes lfs/: {name!r}")
        elif not (item.isfile() or item.isdir()):
            raise SystemExit(f"unsupported LFS home member: {name!r}")
PY

FREE_KB="$(df -Pk "$WORKSPACE" | awk 'NR==2 {print $4}')"
[[ "$FREE_KB" =~ ^[0-9]+$ ]] && (( FREE_KB >= 10485760 )) || fail "full MLFS build requires at least 10 GiB free workspace space"
[[ ! -e "$STAGE" ]] || fail "full-book stage already exists; use a fresh workspace"

log "Restoring the exact LFS build account and home from the verified Binutils checkpoint"
sudo groupadd --gid "$LFS_GID" lfs
sudo useradd --uid "$LFS_UID" --gid "$LFS_GID" --create-home --home-dir /home/lfs --shell /bin/bash --skel /dev/null lfs
sudo tar --same-owner -xJf "$LFS_HOME_ARCHIVE" -C /home
sudo chown -R lfs:lfs /home/lfs

# jhalfs alternates between the unprivileged LFS build user and root-owned
# book steps. The runner is disposable; grant the temporary lfs account
# passwordless sudo only for this CI build and always remove the rule on exit.
SUDOERS_FILE="/etc/sudoers.d/barelinux-lfs-build"
[[ ! -e "$SUDOERS_FILE" ]] || fail "temporary BareLinux LFS sudoers rule already exists"
printf '%s\\n' 'lfs ALL=(ALL) NOPASSWD: ALL' | sudo tee "$SUDOERS_FILE" >/dev/null
sudo chmod 0440 "$SUDOERS_FILE"
sudo visudo -cf "$SUDOERS_FILE" >/dev/null
mkdir -p "$STAGE"

export LFS="$TARGET"
export LFS_TGT=x86_64-lfs-linux-gnu
export CONFIG_SITE="$TARGET/usr/share/config.site"
export LC_ALL=POSIX
export MAKEFLAGS="-j${BLF_BUILD_JOBS:-2}"
export PATH="$TOOLS/bin:$TOOLS/$LFS_TGT/bin:$PATH"
[[ -x "$TOOLS/$LFS_TGT/bin/ld" && -x "$TOOLS/$LFS_TGT/bin/as" ]] || fail "verified cross Binutils tools are missing"

MOUNTPOINT="/mnt/barelinux-lfs"
sudo mkdir -p "$MOUNTPOINT"
mountpoint -q "$MOUNTPOINT" && fail "ALFS build mountpoint is already mounted"
cleanup_build_mount() {
  mountpoint -q "$MOUNTPOINT" && sudo umount "$MOUNTPOINT"
  sudo rm -f "$SUDOERS_FILE"
}
trap cleanup_build_mount EXIT
sudo mount --bind "$TARGET" "$MOUNTPOINT"

log "Running the complete jhalfs-generated MLFS Makefile; no BREAKPOINT is set"
log "This executes the dependency graph beyond GCC Pass 1 through the final MLFS book targets"
set +e
script -q -e -c "stty rows 24 cols 80; make -C '$MOUNTPOINT/jhalfs'" /dev/null 2>&1 | tee "$STAGE/full-book-build.log"
BUILD_STATUS="${PIPESTATUS[0]}"
set -e
(( BUILD_STATUS == 0 )) || fail "jhalfs full-book Makefile failed with exit $BUILD_STATUS"

cleanup_build_mount
trap - EXIT

log "Validating the completed MLFS system root"
for path in \
  usr/bin/bash \
  usr/bin/gcc \
  usr/bin/systemctl \
  usr/lib/libc.so.6 \
  usr/lib/systemd/systemd \
  etc/passwd \
  etc/group \
  var; do
  [[ -e "$TARGET/$path" ]] || fail "completed MLFS root is missing required path: /$path"
done
[[ -x "$TARGET/usr/bin/bash" && -x "$TARGET/usr/bin/gcc" && -x "$TARGET/usr/bin/systemctl" ]] || fail "core MLFS executables are not executable"

find "$TARGET" -xdev -type f -printf '%P\n' | LC_ALL=C sort > "$STAGE/installed-file-inventory.txt"
INVENTORY_SHA="$(sha256sum "$STAGE/installed-file-inventory.txt" | awk '{print $1}')"
{
  printf 'artifact_schema=1\nstage=mlfs-full-book\nstatus=success\n'
  printf 'mlfs_commit=%s\njhalfs_commit=%s\n' "$MLFS_COMMIT" "$JHALFS_COMMIT"
  printf 'target=x86_64-lfs-linux-gnu\nmultilib_profile=ml_32\ninit_system=systemd\n'
  printf 'installed_file_inventory_sha256=%s\n' "$INVENTORY_SHA"
  printf 'completed_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$STAGE/MLFS-BASE-SUCCESS"

log "PASS: full MLFS book completed through jhalfs and required root filesystem checks passed"
log "NOTE: this is the MLFS base system, not yet the integrated BareLinux ISO"
