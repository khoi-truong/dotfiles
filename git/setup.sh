#!/usr/bin/env bash
# git — link ~/.gitconfig and generate the machine-local include.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up git..."
link "${CURRENT_DIR}/gitconfig" "${HOME}/.gitconfig"
link "${CURRENT_DIR}/ignore" "${HOME}/.config/git/ignore"
# init.templateDir: new repos get hooks/pre-commit (gitleaks secret scan) and
# hooks/post-checkout (seeds new worktrees from .worktreeclone).
link "${CURRENT_DIR}/template" "${HOME}/.config/git/template"
# lazygit has no XDG path on macOS; it reads its Application Support dir.
link "${CURRENT_DIR}/lazygit.yml" "${HOME}/Library/Application Support/lazygit/config.yml"

# git/gitconfig ends with `[include] path = ~/.config/git/gitconfig.local`.
# That file holds everything machine-specific: user.name/user.email, and the
# path to the Homebrew gpg, which differs between /opt/homebrew (arm64) and
# /usr/local. gpg.program is always rewritten; user.name/user.email are asked
# for only when missing. Everything else in the file is left alone.
LOCAL_CONFIG="${HOME}/.config/git/gitconfig.local"
mkdir -p "$(dirname "${LOCAL_CONFIG}")"

GPG_PROGRAM="$(brew_prefix)/bin/gpg"
git config --file "${LOCAL_CONFIG}" gpg.program "${GPG_PROGRAM}"
ok "${LOCAL_CONFIG} (gpg.program = ${GPG_PROGRAM})"

# Ask for any missing identity once; never overwrite one that is set.
for key in user.name user.email; do
  value="$(git config --file "${LOCAL_CONFIG}" "${key}" || true)"
  if [ -z "${value}" ] && [ -t 0 ]; then
    read -r -p "  ${key}: " value || true
    [ -n "${value}" ] && git config --file "${LOCAL_CONFIG}" "${key}" "${value}"
  fi
  if [ -n "${value}" ]; then
    ok "${LOCAL_CONFIG} (${key} = ${value})"
  else
    warn "${key} is not set; run \`git config --file ${LOCAL_CONFIG} ${key} …\` before committing."
  fi
done

[ -x "${GPG_PROGRAM}" ] || warn "gpg not found at ${GPG_PROGRAM}; commit signing will fail until \`brew install gpg\`."
