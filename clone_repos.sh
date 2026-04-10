#!/usr/bin/env bash
# Clone a list of git repositories into a target directory.
# Repos that are already cloned are skipped.
#
# Usage:
#   clone_repos.sh [--file FILE] [--dest DIR] [--yes]
#
# Options:
#   --file FILE   File containing one repo URL per line (default: repos.txt)
#   --dest DIR    Directory to clone into (default: .)
#   --yes         Clone immediately (default: dry-run / preview)
#   -h, --help    Show this help
#
# repos.txt format:
#   https://github.com/ACCOUNT/REPO
#   git@github.com:ACCOUNT/REPO.git
#   # lines starting with # are ignored

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

FILE="repos.txt"
DEST="."
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:?--file requires a value}"; shift 2 ;;
    --dest) DEST="${2:?--dest requires a value}"; shift 2 ;;
    --yes)  APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 2; }
[[ -d "$DEST" ]] || { echo "Destination not found: $DEST" >&2; exit 2; }

cloned=0
skipped=0
failed=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip inline comments and whitespace
  url="${line%%#*}"
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  [[ -z "$url" ]] && continue

  # Derive directory name from URL (strip .git suffix, take last path component)
  repo_name="${url##*/}"
  repo_name="${repo_name%.git}"
  dest_path="${DEST%/}/${repo_name}"

  if [[ -d "${dest_path}/.git" ]]; then
    printf '[SKIP]   %s  (already cloned at %s)\n' "$repo_name" "$dest_path"
    ((skipped+=1))
    continue
  fi

  printf '[CLONE]  %s\n  url : %s\n  dest: %s\n' "$repo_name" "$url" "$dest_path"

  if [[ $APPLY -eq 0 ]]; then
    echo "  dry-run (pass --yes to apply)"
    continue
  fi

  if git clone "$url" "$dest_path"; then
    ((cloned+=1))
  else
    printf '[FAIL]   %s\n' "$repo_name"
    ((failed+=1))
  fi
done < "$FILE"

echo ""
echo "Summary"
printf '  Cloned  : %d\n' "$cloned"
printf '  Skipped : %d\n' "$skipped"
[[ $failed -gt 0 ]] && printf '  Failed  : %d\n' "$failed"
[[ $APPLY -eq 0 ]] && echo "(dry-run — rerun with --yes to apply)"
