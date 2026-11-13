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

for tool in git python3 grep find sort realpath xsltproc sed wc tr; do
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

log "Preparing generated-command directories"
if [[ -f "$MLFS_DIR/process-scripts.sh" ]]; then
  (cd "$MLFS_DIR" && bash process-scripts.sh)
fi
if [[ -f "$MLFS_DIR/git-version.sh" ]]; then
  (cd "$MLFS_DIR" && bash git-version.sh systemd)
fi
mkdir -p "$AUDIT/commands"
for chapter in "$MLFS_DIR"/chapter[0-9][0-9]; do
  [[ -d "$chapter" ]] || continue
  mkdir -p "$AUDIT/commands/${chapter##*/}"
done

log "Profiling the raw MLFS book as systemd with legacy arch filtering disabled"
(
  cd "$AUDIT"
  xsltproc --nonet --xinclude \
    --stringparam profile.revision systemd \
    --stringparam profile.arch default \
    --output prbook.xml \
    "$MLFS_DIR/stylesheets/lfs-xsl/profile.xsl" "$MLFS_DIR/index.xml"
)
[[ -s "$AUDIT/prbook.xml" ]] || fail "jhalfs-compatible MLFS profile generation produced no XML"
grep -q 'chapter-cross-tools' "$AUDIT/prbook.xml" || fail "profiled MLFS book lacks cross-toolchain chapter"
grep -q 'chapter-building-system' "$AUDIT/prbook.xml" || fail "profiled MLFS book lacks final-system chapter"

log "Running the pinned jhalfs extraction stylesheet against profiled raw MLFS"
(
  cd "$AUDIT"
  xsltproc --nonet \
    --stringparam luser-lgroup lfs:lfs \
    --stringparam testsuite 1 \
    --stringparam keepdir n \
    --stringparam ncurses5 n \
    --stringparam strip n \
    --stringparam del-la-files y \
    --stringparam full-locale n \
    --stringparam timezone GMT \
    --stringparam page letter \
    --stringparam lang C \
    --stringparam pkgmngt-wrap nn \
    --stringparam hostname barelinux \
    --stringparam interface eth0 \
    --stringparam ip 10.0.2.15 \
    --stringparam gateway 10.0.2.2 \
    --stringparam prefix 24 \
    --stringparam broadcast 10.0.2.255 \
    --stringparam domain barelinux.local \
    --stringparam nameserver1 10.0.2.3 \
    --stringparam nameserver2 8.8.8.8 \
    --stringparam console lat0-16@us:n/4 \
    --stringparam script-root commands \
    --stringparam jobs 2 \
    --stringparam jobs-bp1 2 \
    --stringparam test-mismatch n \
    --output ./commands/ \
    "$JHALFS_DIR/LFS/lfs.xsl" prbook.xml
)
COMMAND_COUNT="$(find "$AUDIT/commands" -type f | wc -l | tr -d ' ')"
(( COMMAND_COUNT > 0 )) || fail "jhalfs generated no package command scripts"
find "$AUDIT/commands" -type f -print | sort > "$AUDIT/generated-command-inventory.txt"
grep -RIl -E -- '-m32|/usr/lib32|lib32|32-bit' "$AUDIT/commands" > "$AUDIT/generated-multilib-command-files.txt" || true
[[ -s "$AUDIT/generated-multilib-command-files.txt" ]] || fail "generated jhalfs scripts contain no recognizable MLFS multilib commands"

log "Archiving generated command scripts for semantic review"
tar -C "$AUDIT" -cJf "$AUDIT/generated-commands.tar.xz" commands
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
        "legacy_arch_profile": "default",
        "generated_command_count": int(command_count),
    },
    "compatibility_status": "JHALFS_XSLT_GENERATION_PASSED_REVIEW_REQUIRED",
    "package_builds_executed": False,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n")
PY
{
  printf 'MLFS repository: %s\nMLFS ref: %s\nMLFS resolved commit: %s\n' "$MLFS_REPOSITORY" "$MLFS_REF" "$MLFS_RESOLVED"
  printf 'jhalfs repository: %s\njhalfs pinned commit: %s\n' "$JHALFS_REPOSITORY" "$JHALFS_RESOLVED"
  printf 'XML files: %s\nXSL/XSLT files: %s\n' "$XML_COUNT" "$XSL_COUNT"
  printf 'Generated command scripts: %s\n' "$COMMAND_COUNT"
  printf 'Compatibility status: XSLT generation tested; package builds and generated-command semantic review remain outstanding.\n'
  printf 'No package build was executed.\n'
} > "$AUDIT/REPORT.txt"

log "PASS: jhalfs generated command scripts from raw MLFS"
log "NOTE: inspect generated scripts before enabling package builds"
