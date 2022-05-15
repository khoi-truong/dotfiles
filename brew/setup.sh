#!/bin/sh

echo "🍺 Homebrew Bundle install..."
brew bundle install -f --verbose
brew bundle cleanup -f
echo "🚀 Homebrew Bundle install completed! 🚀"
