#!/usr/bin/env bash
# List all unique author/committer names and emails from all commits on all
# branches in every git repository found under a root directory.
#
# Usage:
#   list_authors.sh [DIR]
#
# Arguments:
#   DIR   Root directory to scan (default: .)
#   -h, --help   Show this help

set -euo pipefail

ROOT="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown argument: $1" >&2; exit 2 ;;
    *) ROOT="$1"; shift ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "Directory not found: $ROOT" >&2; exit 2; }

while IFS= read -r gitdir; do
  repo="${gitdir%/.git}"
  # skip submodules (their .git is a file, not a directory)
  [[ -f "$repo/.git" ]] && continue

  # Collect unique name+email combos from all branches (author + committer)
  mapfile -t identities < <(git -C "$repo" log --all \
    --format="%aN <%aE>%n%cN <%cE>" 2>/dev/null | sort -u)

  [[ ${#identities[@]} -eq 0 ]] && continue

  echo "=== $repo ==="
  for entry in "${identities[@]}"; do
    [[ -n "$entry" ]] && echo "  $entry"
  done
  echo ""

done < <(find "$ROOT" -type d -name .git -prune -print 2>/dev/null | sort)
