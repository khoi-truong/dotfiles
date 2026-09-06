#!/usr/bin/env bash
# Regenerate vscode/extensions.vscode from the currently installed extensions.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

if [ -x "${VSCODE_CLI}" ]; then
  link "${VSCODE_CLI}" "$(brew_prefix)/bin/code"
fi

command -v code >/dev/null 2>&1 || die "code CLI not found."

code --list-extensions >"${CURRENT_DIR}/extensions.vscode"
ok "Wrote ${CURRENT_DIR}/extensions.vscode"
