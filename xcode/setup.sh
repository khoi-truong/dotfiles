#!/usr/bin/env bash
# Xcode — colour themes and file templates.
# Not run by ./setup.sh by default; use `./setup.sh xcode` or `--all`.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
XCODE_USER_DATA="${HOME}/Library/Developer/Xcode/UserData"

info "Setting up Xcode..."

# Themes are individual files rather than a linked directory: Xcode writes its
# own themes into the same folder, and linking the folder would hide them.
mkdir -p "${XCODE_USER_DATA}/FontAndColorThemes"
for theme in "${CURRENT_DIR}"/FontAndColorThemes/*.xccolortheme; do
  [ -f "${theme}" ] || continue
  link "${theme}" "${XCODE_USER_DATA}/FontAndColorThemes/$(basename "${theme}")"
done

bash "${CURRENT_DIR}/templates/setup.sh"
