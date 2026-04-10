#!/usr/bin/env bash
# Rewrite GitHub remote URLs under a root directory.
# Can change host (https -> SSH alias) and/or account (owner name).
#
# Usage:
#   switch_remotes.sh [--root DIR] [--host HOST] [--account OLD:NEW] [--list] [--yes]
#
# Options:
#   --root DIR         Root directory to scan (default: .)
#   --host HOST        SSH host/alias to use (default: github.com)
#   --account OLD:NEW  Replace owner OLD with NEW in all remote URLs
#   --list             List remotes only; no changes
#   --yes              Apply changes (default: dry-run)
#   -h, --help         Show this help

set -euo pipefail

ROOT="."
HOST="github.com"
ACCOUNT_OLD=""
ACCOUNT_NEW=""
APPLY=0
LIST_ONLY=0
changed_count=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)    ROOT="$2"; shift 2 ;;
    --host)    HOST="$2"; shift 2 ;;
    --account)
      ACCOUNT_OLD="${2%%:*}"
      ACCOUNT_NEW="${2##*:}"
      [[ -n "$ACCOUNT_OLD" && -n "$ACCOUNT_NEW" ]] || { echo "--account requires OLD:NEW format" >&2; exit 2; }
      shift 2 ;;
    --list)    LIST_ONLY=1; shift ;;
    --yes)     APPLY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "Directory not found: $ROOT" >&2; exit 2; }

while IFS= read -r repo; do
  git -C "$repo" remote | while IFS= read -r remote; do
    old=$(git -C "$repo" remote get-url "$remote" 2>/dev/null) || continue

    if [[ $LIST_ONLY -eq 1 ]]; then
      printf '[%s] %s\n  %s\n' "$repo" "$remote" "$old"
      continue
    fi

    # 1. https -> SSH  (git@HOST:OWNER/REPO.git)
    new=$(printf '%s' "$old" \
      | sed -E "s#^https?://([^@/]+@)?github[.]com/([^/]+/[^/]+?)(\.git)?\$#git@${HOST}:\2.git#" \
      | sed -E "s#^git@github[.]com:([^/]+/[^/]+?)(\.git)?\$#git@${HOST}:\1.git#")

    # 2. Account rename: git@HOST:OLD/REPO.git -> git@HOST:NEW/REPO.git
    if [[ -n "$ACCOUNT_OLD" ]]; then
      new=$(printf '%s' "$new" \
        | sed -E "s#^(git@[^:]+:)${ACCOUNT_OLD}/(.+)\$#\1${ACCOUNT_NEW}/\2#")
    fi

    [[ "$old" == "$new" ]] && continue

    printf '[%s] %s\n  %s\n  -> %s\n' "$repo" "$remote" "$old" "$new"

    if [[ $APPLY -eq 1 ]]; then
      git -C "$repo" remote set-url "$remote" "$new"
      echo "  applied"
    else
      echo "  dry-run (pass --yes to apply)"
    fi
    ((changed_count+=1))
  done
done < <(find "$ROOT" -type d -name .git -prune -print 2>/dev/null | sed 's#/.git$##' | sort)

echo ""
echo "Summary"
printf '  Changed : %d\n' "$changed_count"
[[ $APPLY -eq 0 && $changed_count -gt 0 ]] && echo "(dry-run — rerun with --yes to apply)"
