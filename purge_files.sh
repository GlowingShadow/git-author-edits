#!/usr/bin/env bash
# Remove all files matching a glob pattern from a repo's entire git history.
# The file is erased from every commit — no checkout can recover it.
#
# Usage:
#   purge_files.sh [--repo DIR] [--pattern GLOB]... [--file FILE] [--yes] [--push]
#
# Options:
#   --repo DIR       Target repository (default: .)
#   --pattern GLOB   Glob path pattern to purge (repeatable)
#   --file FILE      Text file with one path or glob per line to purge
#   --yes            Apply (default: dry-run)
#   --push           Force-push rewritten history to remote after rewrite (default: do not push)
#   -h, --help       Show this help
#
# At least one --pattern or --file is required.
#
# Examples:
#   purge_files.sh --repo ./npuzzle --pattern "*.swp" --yes
#   purge_files.sh --repo ./myrepo --file matched_files.txt --yes
#   purge_files.sh --repo ./myrepo --file matched_files.txt --pattern "*.pem" --yes

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

REPO="."
PATTERNS=()
FILE_LIST=""

DRY_RUN=true
DO_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="${2:?--repo requires a value}"; shift 2 ;;
    --pattern) PATTERNS+=("${2:?--pattern requires a value}"); shift 2 ;;
    --file)    FILE_LIST="${2:?--file requires a value}"; shift 2 ;;
    --yes)     DRY_RUN=false; shift ;;
    --push)    DO_PUSH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Load paths from file if provided
if [[ -n "$FILE_LIST" ]]; then
  [[ -f "$FILE_LIST" ]] || { echo "Error: file not found: $FILE_LIST" >&2; exit 2; }
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    PATTERNS+=("$line")
  done < "$FILE_LIST"
fi

[[ ${#PATTERNS[@]} -gt 0 ]] || { echo "Error: at least one --pattern or --file is required" >&2; usage >&2; exit 2; }
[[ -d "$REPO/.git" ]] || { echo "Error: not a git repository: $REPO" >&2; exit 2; }

command -v git-filter-repo >/dev/null 2>&1 || { echo "Error: git-filter-repo is required" >&2; exit 2; }

echo "Repository : $REPO"
[[ -n "$FILE_LIST" ]] && echo "File list  : $FILE_LIST (${#PATTERNS[@]} entries)"
echo "Patterns   : ${PATTERNS[*]}"

# Show matching files currently tracked
echo ""
echo "Currently tracked files matching pattern(s):"
mapfile -t tracked < <(git -C "$REPO" ls-files -- "${PATTERNS[@]}" 2>/dev/null || true)
if [[ ${#tracked[@]} -gt 0 ]]; then
  printf '  %s\n' "${tracked[@]}"
else
  echo "  (none currently tracked — may still exist in history)"
fi

echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would purge the above pattern(s) from entire history."
  echo "          Re-run with --yes to apply."
  exit 0
fi

# Save remote URL before filter-repo removes it
remote_url="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"

# Write patterns to a temp file for --paths-from-file (prefix with glob: for glob support)
tmp_paths="$(mktemp)"
for pattern in "${PATTERNS[@]}"; do
  echo "glob:$pattern"
done > "$tmp_paths"

echo "==> Purging from history..."
git -C "$REPO" filter-repo --invert-paths --paths-from-file "$tmp_paths" --force
rm -f "$tmp_paths"

# Restore remote
if [[ -n "$remote_url" ]]; then
  # Switch to SSH if it's an HTTPS GitHub URL
  ssh_url="$(echo "$remote_url" | sed -E 's|https://github.com/([^/]+)/(.+)|git@github.com:\1/\2|')"
  git -C "$REPO" remote add origin "$ssh_url"
  echo "==> Remote restored: $ssh_url"
fi

echo ""
echo "Done. Pattern(s) erased from all commits and pushed."
echo ""
if [[ "$DO_PUSH" == true ]]; then
  echo "==> Force-pushing rewritten history..."
  git -C "$REPO" push --force --all
  git -C "$REPO" push --force --tags
  echo ""
  echo "Done. Pattern(s) erased from all commits and pushed."
else
  echo "To force-push manually, run:"
  echo "  git -C \"$REPO\" push --force --all"
  echo "  git -C \"$REPO\" push --force --tags"
  echo ""
  echo "Done. Pattern(s) erased from all commits."
fi
