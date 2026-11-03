#!/usr/bin/env bash
#
# The AGENTS.md rules that a grep can decide.
#
# Four invariants have no other check behind them: a Homebrew prefix is never
# hardcoded (the repo is dual-arch), mise is the only version manager,
# credentials never land in the repo, and no file names a user's home
# directory. Each is one pattern away from being enforced, so it is enforced
# here rather than left to review.
#
# Scope is the shell files, not the whole tree. A mention of /opt/homebrew in
# README.md or a skill reference is prose, not a hardcoded prefix. Full-line
# comments are skipped for the same reason: a comment explaining one of these
# rules has to be able to name a prefix.
#
# The file list comes from `shell_files` below: the union of
# scripts/ci/list-shell-scripts.sh and `list-shell-scripts.sh --zsh`, which
# read tracked files and untracked ones that are not gitignored. A `*.sh`/`*.zsh`
# glob was not enough - it walked past zsh/zshrc, zsh/zshenv and the
# extensionless hooks in git/template/, and zsh/zshrc is read on every shell
# start, the one place a hardcoded prefix would hurt most.
#
# Untracked files are included so a violation is caught while it is still one
# edit from being fixed. CI runs on a clean checkout, where the working tree and
# the index agree, so this is stricter than CI and never looser.
#
# The home-path rule reads every file, not just the shell ones. The harness
# settings are symlinked into $HOME, so a tool that registers itself there
# (a plugin marketplace, a hook) writes its absolute path straight into a
# tracked file.
#
# The credential rule below is the one exception to "read the working tree": it
# asks whether a secrets file is tracked, which an untracked one is not.
#
# Run by .github/workflows/lint.yml and scripts/ci/lint-local.sh; both files
# name the other, so a change here lands in both.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Files that may legitimately name a Homebrew prefix. Two of them answer "which
# prefix is this machine's"; the third has to spell out the prefixes it looks
# for. Nothing else may join the list — a fourth entry is a design decision,
# not a paperwork fix.
HOMEBREW_ALLOWLIST=(
  # brew_prefix — the arch fallback for when no `brew` is on PATH.
  'lib/common.sh'
  # Exports HOMEBREW_PREFIX from the same arch test, to avoid paying for a
  # `brew shellenv` subprocess on every shell start (~50 ms).
  'zsh/env.zsh'
  # This script: HOMEBREW_RE and the failure message both have to name them.
  'scripts/ci/check-rules.sh'
)

# A hardcoded path in one of these is the dual-arch violation.
HOMEBREW_RE='/opt/homebrew|/usr/local'

# mise owns every runtime; a second manager's init hook in the shell is the
# violation, whatever it is called.
VERSION_MANAGER_RE='pyenv init|rbenv init|jenv init|nodenv init|fnm env|volta setup|corepack enable|nvm\.sh|asdf\.sh'

# Tracked-file suffixes that hold credentials. AGENTS.md names these three as
# the files that must never be versioned; only declarative config under ai/ is.
# is_credential_name below adds the credential files that are matched by name.
CREDENTIAL_SUFFIXES=(
  '.claude.json'
  '.credentials.json'
  'github-copilot/apps.json'
)

# A path that names a credential file: Claude Code's local settings, the gh CLI
# token file, key and certificate stores, and dotenv files (but not the
# committed .env.example template).
is_credential_name() {
  case "$1" in
    */gh/hosts.yml | gh/hosts.yml) return 0 ;;
  esac
  case "${1##*/}" in
    .env.example) return 1 ;;
    settings.local.json | *.pem | *.p12 | .env | .env.*) return 0 ;;
  esac
  return 1
}

# Tracked plus untracked-not-ignored, NUL-delimited so a path with a space or
# a newline cannot split into two. `git ls-files` needs the repository root.
all_files() {
  git ls-files -z --cached --others --exclude-standard
}

# Every shell file the Homebrew-prefix rule is about: the bash/sh list and the
# zsh list from the one script every check reads. `sort -u` so a path cannot be
# listed twice and reported twice.
shell_files() {
  local bash_list zsh_list
  bash_list="$(scripts/ci/list-shell-scripts.sh)" || return 1
  zsh_list="$(scripts/ci/list-shell-scripts.sh --zsh)" || return 1
  if [ -z "$bash_list" ] || [ -z "$zsh_list" ]; then
    printf 'check-rules: list-shell-scripts.sh listed nothing\n' >&2
    return 1
  fi
  printf '%s\n%s\n' "$bash_list" "$zsh_list" | sort -u
}

