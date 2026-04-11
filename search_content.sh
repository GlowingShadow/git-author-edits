#!/usr/bin/env bash
# Search file contents across the entire git history of a repo for a text pattern.
# Reports every file (in any commit) that contains the pattern.
#
# Usage:
#   search_content.sh [--repo DIR] --pattern REGEX [--pattern REGEX]... [--out-files FILE] [--case-sensitive]
#
# Options:
#   --repo DIR         Target repository (default: .)
#   --pattern REGEX    Regex to search for in file contents (repeatable, required)
#                      Multiple patterns are joined with | (OR)
#   --out-files FILE   Write matched file paths to FILE (one per line)
#   --case-sensitive   Match case (default: case-insensitive)
#   -h, --help         Show this help
#
# Examples:
#   search_content.sh --repo ./npuzzle --pattern "REDACTED"
#   search_content.sh --repo ./myrepo --pattern "REDACTED|REDACTED|REDACTED" --out-files matched.txt
#   search_content.sh --repo ./myrepo --pattern "password" --pattern "secret" --out-files matched.txt

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

REPO="."
PATTERNS=()
CASE_FLAG=-i
OUT_FILES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           REPO="${2:?--repo requires a value}"; shift 2 ;;
    --pattern)        PATTERNS+=("${2:?--pattern requires a value}"); shift 2 ;;
    --out-files)      OUT_FILES="${2:?--out-files requires a value}"; shift 2 ;;
    --case-sensitive) CASE_FLAG=""; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ ${#PATTERNS[@]} -gt 0 ]] || { echo "Error: at least one --pattern is required" >&2; usage >&2; exit 2; }
[[ -d "$REPO/.git" ]] || { echo "Error: not a git repository: $REPO" >&2; exit 2; }

# Join multiple patterns with | into a single extended regex
regex="$(IFS='|'; echo "${PATTERNS[*]}")"

echo "Repository : $REPO"
echo "Regex      : $regex"
[[ -n "$OUT_FILES" ]] && echo "Out files  : $OUT_FILES"
echo ""

[[ -n "$OUT_FILES" ]] && > "$OUT_FILES"

# git grep -E searches across all commits in history
# -l lists only file names, --all-match across all branches/tags
git_grep_flags=(-E --all -l)
[[ -n "$CASE_FLAG" ]] && git_grep_flags+=(-i)

match_count=0

while IFS= read -r path; do
  echo "=== $path ==="
  git -C "$REPO" grep -E -n ${CASE_FLAG:+-i} "$regex" HEAD -- "$path" 2>/dev/null \
    | head -20 || true
  echo ""
  [[ -n "$OUT_FILES" ]] && echo "$path" >> "$OUT_FILES"
  ((match_count+=1))
done < <(
  git -C "$REPO" grep "${git_grep_flags[@]}" "$regex" \
    $(git -C "$REPO" rev-list --all) 2>/dev/null \
    | sed 's/^[^:]*://' \
    | sort -u
)

if [[ $match_count -eq 0 ]]; then
  echo "No matches found."
else
  echo "==> $match_count file(s) matched."
  [[ -n "$OUT_FILES" ]] && echo "    File list written to: $OUT_FILES"
fi
