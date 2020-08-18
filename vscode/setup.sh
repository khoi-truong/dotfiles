#!/bin/sh

[ "$(uname -s)" != "Darwin" ] && exit 0

echo ""
echo "Setting up Visual Studio Code..."

VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
[ -x "${VSCODE_CLI}" ] && ln -fs "${VSCODE_CLI}" "/usr/local/bin/code"

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";

if command -v code >/dev/null; then
	VSCODE_HOME="$HOME/Library/Application Support/Code"
	mkdir -p "$VSCODE_HOME/User"

	ln -sf "$CURRENT_DIR/settings.json" "$VSCODE_HOME/User/settings.json"
	ln -sf "$CURRENT_DIR/keybindings.json" "$VSCODE_HOME/User/keybindings.json"
	ln -sf "$CURRENT_DIR/snippets" "$VSCODE_HOME/User/snippets"

	while read -r module; do
		code --install-extension "$module" || true
	done <"$CURRENT_DIR/extensions.vscode"
fi
