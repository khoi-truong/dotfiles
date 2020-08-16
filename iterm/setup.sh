#!/bin/sh

[ "$(uname -s)" != "Darwin" ] && exit 0

echo ""
echo "Setting up iTerm2..."

[ "$(uname -s)" != "Darwin" ] && exit 0
defaults write com.googlecode.iterm2 "PrefsCustomFolder" -string "$DOTFILES/iterm"
defaults write com.googlecode.iterm2 "LoadPrefsFromCustomFolder" -bool true
