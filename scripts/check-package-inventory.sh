#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/sources/manifests/mlfs-13.1-package-inventory.tsv"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] || fail "Missing MLFS 13.1 package inventory"

awk -F '\t' '
    /^#/ || NF == 0 { next }
    $1 == "package" {
        if (NF != 4 || $2 != "version" || $3 != "build_stage" || $4 != "barelinux_policy") {
            print "ERROR: invalid package inventory header" > "/dev/stderr"
            exit 1
        }
        header = 1
        next
    }
    {
        if (!header) {
            print "ERROR: package inventory header is missing" > "/dev/stderr"
            exit 1
        }
        if (NF != 4 || $1 !~ /^[a-z0-9+-]+$/ || $2 == "" || $3 == "" || $4 == "") {
            printf "ERROR: malformed package inventory row %d\n", NR > "/dev/stderr"
            exit 1
        }
        if ($1 in seen) {
            printf "ERROR: duplicate package: %s\n", $1 > "/dev/stderr"
            exit 1
        }
        seen[$1] = 1
        count++
    }
    END {
        if (!header) {
            print "ERROR: package inventory header is missing" > "/dev/stderr"
            exit 1
        }
        if (count < 80) {
            printf "ERROR: expected at least 80 package records, found %d\n", count > "/dev/stderr"
            exit 1
        }
        printf "BareLinux MLFS 13.1 package inventory: OK (%d unique records)\n", count
    }
' "$MANIFEST"
