#!/usr/bin/env bash
# ai — Claude Code, oh-my-pi, GitHub Copilot CLI and herdr configuration.
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
# An older version of this script linked omp/extensions, which the repo no
# longer ships. The dangling link makes anything writing an extension fail
# (herdr's omp integration, for one), so drop it.
if [ -L "${OMP_DIR}/extensions" ] && [ ! -e "${OMP_DIR}/extensions" ]; then
  rm "${OMP_DIR}/extensions"
  ok "removed stale ${OMP_DIR}/extensions link"
fi
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

# True when `herdr plugin list` reports the given plugin id. `herdr plugin
# config-dir` cannot answer this: it only computes a path and exits 0 for any
# string, whether the plugin exists or not.
herdr_plugin_installed() {
  herdr plugin list --plugin "$1" --json 2>/dev/null |
    grep -q '"plugins":\[[^]]'
}

# --- herdr -----------------------------------------------------------------
# Terminal workspace manager for agents (brew/Brewfile). The config is
# versioned; logs, the socket, plugin binaries and plugin state stay local.
link "${CURRENT_DIR}/herdr/config.toml" "${HOME}/.config/herdr/config.toml"

if command -v herdr >/dev/null 2>&1; then
  for integration in claude omp copilot; do
    if herdr_out="$(herdr integration install "${integration}" 2>&1)"; then
      ok "herdr integration: ${integration}"
    else
      warn "herdr integration install ${integration} failed: ${herdr_out}"
    fi
  done
  # herdr rewrites the harness settings files and drops the trailing newline
  # .editorconfig requires, which CI then fails on. Put it back.
  for settings in "${CURRENT_DIR}/claude/settings.json" "${CURRENT_DIR}/copilot/settings.json"; do
    [ -f "${settings}" ] || continue
    [ -n "$(tail -c 1 "${settings}")" ] || continue
    printf '\n' >>"${settings}"
    ok "restored trailing newline in ${settings#"${CURRENT_DIR}/"}"
  done
  # Plugins are installed here, pinned to a release tag by herdr/plugins.list.
  # `herdr plugin` has no update command — reinstalling is updating — and an
  # unpinned install re-fetches the default branch, so leaving the ref off
  # would silently move a plugin to current HEAD. This script is re-run after
  # every `brew upgrade herdr`, after a plugin install and on a new machine, so
  # that drift would be routine.
  #
  # Installs stop for the manifest preview (no --yes) because plugins run
  # unsandboxed as your user. Once a plugin is installed, this links the
  # versioned templates under herdr/plugins/<plugin id>/ into its config dir;
  # a plugin with no template dir simply gets nothing linked.
  #
  # "Installed?" is asked with `plugin list`, not `plugin config-dir`:
  # config-dir just computes a path and succeeds for any string, installed or
  # not, so testing it would skip every install. An uninstalled id lists as an
  # empty plugins array.
  #
  # The list is read on fd 3, not stdin: the install prompt reads from stdin,
  # and would otherwise swallow the next plugin's line as its answer.
  while read -r plugin repo ref <&3; do
    case "${plugin}" in '' | \#*) continue ;; esac
    if ! herdr_plugin_installed "${plugin}"; then
      info "herdr plugin ${plugin} not installed — installing ${repo}@${ref}."
      info "Read the manifest preview; this is not passed --yes."
      if ! herdr plugin install "${repo}" --ref "${ref}"; then
        warn "herdr plugin ${repo} install failed or was declined — skipping."
        continue
      fi
      if ! herdr_plugin_installed "${plugin}"; then
        warn "herdr plugin ${plugin} still not listed after install — skipping."
        continue
      fi
    fi
    plugin_config="$(herdr plugin config-dir "${plugin}" 2>/dev/null)" || plugin_config=""
    if [ -z "${plugin_config}" ]; then
      warn "herdr plugin ${plugin} has no config dir — skipping."
      continue
    fi
    for item in "${CURRENT_DIR}"/herdr/plugins/"${plugin}"/*; do
      [ -e "$item" ] || continue
      link "$item" "${plugin_config}/$(basename "$item")"
    done
  done 3<"${CURRENT_DIR}/herdr/plugins.list"
  ok "herdr $(herdr --version 2>/dev/null || echo installed)"
else
  warn "herdr not found — installed by brew/setup.sh."
fi

# --- GitHub Copilot CLI ----------------------------------------------------
# The standalone `copilot` CLI, config in ~/.copilot. The github/gh-copilot gh
# extension is archived upstream and no longer installed.
link "${CURRENT_DIR}/copilot/settings.json" "${HOME}/.copilot/settings.json"
link "${CURRENT_DIR}/copilot/copilot-instructions.md" "${HOME}/.copilot/copilot-instructions.md"

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
for dir in "${HOME}/.claude" "${HOME}/.claude/skills" "${OMP_DIR}" "${HOME}/.copilot" \
  "${HOME}/.config/herdr"; do
  [ -d "$dir" ] || continue
  for entry in "$dir"/*; do
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      warn "dangling symlink: $entry -> $(readlink "$entry")"
    fi
  done
done

ok "AI tooling configured."
