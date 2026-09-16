#!/usr/bin/env bash
# git — link ~/.gitconfig and generate the machine-local include.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up git..."
link "${CURRENT_DIR}/gitconfig" "${HOME}/.gitconfig"
# init.templateDir: new repos get hooks/pre-commit (gitleaks secret scan).
link "${CURRENT_DIR}/template" "${HOME}/.config/git/template"

# git/gitconfig ends with `[include] path = ~/.config/git/gitconfig.local`.
# That file holds everything machine-specific: user.name/user.email, and the
# path to the Homebrew gpg, which differs between /opt/homebrew (arm64) and
# /usr/local. Only gpg.program is set here; the rest of the file is left alone.
LOCAL_CONFIG="${HOME}/.config/git/gitconfig.local"
mkdir -p "$(dirname "${LOCAL_CONFIG}")"

GPG_PROGRAM="$(brew_prefix)/bin/gpg"
git config --file "${LOCAL_CONFIG}" gpg.program "${GPG_PROGRAM}"
ok "${LOCAL_CONFIG} (gpg.program = ${GPG_PROGRAM})"

[ -x "${GPG_PROGRAM}" ] || warn "gpg not found at ${GPG_PROGRAM}; commit signing will fail until \`brew install gpg\`."
