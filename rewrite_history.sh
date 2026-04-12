#!/usr/bin/env bash
# Rewrite all commits (all branches + tags) in a single repo to stamp the
# correct identity based on the remote URL.
# Profiles are auto-discovered from ~/.gitconfig includeIf blocks, e.g.:
#   [includeIf "hasconfig:remote.*.url:git@gitcustom:*/**"]
#       path = ~/.gitconfig-custom
#
# Timestamps and file contents are untouched. Only author/committer metadata.
# Only commits whose author/committer matches --author patterns are rewritten.
# Branch/tag tips are backed up under refs/original/ before rewriting.
#
# Usage:
#   rewrite_history.sh [--repo DIR] [--author PATTERN]... [--yes] [--push]
#   rewrite_history.sh [--repo DIR] --restore [--yes]
#
# Options:
#   --repo DIR       Git repository to rewrite (default: .)
#   --author PATTERN Match pattern for author/committer name or email (regex). Repeatable. Optional — rewrites all commits if omitted.
#   --restore        Restore original history from refs/original/ backup
#   --yes            Apply changes (default: dry-run)
#   --push           Force-push rewritten history to remote after rewrite (default: do not push)
#   -h, --help       Show help

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

REPO="."
APPLY=0
RESTORE=0
DO_PUSH=0
AUTHOR_PATTERNS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="${2:?--repo requires a value}"; shift 2 ;;
    --author)  AUTHOR_PATTERNS+=("${2:?--author requires a value}"); shift 2 ;;
    --restore) RESTORE=1; shift ;;
    --yes)     APPLY=1; shift ;;
    --push)    DO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Build the match pattern from --author args (matches all if none given)
if [[ ${#AUTHOR_PATTERNS[@]} -eq 0 ]]; then
  MATCH_PATTERN='.'
else
  MATCH_PATTERN=$(IFS='|'; echo "${AUTHOR_PATTERNS[*]}")
fi

[[ -d "$REPO" ]] || { echo "Directory not found: $REPO" >&2; exit 2; }

# --- Restore mode ---
if [[ $RESTORE -eq 1 ]]; then
  mapfile -t originals < <(git -C "$REPO" for-each-ref --format='%(refname)' refs/original/ 2>/dev/null || true)

  if [[ ${#originals[@]} -eq 0 ]]; then
    echo "No refs/original/ backup found in: $REPO"
    exit 0
  fi

  echo "Repo   : $REPO"
  echo "Backup refs found: ${#originals[@]}"

  for ref in "${originals[@]}"; do
    target="${ref#refs/original/}"
    echo "  $ref  ->  $target"
    git -C "$REPO" update-ref "$target" "$ref"
    git -C "$REPO" update-ref -d "$ref"
    echo "  restored: $target"
  done

  # Reset HEAD of current branch to match the restored ref
  if [[ $DO_PUSH -eq 1 ]]; then
    echo "Force-pushing rewritten history to remote..."
    git -C "$REPO" push --force --all
    git -C "$REPO" push --force --tags
    echo "Push complete."
  else
    echo "To force-push manually, run:"
    echo "  git -C \"$REPO\" push --force --all"
    echo "  git -C \"$REPO\" push --force --tags"
  fi

  git -C "$REPO" reset --hard HEAD
  echo ""
  echo "Done. History restored from backup."
  exit 0
fi


# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib_profiles.sh"
declare -A PROFILES
load_git_profiles || exit 2

# --- Rewrite mode ---
  if [[ $DO_PUSH -eq 1 ]]; then
    echo "Force-pushing rewritten history to remote..."
    git -C "$REPO" push --force --all
    git -C "$REPO" push --force --tags
    echo "Push complete."
  else
    echo "To force-push manually, run:"
    echo "  git -C \"$REPO\" push --force --all"
    echo "  git -C \"$REPO\" push --force --tags"
  fi
# Resolve identity from origin remote URL
remote_url=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
if [[ -z "${remote_url:-}" ]]; then
  echo "No 'origin' remote found in: $REPO" >&2
  exit 2
fi

NEW_NAME="" NEW_EMAIL=""
if ! profile_for_remote "$remote_url" NEW_NAME NEW_EMAIL; then
  echo "Remote URL not matched to any profile: $remote_url" >&2
  printf '  Known aliases: %s\n' "${!PROFILES[*]}" >&2
  exit 2
fi

# Count commits whose author or committer matches the pattern
changed=$(git -C "$REPO" log --all --format="%ae|%an|%ce|%cn" \
  | grep -ciE "$MATCH_PATTERN" || true)

echo "Repo   : $REPO"
echo "Remote : $remote_url"
echo "Profile: $NEW_NAME <$NEW_EMAIL>"
echo "Commits to rewrite: $changed"
echo ""

if [[ $APPLY -eq 0 ]]; then
  echo "(dry-run — use --yes to apply)"
  exit 0
fi

if [[ "$changed" -eq 0 ]]; then
  echo "Nothing to do, all commits already use the correct identity."
  exit 0
fi

# git-filter-repo requires a clean working tree
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
  echo "Working tree is dirty. Stash or commit your changes first:" >&2
  git -C "$REPO" status --short >&2
  exit 1
fi

# Backup all branch and tag tips under refs/original/ (same layout as filter-branch)
# so --restore works identically.
while IFS= read -r ref; do
  git -C "$REPO" update-ref "refs/original/${ref}" "$ref"
done < <(git -C "$REPO" for-each-ref --format='%(refname)' refs/heads/ refs/tags/ 2>/dev/null)

# Write conditional commit callback to a temp file
CB_FILE=$(mktemp /tmp/filter_callback_XXXXXX.py)
trap 'rm -f "$CB_FILE"' EXIT
cat > "$CB_FILE" << PYEOF
import re
_PAT = re.compile(b'${MATCH_PATTERN}', re.IGNORECASE)
_NAME = b'${NEW_NAME}'
_EMAIL = b'${NEW_EMAIL}'
def _m(v): return bool(_PAT.search(v))
if _m(commit.author_email) or _m(commit.author_name):
    commit.author_name = _NAME
    commit.author_email = _EMAIL
if _m(commit.committer_email) or _m(commit.committer_name):
    commit.committer_name = _NAME
    commit.committer_email = _EMAIL
PYEOF

# Rewrite with git-filter-repo (must run from inside the repo)
(
  cd "$REPO"
  git filter-repo --force --partial \
    --commit-callback "$(cat "$CB_FILE")"
)

echo ""
echo "Done."
echo ""
echo "Original refs backed up under refs/original/ — clean up with:"
echo "  git -C \"$REPO\" for-each-ref --format='%(refname)' refs/original/ \\"
echo "    | xargs -r git -C \"$REPO\" update-ref -d"
echo ""
echo "Force-push with:"
echo "  git -C \"$REPO\" push --force --all"
echo "  git -C \"$REPO\" push --force --tags"
