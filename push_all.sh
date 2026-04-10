#!/usr/bin/env bash
# Force-push all branches and tags for every git repo under a root directory.
# Optionally cleans up refs/original/ backup refs left by rewrite_history.sh.
#
# Usage:
#   push_all.sh [--root DIR] [--clean-refs] [--yes]
#
# Options:
#   --root DIR      Root directory to scan (default: .)
#   --clean-refs    Also delete refs/original/ backup refs after pushing
#   --yes           Apply changes (default: dry-run)
#   -h, --help      Show this help
#
# Notes:
#   - Repos with no 'origin' remote are skipped.
#   - Only repos whose origin matches a known SSH alias are pushed.
#     Aliases are auto-discovered from ~/.gitconfig includeIf blocks.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

ROOT="."
APPLY=0
CLEAN_REFS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)       ROOT="${2:?--root requires a value}"; shift 2 ;;
    --clean-refs) CLEAN_REFS=1; shift ;;
    --yes)        APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT" ]] || { echo "Directory not found: $ROOT" >&2; exit 2; }

# shellcheck source=lib_profiles.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib_profiles.sh"
declare -A PROFILES
load_git_profiles || exit 2

ok_count=0
skip_count=0
fail_count=0

while IFS= read -r repo; do
  remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  if [[ -z "${remote_url:-}" ]]; then
    printf '[SKIP]  %s  (no origin remote)\n' "$repo"
    ((skip_count+=1))
    continue
  fi

  # Only push repos on known profiles
  if ! remote_is_known "$remote_url"; then
    printf '[SKIP]  %s  (remote not matched: %s)\n' "$repo" "$remote_url"
    ((skip_count+=1))
    continue
  fi

  # Check for backup refs
  backup_count=$(git -C "$repo" for-each-ref --format='%(refname)' refs/original/ 2>/dev/null | wc -l)

  printf '[PUSH]  %s\n  remote: %s\n' "$repo" "$remote_url"
  [[ $backup_count -gt 0 ]] && printf '  backup refs: %d\n' "$backup_count"

  if [[ $APPLY -eq 0 ]]; then
    echo "  dry-run (pass --yes to apply)"
    continue
  fi

  if git -C "$repo" push --force --all && git -C "$repo" push --force --tags; then
    ((ok_count+=1))

    if [[ $CLEAN_REFS -eq 1 && $backup_count -gt 0 ]]; then
      git -C "$repo" for-each-ref --format='%(refname)' refs/original/ \
        | while IFS= read -r ref; do
            git -C "$repo" update-ref -d "$ref"
          done
      printf '  cleaned %d backup refs\n' "$backup_count"
    fi
  else
    printf '[FAIL]  %s\n' "$repo"
    ((fail_count+=1))
  fi

done < <(find "$ROOT" -type d -name .git -prune -print 2>/dev/null | sed 's#/.git$##' | sort)

echo ""
echo "Summary"
printf '  Pushed  : %d\n' "$ok_count"
printf '  Skipped : %d\n' "$skip_count"
[[ $fail_count -gt 0 ]] && printf '  Failed  : %d\n' "$fail_count"
[[ $APPLY -eq 0 ]] && echo "(dry-run — rerun with --yes to apply)"
