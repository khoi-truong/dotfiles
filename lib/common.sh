#!/usr/bin/env bash
# Shared helpers for dotfiles module scripts.
#
# Usage (from any <module>/setup.sh):
#   set -euo pipefail
#   DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.."; pwd)}"
#   . "${DOTFILES}/lib/common.sh"
#
# Everything here must stay POSIX-ish bash 3.2 compatible: macOS ships bash 3.2
# as /bin/bash and this file may be sourced by scripts run through it.

# Guard against double-sourcing.
[ -n "${DOTFILES_COMMON_SH:-}" ] && return 0
DOTFILES_COMMON_SH=1

# Where this file lives, whether or not the caller set DOTFILES.
DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# One attempt per top-level run: modules run as child processes and inherit it.
if [ -z "${DOTFILES_ATTEMPT:-}" ]; then
  DOTFILES_ATTEMPT="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  export DOTFILES_ATTEMPT
fi

# --- logging ---------------------------------------------------------------

log() { printf '%s\n' "$*"; }
info() { printf '\033[0;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m  !\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[0;31m  ✗\033[0m %s\n' "$*" >&2
  exit 1
}

# --- platform --------------------------------------------------------------

is_macos() { [ "$(uname -s)" = "Darwin" ]; }

# Exit successfully (not an error) when not on macOS. Almost every module here
# is macOS-only, so a non-Darwin run should be a silent no-op.
require_macos() {
  is_macos || {
    log "Skipping $(basename "${0:-module}"): not macOS."
    exit 0
  }
}

is_arm() { [ "$(uname -m)" = "arm64" ]; }

# Homebrew prefix for the current architecture. Prefers a real `brew` on PATH
# (handles non-standard installs) and falls back to the arch default.
#
# NOTE: uses `command brew` so a shell alias/function named `brew` cannot
# interfere.
brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    command brew --prefix
  elif is_arm; then
    printf '%s\n' /opt/homebrew
  else
    printf '%s\n' /usr/local
  fi
}

# Put brew on PATH for the remainder of the current script.
load_brew_shellenv() {
  local prefix
  prefix="$(brew_prefix)"
  [ -x "${prefix}/bin/brew" ] || return 1
  eval "$("${prefix}/bin/brew" shellenv)"
}

# --- filesystem ------------------------------------------------------------

# link <source> <target> — idempotent symlink, creating the parent directory.
# Journaled: anything already at the target (file, directory or other symlink)
# is moved into the current attempt's backup directory, and `scripts/restore.sh`
# puts it all back. A missing source warns and returns 0.
link() {
  _transaction link "$@"
}

# backup <path> — move a file or directory aside (journaled) instead of
# deleting it. A missing path is a no-op.
backup() {
  _transaction backup "$@"
}

# copy <source> <target> [mode] — install a regular-file copy, for tools that
# refuse to read through a symlink. Idempotent: an identical regular file is
# left alone. Anything else at the target (a symlink, a different file) is
# backed up first, so `scripts/restore.sh` puts it back. Default mode 600.
copy() {
  local src="$1" dst="$2" mode="${3:-600}"
  if [ ! -f "${src}" ]; then
    warn "copy: source missing: ${src}"
    return 0
  fi
  if [ -f "${dst}" ] && [ ! -L "${dst}" ] && cmp -s "${src}" "${dst}"; then
    chmod "${mode}" "${dst}"
    ok "${dst}"
    return 0
  fi
  if [ -e "${dst}" ] || [ -L "${dst}" ]; then
    backup "${dst}"
  fi
  mkdir -p "$(dirname "${dst}")"
  install -m "${mode}" "${src}" "${dst}"
  ok "${dst} (copied from ${src})"
}

_transaction() {
  if is_macos; then
    xcode-select -p >/dev/null 2>&1 || die "python3 missing: run xcode-select --install"
  fi
  "${DOTFILES_PYTHON:-python3}" -B "${DOTFILES}/lib/transaction.py" "$@"
}

# module_dir — absolute directory of the calling script.
module_dir() { (cd "$(dirname "$0")" && pwd); }
