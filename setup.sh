#!/usr/bin/env bash

cd ./macos
brew bundle
chmod +x ./setup
sudo ./setup
cd ..

DOTFILES="$(cd "$(dirname "$0")"; pwd)";

ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

rm ~/.zsh_history