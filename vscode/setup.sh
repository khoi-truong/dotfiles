#!/usr/bin/env bash
# Visual Studio Code — link user settings and install extensions.
# Not run by ./setup.sh by default; use `./setup.sh vscode` or `--all`.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
VSCODE_HOME="${HOME}/Library/Application Support/Code/User"
VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

info "Setting up Visual Studio Code..."

# The app bundle ships the `code` CLI but doesn't put it on $PATH.
if [ -x "${VSCODE_CLI}" ]; then
  link "${VSCODE_CLI}" "$(brew_prefix)/bin/code"
fi

if ! command -v code >/dev/null 2>&1; then
  warn "code CLI unavailable — is Visual Studio Code installed? Skipping."
  exit 0
fi

link "${CURRENT_DIR}/settings.json" "${VSCODE_HOME}/settings.json"
link "${CURRENT_DIR}/keybindings.json" "${VSCODE_HOME}/keybindings.json"
link "${CURRENT_DIR}/snippets" "${VSCODE_HOME}/snippets"

info "Installing extensions..."
while read -r extension; do
  [ -n "${extension}" ] || continue
  code --install-extension "${extension}" || warn "failed: ${extension}"
done <"${CURRENT_DIR}/extensions.vscode"

# The editor's Python environment: Pylance resolves imports against the
# interpreter pyrightconfig.json names. CI does not use it; it runs the tools
# through uvx. The pytest pin mirrors test.yml and scripts/ci/lint-local.sh.
if command -v uv >/dev/null 2>&1; then
  info "Creating the editor venv..."
  (cd "${DOTFILES}" && { [ -d .venv ] || uv venv; } && uv pip install pytest==9.1.1) ||
    warn "editor venv setup failed"
else
  warn "uv unavailable — skipping the editor venv (run ./setup.sh mise first)."
fi

ok "Visual Studio Code configured."
