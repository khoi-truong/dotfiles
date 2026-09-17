#!/usr/bin/env bash
# ai — Claude Code, pi and GitHub Copilot CLI configuration.
#
# Only the declarative config is versioned. Credentials are NOT:
#   ~/.claude.json                       project history + auth
#   ~/.claude/.credentials.json          OAuth tokens
#   ~/.config/github-copilot/apps.json   OAuth tokens
#   ~/.pi/agent/auth.json                pi API keys (the DeepSeek key lives
#                                        in 1Password; see ai/pi/models.json)
# Those stay on the machine and are re-created by logging in.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

info "Setting up AI tooling..."

# --- Claude Code -----------------------------------------------------------
# claude/CLAUDE.md holds the OMC orchestration rules and imports
# shared/rules/common.md.
# Tools that edit settings.json (Claude Code, iTerm's cc-status installer)
# replace the symlink with a real file. Re-running this backs that file up and
# relinks; fold anything new from the backup into claude/settings.json first.
link "${CURRENT_DIR}/claude/settings.json" "${HOME}/.claude/settings.json"
link "${CURRENT_DIR}/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"

# Shared skills — one symlink per skill dir so OMC-managed skills
# (~/.claude/skills/wiki, …) are left untouched. pi reads shared/skills in
# place (pi/settings.json `skills`), so it gets no links.
for skill in "${CURRENT_DIR}"/shared/skills/*/; do
  [ -d "$skill" ] || continue
  link "${skill%/}" "${HOME}/.claude/skills/$(basename "$skill")"
done

if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>/dev/null || echo 'installed')"
else
  warn "claude not found — installed by brew/setup.sh (cask \"claude-code\")."
fi

# --- pi --------------------------------------------------------------------
# Installed by mise (mise/global.toml). pi writes settings.json in place
# (/model Ctrl+S, pi install, lastChangelogVersion), so the symlink survives
# and those edits show up as repo diffs to commit or discard.
# auth.json, models-store.json, trust.json, sessions/ and npm/ stay local.
PI_DIR="${HOME}/.pi/agent"
for item in settings.json models.json web-search.json mcp.json APPEND_SYSTEM.md agents extensions prompts themes; do
  link "${CURRENT_DIR}/pi/${item}" "${PI_DIR}/${item}"
done
# Same global rules as Claude Code.
link "${CURRENT_DIR}/shared/rules/common.md" "${PI_DIR}/AGENTS.md"

if command -v pi >/dev/null 2>&1; then
  ok "pi $(pi --version 2>/dev/null || echo 'installed')"
else
  warn "pi not found — installed by mise (mise/global.toml)."
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

# --- dangling links -------------------------------------------------------
# Files moved in the repo leave stale links behind. Report them; the user
# decides whether to delete.
for dir in "${HOME}/.claude" "${HOME}/.claude/skills" "${PI_DIR}" "${HOME}/.copilot"; do
  [ -d "$dir" ] || continue
  for entry in "$dir"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      warn "dangling symlink: $entry -> $(readlink "$entry")"
    fi
  done
done

ok "AI tooling configured."
