# git-author-edits

> ⚠️ **Warning:** Generated from a vibe-coding session. Use with caution — the scripts (and this doc) have not been fully reviewed. Use at your own risk.

A toolkit for rewriting git commit author/committer identity across one or many repositories.

Designed for migrating from old personal identities to new ones (e.g. after renaming a GitHub account), while leaving third-party co-author commits untouched.

Profiles (name + email) are auto-discovered from `~/.gitconfig` — no hardcoded values in any script.

---

## Why not `git-reauthor`?

[`git-reauthor`](https://github.com/tj/git-extras/blob/main/man/git-reauthor.md) (from `git-extras`) covers the single-repo case but stops there. This toolkit goes further:

| Feature                            | `git-reauthor`     | This toolkit                      |
| ---------------------------------- | ------------------ | --------------------------------- |
| Single repo rewrite                | ✅                 | ✅                                |
| Multi-repo batch                   | ❌                 | ✅ `rewrite_history_all.sh`       |
| Auto-profile from `~/.gitconfig`   | ❌ (explicit args) | ✅ `lib_profiles.sh`              |
| Selective rewrite by regex pattern | ❌                 | ✅ `--author PATTERN`             |
| Dry-run mode                       | ❌                 | ✅ default on all scripts         |
| Backup + restore                   | ❌                 | ✅ `refs/original/` + `--restore` |
| Clone from URL list                | ❌                 | ✅ `clone_repos.sh`               |
| Switch HTTPS → SSH remotes         | ❌                 | ✅ `switch_remotes.sh`            |
| Force-push all + clean refs        | ❌                 | ✅ `push_all.sh`                  |
| Author audit across repos          | ❌                 | ✅ `update_authors.sh`            |

`git-reauthor` also relies on the deprecated `git-filter-branch`, which is known to be **orders of magnitude slower** than modern alternatives — on large repos it can take hours where [`git-filter-repo`](https://github.com/newren/git-filter-repo) takes seconds. This toolkit uses it as a **required dependency** and wraps it to handle profile resolution, selective rewriting, multi-repo batching, dry-run safety, and force-pushing automatically.

---

## Scripts

| Script                                              | Purpose                                            |
| --------------------------------------------------- | -------------------------------------------------- |
| [`clone_repos.sh`](#clone_reposssh)                 | Clone a list of repos from a file                  |
| [`list_public_repos.sh`](#list_public_reposssh)     | List all public repos of a GitHub user             |
| [`switch_remotes.sh`](#switch_remotessh)            | Convert HTTPS remotes to SSH, rename account       |
| [`rewrite_history.sh`](#rewrite_historyssh)         | Rewrite author identity in a single repo           |
| [`rewrite_history_all.sh`](#rewrite_history_allssh) | Rewrite author identity across all repos           |
| [`push_all.sh`](#push_allssh)                       | Force-push all repos, optionally clean backup refs |
| [`list_authors.sh`](#list_authorsssh)               | List unique author identities per repo             |
| [`update_authors.sh`](#update_authorsssh)           | Regenerate author list files                       |
| [`lib_profiles.sh`](#lib_profilesssh)               | Shared library — sourced by other scripts          |

---

## Prerequisites

- [`git-filter-repo`](https://github.com/newren/git-filter-repo) — required by `rewrite_history.sh`
- SSH config with named host aliases, e.g. `~/.ssh/config`:
  ```
  Host gitcustom
    HostName github.com
    User git
    IdentityFile ~/.ssh/gitcustom
  ```
- `~/.gitconfig` with `includeIf` blocks mapping each alias to a profile file:
  ```ini
  [includeIf "hasconfig:remote.*.url:git@gitcustom:*/**"]
      path = ~/.gitconfig-custom
  ```
- Each profile file (e.g. `~/.gitconfig-custom`) containing:
  ```ini
  [user]
      name = YourName
      email = your@email.com
  ```

---

## Typical workflow

```bash
# 1. Clone repos listed in repos.txt
./clone_repos.sh --file repos.txt --dest /path/to/workspace --yes

# 2. Switch all remotes from HTTPS to SSH alias, rename account if needed
./switch_remotes.sh --root /path/to/workspace --host gitcustom --account oldname:newname --yes

# 3. Preview what would be rewritten (dry-run)
./rewrite_history_all.sh --root /path/to/workspace --author oldname

# 4. Apply the rewrite
./rewrite_history_all.sh --root /path/to/workspace --author oldname --yes

# 5. Force-push all repos and clean up backup refs
./push_all.sh --root /path/to/workspace --clean-refs --yes

# 6. Audit author identities
./update_authors.sh --root /path/to/workspace
```

---

## Script reference

### `clone_repos.sh`

Clone repositories listed one URL per line in a file. Already-cloned repos are skipped.

```
Usage: clone_repos.sh [--file FILE] [--dest DIR] [--yes]

  --file FILE   URL list file (default: repos.txt)
  --dest DIR    Destination directory (default: .)
  --yes         Apply (default: dry-run)
```

`repos.txt` format — one URL per line, `#` comments supported:

```
https://github.com/ACCOUNT/REPO
git@github.com:ACCOUNT/REPO.git
# this line is ignored
```

---

### `list_public_repos.sh`

List all public repositories of a GitHub user via the GitHub API. Output is one HTTPS URL per line, ready to use as a `repos.txt` file. Handles pagination automatically.

```
Usage: list_public_repos.sh --user USERNAME [--token TOKEN] [--out FILE]

  --user USERNAME  GitHub username to query (required)
  --token TOKEN    GitHub personal access token (optional)
  --out FILE       Write output to FILE instead of stdout
```

Example — generate a `repos.txt` and clone all repos:

```bash
./list_public_repos.sh --user MyUsername --out repos.txt
./clone_repos.sh --file repos.txt --dest ./workspace --yes
```

> **Note:** Unauthenticated requests are limited to 60/hour by the GitHub API. Pass `--token` with a [personal access token](https://github.com/settings/tokens) to raise it to 5000/hour.

---

### `switch_remotes.sh`

Convert HTTPS remote URLs to SSH and/or rename the account owner in all remotes under a root directory.

```
Usage: switch_remotes.sh [--root DIR] [--host HOST] [--account OLD:NEW] [--list] [--yes]

  --root DIR         Root directory to scan (default: .)
  --host HOST        SSH host alias to use (default: github.com)
  --account OLD:NEW  Rename account OLD to NEW in all remote URLs
  --list             List remotes only, no changes
  --yes              Apply (default: dry-run)
```

---

### `rewrite_history.sh`

Rewrite author and committer identity on all branches and tags in a single repo.

Identity is resolved automatically from the repo's `origin` remote URL via `lib_profiles.sh`.

Only commits whose author or committer matches `--author` patterns are rewritten — all other commits (co-authors, third parties) are left untouched.

```
Usage: rewrite_history.sh [--repo DIR] [--author PATTERN]... [--yes]
       rewrite_history.sh [--repo DIR] --restore [--yes]

  --repo DIR       Target repository (default: .)
  --author PATTERN Regex to match author name or email. Repeatable.
                   If omitted, all commits are rewritten.
  --restore        Restore original history from refs/original/ backup
  --yes            Apply (default: dry-run)
```

Original branch/tag tips are backed up under `refs/original/` before rewriting, enabling `--restore`.

---

### `rewrite_history_all.sh`

Run `rewrite_history.sh` on every git repo found under a root directory. Repos with no matching SSH profile are skipped automatically.

```
Usage: rewrite_history_all.sh [--root DIR] [--author PATTERN]... [--yes]

  --root DIR       Root directory to scan (default: .)
  --author PATTERN Regex to match (repeatable, optional)
  --yes            Apply (default: dry-run)
```

Repos are skipped if:

- They are submodules (`.git` is a file)
- They have no `origin` remote
- Their remote doesn't match any known SSH alias
- Their working tree is dirty

---

### `push_all.sh`

Force-push all branches and tags for every repo under a root directory. Optionally cleans up `refs/original/` backup refs.

```
Usage: push_all.sh [--root DIR] [--clean-refs] [--yes]

  --root DIR      Root directory to scan (default: .)
  --clean-refs    Delete refs/original/ backup refs after pushing
  --yes           Apply (default: dry-run)
```

---

### `list_authors.sh`

List all unique author and committer identities (name + email) from all commits on all branches, grouped by repo.

```
Usage: list_authors.sh [DIR]

  DIR   Root directory to scan (default: .)
```

Output is printed to stdout. Use `update_authors.sh` to write to files.

---

### `update_authors.sh`

Run `list_authors.sh` and write results to two files:

- `list_authors.txt` — identities grouped by repo
- `list_authors_unique.txt` — globally sorted unique entries

```
Usage: update_authors.sh [--root DIR] [--out FILE] [--out-unique FILE]

  --root DIR         Root directory to scan (default: .)
  --out FILE         Per-repo output (default: list_authors.txt)
  --out-unique FILE  Global unique output (default: list_authors_unique.txt)
```

> Both output files are listed in `.gitignore` as they may contain sensitive identity information.

---

### `lib_profiles.sh`

Shared library sourced by `rewrite_history.sh`, `rewrite_history_all.sh`, and `push_all.sh`. Do not execute directly.

Reads `~/.gitconfig` `includeIf` blocks to build a map of SSH alias → name/email.

**Provided functions:**

```bash
load_git_profiles                            # Populates PROFILES[alias]="Name|email"
profile_for_remote URL name_var email_var    # Resolves identity from a remote URL
remote_is_known URL                          # Returns 0 if URL matches a known alias
```

---

## Security notes

- `list_authors.txt` and `list_authors_unique.txt` are excluded from git via `.gitignore` — they contain real names and email addresses.
- No credentials or tokens are stored in any script. SSH key auth is used exclusively via named host aliases in `~/.ssh/config`.
- `--yes` is required to apply any destructive operation. All scripts default to dry-run.
