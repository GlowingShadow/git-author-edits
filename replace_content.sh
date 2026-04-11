#!/usr/bin/env bash
# Replace text patterns in all file contents across the entire git history.
# After rewrite, no checkout of any past commit will show the original text.
#
# Usage:
#   replace_content.sh [--repo DIR] --replace OLD==>NEW [--replace OLD==>NEW]... [--file FILE] [--yes]
#
# Options:
#   --repo DIR             Target repository (default: .)
#   --replace OLD==>NEW    Replacement rule (repeatable)
#   --file FILE            Text file with one OLD==>NEW rule per line
#   --yes                  Apply (default: dry-run)
#   -h, --help             Show this help
#
# At least one --replace or --file is required.
#
# Examples:
#   replace_content.sh --repo ./myrepo --replace "old==>new" --yes
#   replace_content.sh --repo ./myrepo --file replacements.txt --yes
#   replace_content.sh --repo ./myrepo --replace "oldname==>newname" --replace "old@email.com==>new@email.com" --yes

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

REPO="."
RULES=()
FILE_LIST=""
DRY_RUN=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO="${2:?--repo requires a value}"; shift 2 ;;
    --replace) RULES+=("${2:?--replace requires a value}"); shift 2 ;;
    --file)    FILE_LIST="${2:?--file requires a value}"; shift 2 ;;
    --yes)     DRY_RUN=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Load rules from file if provided
if [[ -n "$FILE_LIST" ]]; then
  [[ -f "$FILE_LIST" ]] || { echo "Error: file not found: $FILE_LIST" >&2; exit 2; }
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    RULES+=("$line")
  done < "$FILE_LIST"
fi

[[ ${#RULES[@]} -gt 0 ]] || { echo "Error: at least one --replace or --file is required" >&2; usage >&2; exit 2; }
[[ -d "$REPO/.git" ]] || { echo "Error: not a git repository: $REPO" >&2; exit 2; }

command -v git-filter-repo >/dev/null 2>&1 || { echo "Error: git-filter-repo is required" >&2; exit 2; }

echo "Repository : $REPO"
[[ -n "$FILE_LIST" ]] && echo "File list  : $FILE_LIST"
echo "Rules      :"
printf '  %s\n' "${RULES[@]}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would apply the above replacements across entire history."
  echo "          Re-run with --yes to apply."
  exit 0
fi

# Write rules to a temp file for filter-repo
tmp_rules="$(mktemp)"
printf '%s\n' "${RULES[@]}" > "$tmp_rules"

# Save remote URL before filter-repo removes it
remote_url="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"

echo "==> Replacing content in history..."
git -C "$REPO" filter-repo --replace-text "$tmp_rules" --force
rm -f "$tmp_rules"

# Restore remote
if [[ -n "$remote_url" ]]; then
  ssh_url="$(echo "$remote_url" | sed -E 's|https://github.com/([^/]+)/(.+)|git@github.com:\1/\2|')"
  git -C "$REPO" remote add origin "$ssh_url"
  echo "==> Remote restored: $ssh_url"
fi

echo ""
echo "==> Force-pushing rewritten history..."
git -C "$REPO" push --force --all
git -C "$REPO" push --force --tags

echo ""
echo "Done. Replacements applied to all commits and pushed."
