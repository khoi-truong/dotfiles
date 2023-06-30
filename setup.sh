#!/bin/sh

DOTFILES="$(cd "$(dirname "$0")"; pwd)";

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.setup.sh` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Install Homebrew
echo ""
echo "Download and install Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

execute() {
  chmod +x "$1"; "$1";
}

for file in ./{git,brew,macos,terminal,iterm,alfred,misc}/setup.sh; do
	[ -r "$file" ] && [ -f "$file" ] && execute "$file"
done;
unset file;
unset execute;

# Make symbolic links
echo ""
echo "Link configs to ${HOME}"
ln -fs "${DOTFILES}/zsh/zshenv" ~/.zshenv
ln -fs "${DOTFILES}/zsh/zshrc" ~/.zshrc
mkdir -p ~/.ssh
ln -fs "${DOTFILES}/ssh/config" ~/.ssh/config

# Remove redundant history file
rm ~/.zsh_history 2> /dev/null
rm -rf ~/.zsh_sessions 2> /dev/null

echo ""
echo "Setting up completed!"
echo "🚀🚀🚀"
echo ""
