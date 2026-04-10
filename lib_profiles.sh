#!/usr/bin/env bash
# Shared library — source this file, do not execute it directly.
#
# Provides: load_git_profiles
#
# After calling load_git_profiles, the associative array PROFILES is populated:
#   PROFILES[alias]="Name|email"
#
# Example:
#   source "$(dirname "$0")/lib_profiles.sh"
#   load_git_profiles          # exits on error
#   echo "${PROFILES[gitcustom]}" # -> GlowingShadow|16785336+GlowingShadow@users.noreply.github.com
#
# Reads ~/.gitconfig includeIf blocks of the form:
#   [includeIf "hasconfig:remote.*.url:git@ALIAS:*/**"]
#       path = ~/.gitconfig-ALIAS

load_git_profiles() {
  # Caller must declare PROFILES as associative array before calling
  # (or we declare it here if not already declared)
  if ! declare -p PROFILES &>/dev/null 2>&1; then
    declare -gA PROFILES
  fi

  local key val alias cfg_path name email found=0

  while IFS='= ' read -r key val; do
    key="${key// /}"
    val="${val// /}"
    [[ "$key" =~ \.path$ ]] || continue

    alias=$(printf '%s' "$key" | sed -nE 's/.*git@([^:]+):.*/\1/p')
    [[ -z "$alias" ]] && continue

    cfg_path="${val/#\~/$HOME}"
    [[ -f "$cfg_path" ]] || continue

    name=$(git config --file "$cfg_path" user.name 2>/dev/null || true)
    email=$(git config --file "$cfg_path" user.email 2>/dev/null || true)
    [[ -z "$name" || -z "$email" ]] && continue

    PROFILES["$alias"]="${name}|${email}"
    found=1
  done < <(git config --global --list 2>/dev/null | grep -i 'includeif')

  if [[ $found -eq 0 ]]; then
    echo "lib_profiles: No SSH profiles found in ~/.gitconfig includeIf blocks." >&2
    echo "  Expected entries like:" >&2
    echo "    [includeIf \"hasconfig:remote.*.url:git@ALIAS:*/**\"]" >&2
    echo "        path = ~/.gitconfig-ALIAS" >&2
    return 1
  fi
}

# Helper: resolve Name and email from a remote URL.
# Usage: profile_for_remote URL name_var email_var
# Returns 1 if alias not found.
profile_for_remote() {
  local url="$1" _name_var="$2" _email_var="$3"
  local alias
  alias=$(printf '%s' "$url" | sed -nE 's#^git@([^:]+):.*#\1#p')
  if [[ -z "$alias" || -z "${PROFILES[$alias]:-}" ]]; then
    return 1
  fi
  printf -v "$_name_var"  '%s' "${PROFILES[$alias]%%|*}"
  printf -v "$_email_var" '%s' "${PROFILES[$alias]##*|}"
}

# Helper: check if a remote URL matches any known profile alias.
# Usage: remote_is_known URL
# Returns 0 if matched, 1 otherwise.
remote_is_known() {
  local url="$1"
  local alias
  alias=$(printf '%s' "$url" | sed -nE 's#^git@([^:]+):.*#\1#p')
  [[ -n "$alias" && -n "${PROFILES[$alias]:-}" ]]
}
