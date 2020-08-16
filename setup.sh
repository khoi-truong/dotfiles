#!/bin/sh

# Install Homebrew casks
echo "Homebrew Bundle..."
cd ./macos
brew bundle
brew bundle cleanup -f
cd ..

# Setup macOS defaults
execute() {
    chmod +x "$1"; "$1";
}

for file in ./{macos,terminal,iterm,alfred,misc/gotiengviet}/setup.sh; do
	[ -r "$file" ] && [ -f "$file" ] && execute "$file"
done;
unset file;
unset execute;

# Make symbolic links
echo "Link configs to ${HOME}"
DOTFILES="$(cd "$(dirname "$0")"; pwd)";
ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

# Remove redundant history file
rm ~/.zsh_history 2> /dev/null
