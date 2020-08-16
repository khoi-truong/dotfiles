#!/bin/sh

[ "$(uname -s)" != "Darwin" ] && exit 0

echo "Config Alfred preferences folder"
defaults write com.runningwithcrayons.Alfred-Preferences "syncfolder" -string "~/.dotfiles/alfred"
