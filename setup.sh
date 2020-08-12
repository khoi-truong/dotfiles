#!/usr/bin/env bash

# Install Homebrew casks and setup macos defaults
cd ./macos
brew bundle
chmod +x ./setup.sh
sudo ./setup.sh
cd ..

DOTFILES="$(cd "$(dirname "$0")"; pwd)";

# Setup Terminal

chmod +x ./terminal/setup.sh
sudo ./terminal/setup.sh

# Setup iTerm
chmod +x ./iterm/setup.sh
sudo ./iterm/setup.sh

# Make symbolic links

ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

# Remove redundant history file

rm ~/.zsh_history 2> /dev/null