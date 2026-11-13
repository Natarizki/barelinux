#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/sources/manifests/mlfs-13.1-patches.tsv"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$MANIFEST" ]] || fail "Missing MLFS 13.1 patch inventory"

awk -F '\t' '
    /^#/ || NF == 0 { next }
    $1 == "package" {
        if (NF != 6 || $2 != "patch_name" || $3 != "archive_url" ||
            $4 != "book_md5" || $5 != "sha256" || $6 != "policy") {
            print "ERROR: invalid patch inventory header" > "/dev/stderr"
            exit 1
        }
        header = 1
        next
    }
    {
        if (!header || NF != 6 || $1 !~ /^[a-z0-9+-]+$/ ||
            $2 !~ /^[A-Za-z0-9._+-]+$/ || $3 !~ /^https:\/\// ||
            $4 !~ /^[[:xdigit:]]{32}$/ ||
            ($5 != "-" && $5 !~ /^[[:xdigit:]]{64}$/) ||
            $6 !~ /^[a-z0-9-]+$/) {
            printf "ERROR: malformed patch inventory row %d\n", NR > "/dev/stderr"
            exit 1
        }
        key = $1 SUBSEP $2
        if (key in seen) {
            printf "ERROR: duplicate patch record: %s / %s\n", $1, $2 > "/dev/stderr"
            exit 1
        }
        seen[key] = 1
        count++
        if ($5 == "-") missing++
    }
    END {
        if (!header || count != 9) {
            printf "ERROR: expected header and 9 patch records, found %d\n", count > "/dev/stderr"
            exit 1
        }
        printf "BareLinux MLFS 13.1 patch inventory: OK (%d records; %d SHA-256 values pending)\n", count, missing
    }
' "$MANIFEST"
