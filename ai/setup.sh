#!/usr/bin/env bash
# ai — Claude Code, oh-my-pi and GitHub Copilot CLI configuration.
#
# Only the declarative config is versioned. Credentials are NOT:
#   ~/.claude.json                       project history + auth
#   ~/.claude/.credentials.json          OAuth tokens
#   ~/.config/github-copilot/apps.json   OAuth tokens
#   ~/.omp/agent/agent.db                omp logins and API keys (the DeepSeek
#                                        key lives in 1Password; see
#                                        ai/omp/models.yml)
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
# (~/.claude/skills/wiki, …) are left untouched. omp gets the whole directory
# (below).
for skill in "${CURRENT_DIR}"/shared/skills/*/; do
  [ -d "$skill" ] || continue
  link "${skill%/}" "${HOME}/.claude/skills/$(basename "$skill")"
done

if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>/dev/null || echo 'installed')"
else
  warn "claude not found — installed by brew/setup.sh (cask \"claude-code\")."
fi

# --- oh-my-pi --------------------------------------------------------------
# Installed by brew/Brewfile (can1357/tap/omp). /settings and /model write
# config.yml in place, so those edits show up as repo diffs to commit or
# discard. agent.db, sessions and the rest of ~/.omp stay local.
OMP_DIR="${HOME}/.omp/agent"
for item in config.yml models.yml mcp.json APPEND_SYSTEM.md commands; do
  link "${CURRENT_DIR}/omp/${item}" "${OMP_DIR}/${item}"
done
link "${CURRENT_DIR}/shared/skills" "${OMP_DIR}/skills"
# Same global rules as Claude Code.
link "${CURRENT_DIR}/shared/rules/common.md" "${OMP_DIR}/AGENTS.md"

if command -v omp >/dev/null 2>&1; then
  ok "omp $(omp --version 2>/dev/null || echo 'installed')"
else
  warn "omp not found — installed by brew/setup.sh (can1357/tap/omp)."
fi
if [ -d "${HOME}/.pi" ]; then
  warn "${HOME}/.pi is left over from pi; delete it once nothing there is needed."
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
for dir in "${HOME}/.claude" "${HOME}/.claude/skills" "${OMP_DIR}" "${HOME}/.copilot"; do
  [ -d "$dir" ] || continue
  for entry in "$dir"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      warn "dangling symlink: $entry -> $(readlink "$entry")"
    fi
  done
done

ok "AI tooling configured."
