#!/usr/bin/env bash
# List all public, non-forked repositories owned by a GitHub user.
# Output is one HTTPS URL per line, ready to use as a repos.txt file.
#
# Usage:
#   list_public_repos.sh --user USERNAME [--token TOKEN] [--out FILE]
#
# Options:
#   --user USERNAME  GitHub username to query (required)
#   --token TOKEN    GitHub personal access token (optional, raises rate limit from 60 to 5000 req/hour)
#   --out FILE       Write output to FILE instead of stdout
#   -h, --help       Show this help
#
# Notes:
#   Uses the GitHub REST API.
#   Handles pagination automatically.

set -euo pipefail
IFS=$'\n\t'

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

USER=""
OUT=""
TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)  USER="${2:?--user requires a value}"; shift 2 ;;
    --token) TOKEN="${2:?--token requires a value}"; shift 2 ;;
    --out)   OUT="${2:?--out requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$USER" ]] || { echo "Error: --user is required" >&2; usage >&2; exit 2; }

command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 2; }

fetch_page() {
  local page="$1"
  local auth_header=()
  [[ -n "$TOKEN" ]] && auth_header=(--header "Authorization: Bearer ${TOKEN}")
  curl --silent --fail --show-error \
    --header "Accept: application/vnd.github.v3+json" \
    "${auth_header[@]}" \
    "https://api.github.com/users/${USER}/repos?type=public&per_page=100&page=${page}"
}

urls=()
page=1

while true; do
  response=$(fetch_page "$page")

  # Extract HTTPS clone URLs for non-forked repos only.
  # Each repo object has "fork": true/false before "clone_url", so we use awk
  # to track the fork flag and only emit the URL when fork is false.
  mapfile -t batch < <(printf '%s' "$response" | awk '
    /"fork": *true/  { fork=1 }
    /"fork": *false/ { fork=0 }
    /"clone_url"/ {
      if (!fork) {
        gsub(/.*"clone_url": *"/, ""); gsub(/".*/, ""); print
      }
      fork=0
    }
  ')

  [[ ${#batch[@]} -eq 0 ]] && break

  urls+=("${batch[@]}")
  [[ ${#batch[@]} -lt 100 ]] && break
  ((page+=1))
done

if [[ ${#urls[@]} -eq 0 ]]; then
  echo "No public repositories found for user: $USER" >&2
  exit 0
fi

if [[ -n "$OUT" ]]; then
  printf '%s\n' "${urls[@]}" > "$OUT"
  echo "Written ${#urls[@]} repos to: $OUT" >&2
else
  printf '%s\n' "${urls[@]}"
fi
