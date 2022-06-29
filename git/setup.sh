#!/bin/sh

# Setup git configs

echo ""
echo "Setup git configs..."
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore

mkdir -p ~/.config/git
touch ~/.config/git/gitconfig.local
echo "[gpg]" >> ~/.config/git/gitconfig.local
if [[ $(uname -m) == 'arm64' ]]; then
  echo "  program = /opt/homebrew/bin/gpg" >> ~/.config/git/gitconfig.local
else
  echo "  program = /usr/local/bin/gpg" >> ~/.config/git/gitconfig.local
fi
