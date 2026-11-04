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
# relinks, and the warning names the backup: diff it against
# claude/settings.json and fold in anything wanted.
link "${CURRENT_DIR}/claude/settings.json" "${HOME}/.claude/settings.json"
link "${CURRENT_DIR}/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"

# claude-hud reads its layout from here; the plugin itself is installed from
# the marketplace in settings.json, never with `/hud install` (it rewrites
# settings.json). A copy, not a link: claude-hud opens config.json with
# O_NOFOLLOW and reports a symlink as "can't be read". `/hud` edits the copy,
# so fold anything wanted back into claude/claude-hud.json.
copy "${CURRENT_DIR}/claude/claude-hud.json" "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/claude-hud/config.json"

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
  # herdr only recognises its hook by the absolute-path string, so it appends a
  # second SessionStart entry beside the tracked "$HOME" one. Drop that copy:
  # the tracked file must not carry a home path, and the hook must run once.
  herdr_strip() {
    local file="$1" filter="$2" tmp
    [ -f "${file}" ] || return 0
    tmp="$(mktemp)"
    if jq --arg abs "${HOME}" "${filter}" "${file}" >"${tmp}"; then
      cmp -s "${tmp}" "${file}" || {
        cat "${tmp}" >"${file}"
        ok "dropped herdr's absolute-path hook from ${file#"${CURRENT_DIR}/"}"
      }
    fi
    rm -f "${tmp}"
  }
  # $abs is a jq variable, not a shell one.
  # shellcheck disable=SC2016
  herdr_strip "${CURRENT_DIR}/claude/settings.json" \
    'if .hooks.SessionStart then .hooks.SessionStart |= map(select([.hooks[]?.command // ""] | any(startswith("bash \u0027" + $abs + "/")) | not)) else . end'
  # shellcheck disable=SC2016
  herdr_strip "${CURRENT_DIR}/copilot/settings.json" \
    'if .hooks.SessionStart then .hooks.SessionStart |= map(select((.bash // "") | startswith("bash \u0027" + $abs + "/") | not)) else . end'
  # herdr rewrites the harness settings files and drops the trailing newline
  # .editorconfig requires, which CI then fails on. Put it back.
  for settings in "${CURRENT_DIR}/claude/settings.json" "${CURRENT_DIR}/copilot/settings.json"; do
    [ -f "${settings}" ] || continue
    [ -n "$(tail -c 1 "${settings}")" ] || continue
    printf '\n' >>"${settings}"
    ok "restored trailing newline in ${settings#"${CURRENT_DIR}/"}"
  done
  # Plugins are pinned in herdr/plugins.toml; plugins.sh is sourced so its
  # `link` calls stay inside this script's transaction. A bad manifest or no
  # Python 3.11 (2) warns and the rest of setup carries on; a failed link (1)
  # fails setup, as it would anywhere else here.
  # shellcheck source=ai/herdr/plugins.sh
  . "${CURRENT_DIR}/herdr/plugins.sh"
  plugins_rc=0
  herdr_plugins_apply || plugins_rc=$?
  case "${plugins_rc}" in
    0) ;;
    2) warn "herdr plugins not applied; see above." ;;
    *) exit "${plugins_rc}" ;;
  esac
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
# ai/env.local.zsh is generated here from 1Password and sourced by
# ai/aliases.zsh. It is regenerated wholesale on every run, so it is not a
# place to hand-write anything — a key belongs in the 1Password item, which
# stays the single place a key is named and kept.
#
# The keys are dumped to disk rather than read through `op` at launch because
# `op read` raises a biometric prompt, and an agent pane ai/herdr/team.sh
# spawned cannot answer one — it reads as a hung spawn and stops the whole
# unattended workflow. This script is run by a human, so it is the one place
# that prompt is answerable. 1Password stays the master copy.
# The 1Password ids live in ai/op.local.env (gitignored): OP_ACCOUNT, OP_VAULT,
# OP_ITEM.
if [ -f "${CURRENT_DIR}/op.local.env" ]; then
  # shellcheck source=/dev/null
  . "${CURRENT_DIR}/op.local.env"
fi
OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"
SECRETS="${CURRENT_DIR}/env.local.zsh"

if [ -z "${OP_VAULT:-}" ] || [ -z "${OP_ITEM:-}" ]; then
  warn "ai/op.local.env missing — skipping ai/env.local.zsh"
elif ! command -v op >/dev/null 2>&1; then
  warn "1password-cli not found — skipping ai/env.local.zsh"
elif ! command -v jq >/dev/null 2>&1; then
  warn "jq not found — skipping ai/env.local.zsh"
elif ! op_json="$(op item get "$OP_ITEM" --vault "$OP_VAULT" \
  --account "$OP_ACCOUNT" --format json 2>/dev/null)"; then
  warn "could not read the 1Password item — unlock 1Password and re-run."
  warn "ai/env.local.zsh left as-is."
else
  # Concealed fields only: passwords and API keys, not usernames or notes.
  # The field label becomes the variable name verbatim — the item is the place
  # names are decided, so renaming a field there is the whole edit. A label
  # that is not a shell identifier is reported, not quietly mangled into one.
  op_exports="$(printf '%s' "$op_json" | jq -r '
    .fields[]
    | select((.value // "") != "" and .id != "notesPlain")
    | (.label // .id) as $name
    | if .type != "CONCEALED"
      then "# skipped: \($name) is a plain-text field, not a password field"
      elif ($name | test("^[A-Za-z_][A-Za-z0-9_]*$") | not)
      then "# skipped: \($name) is not a usable variable name"
      else "export \($name)=\(.value | @sh)"
      end')"

  # umask before create: the file must never exist world-readable, not even
  # for the instant between creat(2) and chmod(2).
  (
    umask 077
    {
      printf '%s\n' \
        "# Generated by ai/setup.sh from 1Password (ids in ai/op.local.env)." \
        "# Hand edits are lost on the next run — add the key to the item" \
        "# instead. Gitignored; mode 600." \
        ""
      printf '%s\n' "$op_exports"
    } >"${SECRETS}.tmp"
  )
  mv -f "${SECRETS}.tmp" "$SECRETS"
  ok "wrote ai/env.local.zsh ($(grep -c '^export ' "$SECRETS") keys, mode 600)"
  { printf '%s\n' "$op_exports" | grep '^# skipped: ' || true; } | while read -r line; do
    warn "${line#\# skipped: }"
  done
fi
unset op_json op_exports

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
