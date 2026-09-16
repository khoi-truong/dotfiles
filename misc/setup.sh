#!/usr/bin/env bash
# misc — run every misc/*/setup.sh.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up misc modules..."
for script in "${CURRENT_DIR}"/*/setup.sh; do
  [ -f "${script}" ] || continue
  log "  → ${script#"${DOTFILES}"/}"
  DOTFILES="${DOTFILES}" bash "${script}"
done
