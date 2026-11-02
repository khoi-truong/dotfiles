#!/usr/bin/env bash
# mise — the single version manager (python, node, ruby, go, java, swift tools).
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

install_tools=1
for arg in "$@"; do
  case "$arg" in
    --no-install) install_tools=0 ;;
  esac
done

info "Setting up mise..."
link "${CURRENT_DIR}/global.toml" "${HOME}/.config/mise/config.toml"

if [ "$install_tools" -eq 0 ]; then
  info "Skipping mise install (--no-install)."
elif command -v mise >/dev/null 2>&1; then
  info "Installing pinned tools (mise install)..."
  mise install
else
  warn "mise is not installed yet — run brew/setup.sh first, then re-run this."
fi