# A line whose first non-blank character is `#` is a comment. `$1` is the text
# after "file:line:" from `grep -n`.
is_comment() {
  case "${1#"${1%%[![:space:]]*}"}" in
    '#'*) return 0 ;;
  esac
  return 1
}

# `grep -n` output is "file:line:text". The text may itself contain colons, so
# the split drops the shortest "file:" then the shortest "line:".
grep_text() {
  local rest="${1#*:}"
  printf '%s\n' "${rest#*:}"
}

check_homebrew_prefix() {
  local -a files=() found=()
  local path hit list
  list="$(shell_files)" || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case " ${HOMEBREW_ALLOWLIST[*]} " in
      *" ${path} "*) continue ;;
    esac
    files+=("$path")
  done <<<"$list"

  [ "${#files[@]}" -gt 0 ] || return 0

  # One grep over every file so the findings come out grouped, not interleaved.
  while IFS= read -r hit; do
    is_comment "$(grep_text "$hit")" && continue
    found+=("$hit")
  done < <(grep -nE -e "$HOMEBREW_RE" -- "${files[@]}" || true)

  if [ "${#found[@]}" -ne 0 ]; then
    printf 'Use brew_prefix from lib/common.sh; never hardcode /opt/homebrew or /usr/local:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
    return 1
  fi
}

check_version_manager() {
  local -a files=() found=()
  local path hit
  while IFS= read -r -d '' path; do
    case "$path" in
      zsh/*) files+=("$path") ;;
    esac
  done < <(all_files)

  [ "${#files[@]}" -gt 0 ] || return 0

  while IFS= read -r hit; do
    is_comment "$(grep_text "$hit")" && continue
    found+=("$hit")
  done < <(grep -nE -e "$VERSION_MANAGER_RE" -- "${files[@]}" || true)

  if [ "${#found[@]}" -ne 0 ]; then
    printf 'mise is the only version manager; nothing else may init in zsh/:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
    return 1
  fi
}

check_credentials() {
  local -a found=()
  local path suffix
  # Tracked, not the working tree: the rule is about what is in the repository.
  # An ignored working-copy file (ai/claude/.credentials*) never gets here.
  while IFS= read -r -d '' path; do
    if is_credential_name "$path"; then
      found+=("$path")
      continue
    fi
    for suffix in "${CREDENTIAL_SUFFIXES[@]}"; do
      case "$path" in
        *"$suffix")
          found+=("$path")
          break
          ;;
      esac
    done
  done < <(git ls-files -z)

  if [ "${#found[@]}" -ne 0 ]; then
    printf 'Credentials are tracked; remove them from the index and gitignore them:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
    return 1
  fi
}

# /Users/<name>/ — the macOS home form. /Users/Shared is not a home.
HOME_PATH_RE='/Users/[a-z][a-z0-9._-]*/'

check_home_path() {
  local -a files=() found=()
  local path
  while IFS= read -r -d '' path; do
    [ -f "$path" ] && [ ! -L "$path" ] && files+=("$path")
  done < <(all_files)

  [ "${#files[@]}" -gt 0 ] || return 0

  # -I skips binaries. Names only, never the matched line: it holds the path.
  while IFS= read -r path; do
    found+=("$path")
  done < <(grep -lIE -e "$HOME_PATH_RE" -- "${files[@]}" || true)

  if [ "${#found[@]}" -ne 0 ]; then
    printf 'A home path (/Users/<name>/) is in these files; use the HOME variable or ~, or keep the entry machine-local:\n' >&2
    printf '  %s\n' "${found[@]}" >&2
    return 1
  fi
}

main() {
  local -a failed=()

  printf '==> no hardcoded Homebrew prefix\n'
  check_homebrew_prefix || failed+=('Homebrew prefix')

  printf '\n==> mise is the only version manager\n'
  check_version_manager || failed+=('version managers')

  printf '\n==> no tracked credentials\n'
  check_credentials || failed+=('tracked credentials')

  printf '\n==> no hardcoded home path\n'
  check_home_path || failed+=('home path')

  printf '\n'
  if [ "${#failed[@]}" -ne 0 ]; then
    printf 'check-rules: FAILED — %s\n' "${failed[*]}"
    return 1
  fi
  printf 'check-rules: all four rules hold\n'
}

main "$@"
