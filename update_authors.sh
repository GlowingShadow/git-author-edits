#!/usr/bin/env bash
# List all unique author/committer identities across all git repos under a
# root directory and write results to two files:
#   list_authors.txt        — grouped by repo
#   list_authors_unique.txt — globally sorted unique entries
#
# Usage:
#   update_authors.sh [--root DIR] [--out FILE] [--out-unique FILE]
#
# Options:
#   --root DIR         Root directory to scan (default: .)
#   --out FILE         Per-repo output file (default: list_authors.txt)
#   --out-unique FILE  Global unique output file (default: list_authors_unique.txt)
#   -h, --help         Show this help

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST_SCRIPT="${SCRIPT_DIR}/list_authors.sh"

[[ -x "$LIST_SCRIPT" ]] || { echo "list_authors.sh not found or not executable in: $SCRIPT_DIR" >&2; exit 2; }

ROOT="."
OUT="list_authors.txt"
OUT_UNIQUE="list_authors_unique.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)       ROOT="${2:?--root requires a value}"; shift 2 ;;
    --out)        OUT="${2:?--out requires a value}"; shift 2 ;;
    --out-unique) OUT_UNIQUE="${2:?--out-unique requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "Directory not found: $ROOT" >&2; exit 2; }

echo "Scanning: $ROOT"
"$LIST_SCRIPT" "$ROOT" > "$OUT"

# Extract all identity lines (indented), strip leading spaces, sort unique
grep -E '^\s+\S' "$OUT" | sed 's/^[[:space:]]*//' | sort -u > "$OUT_UNIQUE"

total=$(wc -l < "$OUT_UNIQUE")
echo "Written : $OUT"
echo "Written : $OUT_UNIQUE  ($total unique identities)"
echo ""
cat "$OUT_UNIQUE"
