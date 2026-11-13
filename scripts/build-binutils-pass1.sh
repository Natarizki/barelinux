#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ARG="${1:-}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[binutils-pass1] %s\n' "$*"; }
[[ -n "$WORKSPACE_ARG" ]] || fail "usage: build-binutils-pass1.sh WORKSPACE"
[[ "$(id -u)" -ne 0 ]] || fail "refusing to build as root"
[[ -d "$WORKSPACE_ARG" && ! -L "$WORKSPACE_ARG" ]] || fail "workspace must be an existing, non-symlink directory"
WORKSPACE="$(realpath -e -- "$WORKSPACE_ARG")"
[[ "$(stat -c '%u' "$WORKSPACE")" == "$(id -u)" ]] || fail "workspace must be owned by current build user"
[[ "$WORKSPACE" != "/" && "$(uname -m)" == "x86_64" ]] || fail "requires a non-root workspace on an x86_64 host"
for tool in bash curl sha256sum tar make gcc g++ ld as python3 realpath stat df nproc awk; do command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"; done
free_kb="$(df -Pk "$WORKSPACE" | awk 'NR==2 {print $4}')"
[[ "$free_kb" =~ ^[0-9]+$ ]] && (( free_kb >= 2097152 )) || fail "at least 2 GiB free space required"
manifest="$ROOT_DIR/sources/manifests/mlfs-13.1-toolchain.tsv"
row="$(awk -F '\t' '$1=="binutils" {print; found=1} END {if (!found) exit 1}' "$manifest")" || fail "Binutils missing from manifest"
IFS=$'\t' read -r package version url digest <<< "$row"
[[ "$version" == "2.47" && "$url" == https://* && "$digest" =~ ^[[:xdigit:]]{64}$ ]] || fail "Binutils source lock invalid"
CACHE="$WORKSPACE/sources/cache"
UNPACK="$WORKSPACE/sources/unpacked"
STAGE="$WORKSPACE/build/mlfs-13.1/binutils-pass1"
LFS="$WORKSPACE/rootfs"
ARCHIVE="$CACHE/${url##*/}"
mkdir -p "$CACHE" "$UNPACK" "$STAGE" "$LFS/tools" "$LFS/usr/share"
[[ ! -e "$STAGE/.started" && ! -e "$UNPACK/binutils-2.47" ]] || fail "stage/source already exists; inspect before retrying"
if [[ -f "$ARCHIVE" ]] && ! printf '%s  %s\n' "$digest" "$ARCHIVE" | sha256sum -c --status; then rm -f "$ARCHIVE"; fi
if [[ ! -f "$ARCHIVE" ]]; then
  part="$ARCHIVE.part"; rm -f "$part"
  log "Downloading Binutils $version"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$part" "$url"
  printf '%s  %s\n' "$digest" "$part" | sha256sum -c -
  mv "$part" "$ARCHIVE"
fi
printf '%s  %s\n' "$digest" "$ARCHIVE" | sha256sum -c -
python3 - "$ARCHIVE" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1], "r:*") as tf:
    entries = tf.getmembers()
    if not entries:
        raise SystemExit("empty archive")
    for item in entries:
        parts = item.name.split("/")
        if item.name.startswith("/") or any(p in ("", ".", "..") for p in parts[:-1]):
            raise SystemExit(f"unsafe archive path: {item.name!r}")
        if parts[0] != "binutils-2.47":
            raise SystemExit(f"unexpected archive root: {item.name!r}")
        if item.issym() or item.islnk():
            target = item.linkname
            if target.startswith("/") or ".." in target.split("/"):
                raise SystemExit(f"unsafe archive link: {item.name!r} -> {target!r}")
PY
log "Extracting verified archive"
tar -xf "$ARCHIVE" -C "$UNPACK" --no-same-owner --no-same-permissions
SOURCE="$UNPACK/binutils-2.47"
[[ -x "$SOURCE/configure" ]] || fail "archive missing configure script"
: > "$STAGE/.started"
export LFS LFS_TGT=x86_64-lfs-linux-gnu LC_ALL=POSIX
export CONFIG_SITE="$LFS/usr/share/config.site"
: > "$CONFIG_SITE"
jobs="${BLF_BUILD_JOBS:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "BLF_BUILD_JOBS must be positive integer"
export MAKEFLAGS=
mkdir "$STAGE/work"
cd "$STAGE/work"
log "Configuring Binutils $version for $LFS_TGT"
"$SOURCE/configure" --prefix="$LFS/tools" --with-sysroot="$LFS" --target="$LFS_TGT" \
  --disable-nls --enable-gprofng=no --disable-werror --enable-new-dtags \
  --enable-default-hash-style=gnu 2>&1 | tee "$STAGE/configure.log"
log "Compiling with $jobs jobs"
make -j"$jobs" 2>&1 | tee "$STAGE/build.log"
log "Installing into isolated target prefix"
make install 2>&1 | tee "$STAGE/install.log"
cross_ld="$LFS/tools/$LFS_TGT/bin/ld"
cross_as="$LFS/tools/$LFS_TGT/bin/as"
[[ -x "$cross_ld" && -x "$cross_as" ]] || fail "cross linker/assembler missing"
ld_version="$("$cross_ld" -V 2>&1)"
grep -q 'elf_x86_64' <<< "$ld_version" || fail "cross linker lacks x86_64 ELF support"
"$cross_as" --version >/dev/null
"$cross_ld" --version >/dev/null
{
  printf 'stage=binutils-pass1\npackage=binutils\nversion=%s\n' "$version"
  printf 'source_sha256=%s\ntarget=%s\nprefix=%s\n' "$digest" "$LFS_TGT" "$LFS/tools"
  printf 'host_arch=%s\ncompleted_utc=%s\nstatus=success\n' "$(uname -m)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$STAGE/BUILD-SUCCESS"
log "PASS: Binutils Pass 1 compiled, installed, and validated"
