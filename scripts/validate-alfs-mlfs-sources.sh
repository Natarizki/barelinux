#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${1:-}"
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[alfs-mlfs-audit] %s\n' "$*"; }

[[ -n "$WORKSPACE" ]] || fail "usage: validate-alfs-mlfs-sources.sh WORKSPACE"
[[ ! -L "$WORKSPACE" ]] || fail "workspace must not be a symlink"
mkdir -p "$WORKSPACE"
WORKSPACE="$(realpath -e -- "$WORKSPACE")"
[[ "$WORKSPACE" != "/" ]] || fail "refusing filesystem root as workspace"

for tool in git python3 grep find sort realpath xsltproc sed wc tr sudo mountpoint; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

LOCK="$ROOT_DIR/sources/locks/alfs-mlfs.lock"
[[ -f "$LOCK" ]] || fail "source lock missing"
lock_value() {
  local key="$1" value count
  value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; count++} END {if (count != 1) exit 1}' "$LOCK")" || fail "lock must contain exactly one $key entry"
  printf '%s' "$value"
}
MLFS_REPOSITORY="$(lock_value MLFS_REPOSITORY)"
MLFS_REF="$(lock_value MLFS_REF)"
MLFS_COMMIT="$(lock_value MLFS_COMMIT)"
JHALFS_REPOSITORY="$(lock_value JHALFS_REPOSITORY)"
JHALFS_MIRROR="$(lock_value JHALFS_MIRROR)"
JHALFS_COMMIT="$(lock_value JHALFS_COMMIT)"

