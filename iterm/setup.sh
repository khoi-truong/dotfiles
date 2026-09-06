#!/usr/bin/env bash
# iTerm2 — point the app at this repo's prefs folder.
#
# iTerm2 has no dotfile: it reads com.googlecode.iterm2.plist out of whatever
# folder "Load preferences from a custom folder" is set to. Pointing that at
# iterm/ makes the committed plist live. Changes made in iTerm's UI are written
# back to iterm/com.googlecode.iterm2.plist on quit, so commit them from there.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up iTerm2..."
defaults write com.googlecode.iterm2 PrefsCustomFolder -string "${CURRENT_DIR}"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
ok "iTerm2 prefs folder -> ${CURRENT_DIR}"
