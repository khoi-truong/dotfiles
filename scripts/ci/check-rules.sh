#!/usr/bin/env bash
#
# The CLAUDE.md rules that a grep can decide.
#
# Three invariants in CLAUDE.md have no other check behind them: a Homebrew
# prefix is never hardcoded (the repo is dual-arch), mise is the only version
# manager, and credentials never land in the repo. Each is one pattern away
# from being enforced, so it is enforced here rather than left to review.
#
# Scope is the shell files, not the whole tree. A mention of /opt/homebrew in
# README.md or a skill reference is prose, not a hardcoded prefix. Full-line
# comments are skipped for the same reason: a comment explaining one of these
# rules has to be able to name a prefix.
#
# The file list comes from `shell_files` below. A `*.sh`/`*.zsh` glob was not
# enough: it walked past zsh/zshrc, zsh/zshenv and the extensionless hooks in
# git/template/, and zsh/zshrc is read on every shell start — the one place a
# hardcoded prefix would hurt most.
#
# Files are read from the working tree, so an edit that is not committed yet is
# still checked. CI runs on a clean checkout, where the two are the same.
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
VERSION_MANAGER_RE='pyenv init|rbenv init|jenv init|nvm\.sh|asdf\.sh'

# Tracked-file suffixes that hold credentials. CLAUDE.md names these three as
# the files that must never be versioned; only declarative config under ai/ is.
CREDENTIAL_SUFFIXES=(
  '.claude.json'
  '.credentials.json'
  'github-copilot/apps.json'
)

# Tracked plus untracked-not-ignored, NUL-delimited so a path with a space or
# a newline cannot split into two. `git ls-files` needs the repository root.
all_files() {
  git ls-files -z --cached --others --exclude-standard
}

# Every shell file the Homebrew-prefix rule is about, taken from the same source
# CI's shellcheck step reads — scripts/ci/list-shell-scripts.sh finds every
# tracked `*.sh` and every tracked extensionless file whose shebang names bash
# or sh.
# That script leaves zsh to `zsh -n`, so the zsh files are named here — those
# two extensionless ones included, since they are what a shell reads. `sort -u`
# so a path cannot be listed twice and reported twice.
shell_files() {
  {
    scripts/ci/list-shell-scripts.sh
    git ls-files '*.zsh' zsh/zshrc zsh/zshenv
  } | sort -u
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
  local path hit
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case " ${HOMEBREW_ALLOWLIST[*]} " in
      *" ${path} "*) continue ;;
    esac
    files+=("$path")
  done < <(shell_files)

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

main() {
  local -a failed=()

  printf '==> no hardcoded Homebrew prefix\n'
  check_homebrew_prefix || failed+=('Homebrew prefix')

  printf '\n==> mise is the only version manager\n'
  check_version_manager || failed+=('version managers')

  printf '\n==> no tracked credentials\n'
  check_credentials || failed+=('tracked credentials')

  printf '\n'
  if [ "${#failed[@]}" -ne 0 ]; then
    printf 'check-rules: FAILED — %s\n' "${failed[*]}"
    return 1
  fi
  printf 'check-rules: all three rules hold\n'
}

main "$@"
