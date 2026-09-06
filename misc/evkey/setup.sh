#!/usr/bin/env bash
# EVKey — replace the menu bar icons with the ones in Resources/.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
EVKEY_RESOURCES="/Applications/EVKey.app/Contents/Resources"

if [ ! -d "${EVKEY_RESOURCES}" ]; then
  warn "EVKey is not installed; skipping icon replacement."
  exit 0
fi

info "Replacing EVKey menu bar icons..."
for icon in en en_l vn vn_l; do
  cp -f "${CURRENT_DIR}/Resources/${icon}.tiff" "${EVKEY_RESOURCES}/${icon}.tiff"
done
ok "EVKey icons replaced."