[[ "$MLFS_REPOSITORY" == "https://git.linuxfromscratch.org/lfs.git" ]] || fail "unexpected MLFS upstream"
[[ "$MLFS_REF" == "multilib" ]] || fail "unexpected MLFS ref"
[[ "$MLFS_COMMIT" == "UNPINNED" || "$MLFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "invalid MLFS commit lock"
[[ "$JHALFS_REPOSITORY" == "https://git.linuxfromscratch.org/jhalfs.git" ]] || fail "unexpected jhalfs upstream"
[[ "$JHALFS_MIRROR" == "https://github.com/lfs-book/jhalfs.git" ]] || fail "unexpected jhalfs mirror"
[[ "$JHALFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "invalid pinned jhalfs commit"

AUDIT="$WORKSPACE/audit"
MLFS_DIR="$WORKSPACE/mlfs"
JHALFS_DIR="$WORKSPACE/jhalfs"
[[ ! -e "$AUDIT" && ! -e "$MLFS_DIR" && ! -e "$JHALFS_DIR" ]] || fail "workspace already contains audit/source directories"
mkdir -p "$AUDIT"

log "Cloning raw MLFS source from the official multilib branch"
git clone --quiet --no-tags --single-branch --branch "$MLFS_REF" "$MLFS_REPOSITORY" "$MLFS_DIR"
if [[ "$MLFS_COMMIT" != "UNPINNED" ]]; then
  git -C "$MLFS_DIR" checkout --quiet --detach "$MLFS_COMMIT"
fi
MLFS_RESOLVED="$(git -C "$MLFS_DIR" rev-parse HEAD)"
if [[ "$MLFS_COMMIT" != "UNPINNED" && "$MLFS_RESOLVED" != "$MLFS_COMMIT" ]]; then
  fail "resolved MLFS commit $MLFS_RESOLVED differs from locked $MLFS_COMMIT"
fi

log "Cloning the read-only upstream jhalfs mirror at the pinned commit"
git clone --quiet --no-checkout "$JHALFS_MIRROR" "$JHALFS_DIR"
git -C "$JHALFS_DIR" fetch --quiet --depth 1 origin "$JHALFS_COMMIT"
git -C "$JHALFS_DIR" checkout --quiet --detach "$JHALFS_COMMIT"
JHALFS_RESOLVED="$(git -C "$JHALFS_DIR" rev-parse HEAD)"
[[ "$JHALFS_RESOLVED" == "$JHALFS_COMMIT" ]] || fail "jhalfs checkout does not match pinned commit"

log "Checking raw MLFS 13.1 source layout"
[[ -f "$MLFS_DIR/index.xml" ]] || fail "raw MLFS index.xml missing"
[[ -f "$MLFS_DIR/stylesheets/lfs-xsl/profile.xsl" ]] || fail "MLFS profile stylesheet missing"
[[ -f "$JHALFS_DIR/LFS/lfs.xsl" ]] || fail "jhalfs LFS extraction stylesheet missing"
[[ -f "$JHALFS_DIR/common/libs/func_book_parser" ]] || fail "jhalfs book parser missing"
XML_COUNT="$(find "$MLFS_DIR" -type f -name '*.xml' | wc -l | tr -d ' ')"
XSL_COUNT="$(find "$MLFS_DIR" -type f \( -name '*.xsl' -o -name '*.xslt' \) | wc -l | tr -d ' ')"
(( XML_COUNT > 0 )) || fail "no XML book sources found in raw MLFS checkout"
grep -RIl --include='*.xml' 'MLFS-13.1 released' "$MLFS_DIR" > "$AUDIT/mlfs-release-marker-files.txt" || true
if [[ ! -s "$AUDIT/mlfs-release-marker-files.txt" ]]; then
  grep -RIl --include='*.xml' '13.1' "$MLFS_DIR/chapter01" > "$AUDIT/mlfs-release-marker-files.txt" 2>/dev/null || true
fi
[[ -s "$AUDIT/mlfs-release-marker-files.txt" ]] || fail "could not locate MLFS 13.1 release/changelog marker"
grep -RIl -E --include='*.xml' --include='*.xsl' --include='*.xslt' 'multilib|i686|m32' "$MLFS_DIR" > "$AUDIT/mlfs-multilib-files.txt" || true
[[ -s "$AUDIT/mlfs-multilib-files.txt" ]] || fail "no multilib-related XML/XSL source material found"

log "Verifying jhalfs local-book and multilib configuration support"
grep -q 'config[[:space:]]\+WORKING_COPY' "$JHALFS_DIR/Config.in" || fail "jhalfs has no local book configuration"
grep -q 'config[[:space:]]\+MULTILIB' "$JHALFS_DIR/Config.in" || fail "jhalfs has no multilib profile setting"
grep -q 'if \[ -z "\$WORKING_COPY" \]' "$JHALFS_DIR/common/libs/func_book_parser" || fail "jhalfs local-copy branch not found"
grep -q 'profile.arch' "$JHALFS_DIR/common/libs/func_book_parser" || fail "jhalfs profile transform invocation not found"

log "Preparing a non-interactive jhalfs configuration for raw MLFS 13.1"
TARGET_DIR="$(dirname "$WORKSPACE")/target"
MOUNTPOINT="/mnt/barelinux-lfs"
BUILDDIR="$MOUNTPOINT"
JHALFS_BUILD_DIR="$BUILDDIR/jhalfs"
mkdir -p "$TARGET_DIR"
sudo mkdir -p "$MOUNTPOINT"
mountpoint -q "$MOUNTPOINT" && fail "ALFS build mountpoint is already mounted"
sudo mount --bind "$TARGET_DIR" "$MOUNTPOINT"
cleanup_alfs_mount() { mountpoint -q "$MOUNTPOINT" && sudo umount "$MOUNTPOINT"; }
trap cleanup_alfs_mount EXIT
cat > "$JHALFS_DIR/configuration" <<EOF
BOOK_LFS_ANY="y"
BOOK_LFS_SYSD="y"
INITSYS="systemd"
WORKING_COPY="y"
BOOK="$MLFS_DIR"
COMMIT="$MLFS_COMMIT"
LFS_MULTILIB_I686="y"
MULTILIB="ml_32"
BUILD_CHROOT="y"
METHOD="chroot"
BLFS_TOOL="n"
CUSTOM_TOOLS="n"
LUSER="lfs"
LGROUP="lfs"
LHOME="/home"
BUILDDIR="$BUILDDIR"
GETPKG="n"
RUNMAKE="n"
CLEAN="n"
ALL_CORES="n"
N_PARALLEL="2"
REALSBU="n"
CONFIG_TESTS="n"
TEST="0"
KEEPDIR="n"
TEST_MISMATCH="n"
PKGMNGT="n"
WRAP_INSTALL="n"
INSTALL_LOG="y"
STRIP="n"
NO_PROGRESS_BAR="y"
HAVE_FSTAB="n"
FSTAB=""
CONFIG_BUILD_KERNEL="n"
CONFIG=""
NCURSES5="n"
TIMEZONE="Etc/UTC"
LANG="en_US.UTF-8"
FULL_LOCALE="n"
PAGE="letter"
HOSTNAME="barelinux"
INTERFACE="eth0"
IP_ADDR="10.0.2.15"
GATEWAY="10.0.2.2"
PREFIX="24"
BROADCAST="10.0.2.255"
DOMAIN="barelinux.local"
DNS1="10.0.2.3"
DNS2="8.8.8.8"
FONT="lat0-16"
KEYMAP="us"
LOCAL="n"
LOG_LEVEL="4"
OPTIMIZE="0"
REPORT="y"
SAVE_CH5="n"
COMPARE="n"
RUN_ICA="n"
REBUILD_MAKEFILE="n"
SCRIPT_ROOT="jhalfs"
JHALFSDIR="$JHALFS_BUILD_DIR"
LOGDIRBASE="logs"
LOGDIR="$JHALFS_BUILD_DIR/logs"
TESTLOGDIRBASE="test-logs"
TESTLOGDIR="$JHALFS_BUILD_DIR/test-logs"
FILELOGDIRBASE="installed-files"
FILELOGDIR="$JHALFS_BUILD_DIR/installed-files"
ICALOGDIR="$JHALFS_BUILD_DIR/logs/ICA"
MKFILE="$JHALFS_BUILD_DIR/Makefile"
XSL="lfs.xsl"
PKG_LST="unpacked"
DEL_LA_FILES="y"
EOF

log "Running the pinned jhalfs configuration and Makefile generator"
(
  cd "$JHALFS_DIR"
  printf 'yes\nyes\n' | ./jhalfs run
)
[[ -s "$JHALFS_BUILD_DIR/Makefile" ]] || fail "jhalfs did not generate its orchestration Makefile"
[[ -d "$JHALFS_BUILD_DIR/lfs-commands" ]] || fail "jhalfs did not generate its command tree"
COMMAND_COUNT="$(find "$JHALFS_BUILD_DIR/lfs-commands" -type f | wc -l | tr -d ' ')"
(( COMMAND_COUNT > 0 )) || fail "jhalfs generated no package command scripts"
find "$JHALFS_BUILD_DIR/lfs-commands" -type f -print | sort > "$AUDIT/generated-command-inventory.txt"
grep -RIl -E -- '-m32|/usr/lib32|lib32|32-bit' "$JHALFS_BUILD_DIR/lfs-commands" > "$AUDIT/generated-multilib-command-files.txt" || true
[[ -s "$AUDIT/generated-multilib-command-files.txt" ]] || fail "jhalfs-generated scripts contain no recognizable i686 multilib commands"
cp "$JHALFS_BUILD_DIR/prbook.xml" "$AUDIT/prbook.xml"
cp "$JHALFS_BUILD_DIR/Makefile" "$AUDIT/jhalfs-Makefile"

log "Archiving generated command scripts for semantic review"
tar -C "$JHALFS_BUILD_DIR" -cJf "$AUDIT/generated-commands.tar.xz" lfs-commands
log "Writing source and compatibility report"
python3 - "$AUDIT/source-audit.json" "$MLFS_DIR" "$JHALFS_DIR" "$MLFS_RESOLVED" "$JHALFS_RESOLVED" "$XML_COUNT" "$XSL_COUNT" "$COMMAND_COUNT" <<'PY'
import json, pathlib, subprocess, sys
out, mlfs, jhalfs, mlfs_sha, jhalfs_sha, xml_count, xsl_count, command_count = sys.argv[1:]
def git(path, *args):
    return subprocess.check_output(["git", "-C", path, *args], text=True).strip()
data = {
    "audit_schema": 2,
    "mlfs": {
        "repository": "https://git.linuxfromscratch.org/lfs.git",
        "ref": "multilib",
        "resolved_commit": mlfs_sha,
        "commit_date": git(mlfs, "show", "-s", "--format=%cI", "HEAD"),
        "xml_file_count": int(xml_count),
        "xsl_file_count": int(xsl_count),
    },
    "jhalfs": {
        "repository": "https://git.linuxfromscratch.org/jhalfs.git",
        "mirror": "https://github.com/lfs-book/jhalfs.git",
        "resolved_commit": jhalfs_sha,
        "commit_date": git(jhalfs, "show", "-s", "--format=%cI", "HEAD"),
        "subject": git(jhalfs, "show", "-s", "--format=%s", "HEAD"),
    },
    "adapter_mode": {
        "book_source": "local raw MLFS checkout",
        "init_system": "systemd",
        "multilib_profile": "ml_32 (x86_64 + i686)",
        "orchestrator": "pinned jhalfs run + generated Makefile",
        "generated_command_count": int(command_count),
    },
    "compatibility_status": "JHALFS_MAKEFILE_GENERATION_PASSED_REVIEW_REQUIRED",
    "package_builds_executed": False,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n")
PY
{
  printf 'MLFS repository: %s\nMLFS ref: %s\nMLFS resolved commit: %s\n' "$MLFS_REPOSITORY" "$MLFS_REF" "$MLFS_RESOLVED"
  printf 'jhalfs repository: %s\njhalfs pinned commit: %s\n' "$JHALFS_REPOSITORY" "$JHALFS_RESOLVED"
  printf 'XML files: %s\nXSL/XSLT files: %s\n' "$XML_COUNT" "$XSL_COUNT"
  printf 'Generated command scripts: %s\n' "$COMMAND_COUNT"
  printf 'Compatibility status: pinned jhalfs generated its Makefile and command graph; package builds and semantic review remain outstanding.\n'
  printf 'No package build was executed.\n'
} > "$AUDIT/REPORT.txt"

log "PASS: pinned jhalfs generated its orchestration Makefile and command graph from raw MLFS"
log "NOTE: package execution remains gated until the generated graph and host isolation are reviewed"
