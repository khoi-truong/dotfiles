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
# Uses -n so re-linking a directory replaces the link instead of nesting a new
# link inside it.
link() {
  local src="$1" dst="$2"
  [ -e "$src" ] || {
    warn "link: source missing, skipped: $src"
    return 0
  }
  mkdir -p "$(dirname "$dst")"
  # A real (non-symlink) file/dir at the target would be silently shadowed;
  # back it up once so nothing is lost on a fresh machine.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "${dst}.dotfiles-backup"
    warn "backed up existing $dst -> ${dst}.dotfiles-backup"
  fi
  ln -sfn "$src" "$dst"
  ok "$dst -> $src"
}

# module_dir — absolute directory of the calling script.
module_dir() { (cd "$(dirname "$0")" && pwd); }
