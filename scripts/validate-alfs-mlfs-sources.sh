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

for tool in git python3 grep find sort realpath; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing prerequisite: $tool"
done

LOCK="$ROOT_DIR/sources/locks/alfs-mlfs.lock"
[[ -f "$LOCK" ]] || fail "source lock missing"
# The lock contains fixed KEY=value records maintained in-repository.
# shellcheck disable=SC1090
source "$LOCK"
[[ "$JHALFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "invalid pinned jhalfs commit"
[[ "$MLFS_REF" == "multilib" ]] || fail "unexpected MLFS ref"
[[ "$MLFS_COMMIT" == "UNPINNED" || "$MLFS_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "invalid MLFS commit lock"

AUDIT="$WORKSPACE/audit"
MLFS_DIR="$WORKSPACE/mlfs"
JHALFS_DIR="$WORKSPACE/jhalfs"
[[ ! -e "$AUDIT" && ! -e "$MLFS_DIR" && ! -e "$JHALFS_DIR" ]] || fail "workspace already contains audit/source directories"
mkdir -p "$AUDIT"

log "Cloning raw MLFS source from the official multilib branch"
git clone --quiet --no-tags --single-branch --branch "$MLFS_REF" "$MLFS_REPOSITORY" "$MLFS_DIR"
MLFS_RESOLVED="$(git -C "$MLFS_DIR" rev-parse HEAD)"
if [[ "$MLFS_COMMIT" != "UNPINNED" && "$MLFS_RESOLVED" != "$MLFS_COMMIT" ]]; then
  fail "resolved MLFS commit $MLFS_RESOLVED differs from locked $MLFS_COMMIT"
fi

log "Cloning jhalfs and checking out the pinned ALFS revision"
git clone --quiet --no-checkout "$JHALFS_REPOSITORY" "$JHALFS_DIR"
git -C "$JHALFS_DIR" fetch --quiet --depth 1 origin "$JHALFS_COMMIT"
git -C "$JHALFS_DIR" checkout --quiet --detach "$JHALFS_COMMIT"
JHALFS_RESOLVED="$(git -C "$JHALFS_DIR" rev-parse HEAD)"
[[ "$JHALFS_RESOLVED" == "$JHALFS_COMMIT" ]] || fail "jhalfs checkout does not match pinned commit"

log "Checking raw MLFS book identity and multilib source material"
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

log "Inspecting jhalfs source layout without executing generated build commands"
JHALFS_FILES="$(find "$JHALFS_DIR" -maxdepth 3 -type f | sed "s#^$JHALFS_DIR/##" | sort)"
printf '%s\n' "$JHALFS_FILES" > "$AUDIT/jhalfs-file-inventory.txt"
[[ -s "$AUDIT/jhalfs-file-inventory.txt" ]] || fail "jhalfs checkout is empty"

python3 - "$AUDIT/source-audit.json" "$MLFS_DIR" "$JHALFS_DIR" "$MLFS_RESOLVED" "$JHALFS_RESOLVED" "$XML_COUNT" "$XSL_COUNT" <<'PY'
import json, pathlib, subprocess, sys
out, mlfs, jhalfs, mlfs_sha, jhalfs_sha, xml_count, xsl_count = sys.argv[1:]
def git(path, *args):
    return subprocess.check_output(["git", "-C", path, *args], text=True).strip()
data = {
    "audit_schema": 1,
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
        "resolved_commit": jhalfs_sha,
        "commit_date": git(jhalfs, "show", "-s", "--format=%cI", "HEAD"),
        "subject": git(jhalfs, "show", "-s", "--format=%s", "HEAD"),
    },
    "compatibility_status": "SOURCE_AUDIT_ONLY_NOT_PROVEN",
    "package_builds_executed": False,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n")
PY

{
  printf 'MLFS repository: %s\nMLFS ref: %s\nMLFS resolved commit: %s\n' "$MLFS_REPOSITORY" "$MLFS_REF" "$MLFS_RESOLVED"
  printf 'jhalfs repository: %s\njhalfs pinned commit: %s\n' "$JHALFS_REPOSITORY" "$JHALFS_RESOLVED"
  printf 'XML files: %s\nXSL/XSLT files: %s\n' "$XML_COUNT" "$XSL_COUNT"
  printf 'Compatibility status: SOURCE AUDIT ONLY; jhalfs has not yet generated MLFS recipes.\n'
  printf 'No package build was executed.\n'
} > "$AUDIT/REPORT.txt"

log "PASS: source repositories fetched and revision identities recorded"
log "NOTE: this does not yet prove that jhalfs can generate MLFS recipes"
