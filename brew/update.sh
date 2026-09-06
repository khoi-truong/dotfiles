#!/usr/bin/env bash
# brew/update.sh — dump what is actually installed on this machine to
# Brewfile.generated, to reconcile against the grouped Brewfile by hand.
# Run this after installing something new manually.
#
# `brew bundle dump` loses the Brewfile's comment headers, so it writes to
# Brewfile.generated and leaves the merge to you.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
load_brew_shellenv || die "Homebrew not found."

info "Dumping installed packages to Brewfile.generated..."
brew bundle dump --force --describe --file="${CURRENT_DIR}/Brewfile.generated"
ok "${CURRENT_DIR}/Brewfile.generated"

log ""
log "Review the diff, fold anything new into the grouped Brewfile, then:"
log "  rm ${CURRENT_DIR}/Brewfile.generated"
