#!/usr/bin/env bash
# ai — Claude Code and GitHub Copilot CLI configuration.
#
# Only the declarative config is versioned. Credentials are NOT:
#   ~/.claude.json                       project history + auth
#   ~/.claude/.credentials.json          OAuth tokens
#   ~/.config/github-copilot/apps.json   OAuth tokens
# Those stay on the machine and are re-created by logging in.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up AI tooling..."

# --- Claude Code -----------------------------------------------------------
# claude/CLAUDE.md holds the OMC orchestration rules and imports rules/common.md.
link "${CURRENT_DIR}/claude/settings.json" "${HOME}/.claude/settings.json"
link "${CURRENT_DIR}/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"

# Personal skills — one symlink per skill dir so OMC-managed skills
# (~/.claude/skills/wiki, …) are left untouched.
for skill in "${CURRENT_DIR}"/claude/skills/*/; do
  [ -d "$skill" ] || continue
  link "${skill%/}" "${HOME}/.claude/skills/$(basename "$skill")"
done

if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>/dev/null || echo 'installed')"
else
  warn "claude not found — installed by brew/setup.sh (cask \"claude-code\")."
fi

# --- GitHub Copilot CLI ----------------------------------------------------
# Two separate products, both used:
#   `copilot`             the standalone Copilot CLI, config in ~/.copilot
#   `gh copilot suggest`  the gh extension
link "${CURRENT_DIR}/copilot/settings.json" "${HOME}/.copilot/settings.json"
link "${CURRENT_DIR}/copilot/copilot-instructions.md" "${HOME}/.copilot/copilot-instructions.md"

if command -v gh >/dev/null 2>&1; then
  if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    ok "gh-copilot extension already installed"
  else
    info "Installing the gh-copilot extension..."
    gh extension install github/gh-copilot || warn "gh extension install failed (run \`gh auth login\` first)."
  fi
else
  warn "gh not found — installed by brew/setup.sh."
fi

# --- secrets ---------------------------------------------------------------
# ai/env.local.zsh is gitignored and sourced by ai/aliases.zsh. Put API keys
# (e.g. ANTHROPIC_API_KEY) there — never in a tracked file.
if [ ! -f "${CURRENT_DIR}/env.local.zsh" ]; then
  cp "${CURRENT_DIR}/env.local.zsh.example" "${CURRENT_DIR}/env.local.zsh"
  ok "created ai/env.local.zsh (gitignored) — add API keys there"
fi

ok "AI tooling configured."
