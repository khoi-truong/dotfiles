#!/usr/bin/env bash
# gh — link the GitHub CLI config. Auth (hosts.yml, keychain) stays local.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up gh..."
link "${CURRENT_DIR}/config.yml" "${HOME}/.config/gh/config.yml"

if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
  warn "gh is not logged in: run \`gh auth login\`."
fi
