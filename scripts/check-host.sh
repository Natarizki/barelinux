#!/usr/bin/env bash
set -euo pipefail

failures=0
missing=()

required=(bash ld bison sort diff find gawk gcc g++ grep gzip m4 make patch perl python3 sed tar texi2any xz uname mount nproc)
for cmd in "${required[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'MISSING: %s\n' "$cmd" >&2
        missing+=("$cmd")
        failures=1
    else
        printf 'FOUND:   %s\n' "$cmd"
    fi
done

if [[ "$(uname -s)" != Linux ]]; then
    printf 'ERROR: MLFS build host must run Linux\n' >&2
    failures=1
fi

kernel="$(uname -r | grep -oE '^[0-9]+(\.[0-9]+)+' || true)"
if [[ -z "$kernel" ]] || ! printf '%s\\n' 5.4 "$kernel" | sort -V -C; then
    printf 'ERROR: host kernel must be Linux 5.4 or newer (found: %s)\n' "${kernel:-unknown}" >&2
    failures=1
else
    printf 'OK: host kernel %s\n' "$kernel"
fi

if [[ ! -e /dev/ptmx ]] || ! mount | grep -qE 'devpts on /dev/pts'; then
    printf 'ERROR: UNIX 98 PTY support (/dev/ptmx and devpts) is unavailable\n' >&2
    failures=1
else
    printf 'OK: UNIX 98 PTY support\n'
fi

if ! awk --version 2>&1 | grep -qi 'GNU Awk'; then
    printf 'ERROR: awk must resolve to GNU Awk\n' >&2
    failures=1
fi
if ! yacc --version 2>&1 | grep -qi 'bison'; then
    printf 'ERROR: yacc must resolve to Bison\n' >&2
    failures=1
fi
if ! sh --version 2>&1 | grep -qi 'bash'; then
    printf 'ERROR: /bin/sh must resolve to Bash for the MLFS procedure\n' >&2
    failures=1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
if printf 'int main() { return 0; }\n' | g++ -x c++ - -o "$tmpdir/host-cxx-test"; then
    printf 'OK: host C++ compiler can build a hosted executable\n'
else
    printf 'ERROR: host g++ cannot build a hosted executable\n' >&2
    failures=1
fi

if (( failures != 0 )); then
    printf '\nHOST PREREQUISITE CHECK: FAILED\n' >&2
    if (("${#missing[@]}" > 0)); then
        printf 'Missing commands: %s\n' "${missing[*]}" >&2
    fi
    exit 1
fi

printf '\nHOST PREREQUISITE CHECK: PASSED\n'
printf 'NOTE: this checks the build host only; it does not build the MLFS toolchain.\n'
