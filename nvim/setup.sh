#!/usr/bin/env bash
# Neovim — link the whole config directory, so lazy-lock.json written by
# `:Lazy update` lands back in the repo.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"

CURRENT_DIR="$(module_dir)"

info "Setting up Neovim..."

link "${CURRENT_DIR}" "${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"

ok "Neovim configured."
