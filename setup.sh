#!/usr/bin/env bash

# Install Homebrew casks and setup macos defaults
cd ./macos
brew bundle
chmod +x ./setup.sh
sudo ./setup.sh
cd ..

# Setup iTerm
chmod +x ./iterm/setup.sh
sudo ./iterm/setup.sh

# Make symbolic links

DOTFILES="$(cd "$(dirname "$0")"; pwd)";

ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

# Remove redundant history file

rm ~/.zsh_history