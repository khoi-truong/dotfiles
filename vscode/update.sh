#!/bin/sh

set -e

if [ "$(uname -s)" = "Darwin" ]; then
	VSCODE_HOME="$HOME/Library/Application Support/Code"
else
	VSCODE_HOME="$HOME/.config/Code"
fi

VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
[ -x "${VSCODE_CLI}" ] && ln -fs "${VSCODE_CLI}" "/usr/local/bin/code"

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";
code --list-extensions >"${CURRENT_DIR}/extensions.vscode"
