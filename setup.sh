#!/bin/sh

DOTFILES="$(cd "$(dirname "$0")"; pwd)";

# Install Homebrew casks
echo "Homebrew Bundle..."
cd ${DOTFILES}/macos
brew bundle install -f --verbose
brew bundle cleanup -f
cd ..

# Setup macOS defaults
execute() {
    chmod +x "$1"; "$1";
}

for file in ./{brew,macos,terminal,iterm,warp,alfred,misc,vscode}/setup.sh; do
	[ -r "$file" ] && [ -f "$file" ] && execute "$file"
done;
unset file;
unset execute;

# Make symbolic links
echo ""
echo "Link configs to ${HOME}"
ln -fs "${DOTFILES}/zsh/zshenv" ~/.zshenv
ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
ln -fs "${DOTFILES}/git/gitconfig" ~/.gitconfig
ln -fs "${DOTFILES}/git/gitignore" ~/.gitignore
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

# Remove redundant history file
rm ~/.zsh_history 2> /dev/null
rm -rf ~/.zsh_sessions 2> /dev/null

echo ""
echo "Setting up completed!"
echo "🚀🚀🚀"
echo ""
