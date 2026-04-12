#!/usr/bin/env bash
# Run rewrite_history.sh on every git repo found under a root directory.
# Repos whose origin remote doesn't match a known profile are skipped.
#
# Usage:
#   rewrite_history_all.sh [--root DIR] [--author PATTERN]... [--yes] [--push]
#
# Options:
#   --root DIR       Root directory to scan (default: .)
#   --author PATTERN Match pattern for author/committer (regex). Repeatable. Optional.
#   --yes            Apply changes (default: dry-run)
#   --push           Force-push rewritten history to remote after rewrite (default: do not push)
#   -h, --help       Show help

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REWRITE="${SCRIPT_DIR}/rewrite_history.sh"

[[ -x "$REWRITE" ]] || { echo "rewrite_history.sh not found or not executable in: $SCRIPT_DIR" >&2; exit 2; }

ROOT="."
APPLY=0
DO_PUSH=0
AUTHOR_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="${2:?--root requires a value}"; shift 2 ;;
    --author) AUTHOR_ARGS+=(--author "${2:?--author requires a value}"); shift 2 ;;
    --yes)    APPLY=1; shift ;;
    --push)   DO_PUSH=1; shift ;;
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

# Find all repos (same logic as switch_github_remotes_to_ssh.sh)
mapfile -d '' -t git_entries < <(
  {
    find "$ROOT" -type d -name .git -prune -print0 2>/dev/null
    find "$ROOT" -type f -name .git -print0 2>/dev/null
  }
)

if [[ ${#git_entries[@]} -eq 0 ]]; then
  echo "No git repositories found under: $ROOT"
  exit 0
fi

repos=()
for entry in "${git_entries[@]}"; do
  repos+=("${entry%/.git}")
done
mapfile -d '' -t repos < <(printf '%s\0' "${repos[@]}" | sort -z -u)

ok_count=0
skip_count=0
fail_count=0
dirty_count=0
total_start=$(date +%s%3N)

for repo in "${repos[@]}"; do
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    continue
  fi

  # Skip submodules (.git is a file, not a directory)
  if [[ -f "$repo/.git" ]]; then
    printf '[SKIP] %s  (submodule)\n' "$repo"
    ((skip_count+=1))
    continue
  fi

  remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
  if [[ -z "${remote_url:-}" ]]; then
    printf '[SKIP] %s  (no origin remote)\n' "$repo"
    ((skip_count+=1))
    continue
  fi

  if ! remote_is_known "$remote_url"; then
    printf '[SKIP] %s  (remote not matched: %s)\n' "$repo" "$remote_url"
    ((skip_count+=1))
    continue
  fi

  # Check dirty working tree upfront so we can report cleanly
  if ! git -C "$repo" diff --quiet 2>/dev/null || ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
    printf '[DIRTY] %s  (stash or commit changes first)\n' "$repo"
    ((dirty_count+=1))
    continue
  fi

  args=(--repo "$repo" "${AUTHOR_ARGS[@]}")
  [[ $APPLY -eq 1 ]] && args+=(--yes)
  [[ $DO_PUSH -eq 1 ]] && args+=(--push)

  repo_start=$(date +%s%3N)
  if "$REWRITE" "${args[@]}"; then
    ((ok_count+=1))
  else
    printf '[FAIL] %s\n' "$repo"
    ((fail_count+=1))
  fi
  printf '  time: %dms\n' "$(( $(date +%s%3N) - repo_start ))"

  printf '%s\n' "---"
done

total_ms=$(( $(date +%s%3N) - total_start ))

printf '\nSummary\n'
printf '  Rewritten : %d\n' "$ok_count"
printf '  Skipped   : %d\n' "$skip_count"
printf '  Dirty     : %d\n' "$dirty_count"
printf '  Failed    : %d\n' "$fail_count"
printf '  Total time: %dms\n' "$total_ms"

if [[ $APPLY -eq 0 ]]; then
  printf '\n(dry-run — use --yes to apply)\n'
fi
