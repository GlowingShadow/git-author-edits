#!/usr/bin/env bash
# List all public owned repos of a GitHub user, clone them, and print unique git authors.
#
# Usage:
#   check_user.sh --user USERNAME [--token TOKEN] [--dest DIR] [--keep]
#
# Options:
#   --user USERNAME  GitHub username to check (required)
#   --token TOKEN    GitHub personal access token (optional, raises rate limit)
#   --dest DIR       Directory to clone repos into (default: /tmp/check_user_USERNAME)
#   --keep           Keep cloned repos after the scan (default: delete them)
#   -h, --help       Show this help

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

USER=""
TOKEN=""
DEST=""
KEEP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)  USER="${2:?--user requires a value}"; shift 2 ;;
    --token) TOKEN="${2:?--token requires a value}"; shift 2 ;;
    --dest)  DEST="${2:?--dest requires a value}"; shift 2 ;;
    --keep)  KEEP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$USER" ]] || { echo "Error: --user is required" >&2; usage >&2; exit 2; }

[[ -n "$DEST" ]] || DEST="/tmp/check_user_${USER}"

echo "==> Listing public owned repos for: $USER"

token_args=()
[[ -n "$TOKEN" ]] && token_args=(--token "$TOKEN")

mapfile -t urls < <("$SCRIPT_DIR/list_public_repos.sh" --user "$USER" "${token_args[@]}")

if [[ ${#urls[@]} -eq 0 ]]; then
  echo "No public owned repos found." >&2
  exit 0
fi

echo "    Found ${#urls[@]} repo(s):"
printf '    %s\n' "${urls[@]}"
echo ""

echo "==> Cloning into: $DEST"
mkdir -p "$DEST"

for url in "${urls[@]}"; do
  repo_name="$(basename "$url" .git)"
  if [[ -d "$DEST/$repo_name/.git" ]]; then
    echo "    [skip] $repo_name (already cloned)"
  else
    echo "    [clone] $repo_name"
    git clone --quiet "$url" "$DEST/$repo_name"
  fi
done
echo ""

echo "==> Scanning git authors"
out_all="$DEST/authors.txt"
out_unique="$DEST/authors_unique.txt"

"$SCRIPT_DIR/update_authors.sh" \
  --root "$DEST" \
  --out "$out_all" \
  --out-unique "$out_unique"

echo ""
echo "==> Unique identities found:"
cat "$out_unique"

if [[ "$KEEP" == false ]]; then
  echo ""
  echo "==> Cleaning up: $DEST"
  rm -rf "$DEST"
fi
