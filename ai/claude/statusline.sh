#!/usr/bin/env bash
# Claude Code statusLine, referenced from ai/claude/settings.json.
#
# This is a script rather than a one-liner in settings.json because the
# pipeline needs bash (process substitution), and because the plugin path
# below wants a comment that JSON cannot hold.
set -uo pipefail

NODE="${HOME}/.local/share/mise/shims/node"
HUD="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/hud/omc-hud.mjs"

# usagebar (herdr/plugins.list) caches Claude's 5h/7d rate-limit windows and
# the prompt-cache expiry from this stdin payload; nothing else reports them,
# so without this branch the sidebar $limit and Claude rate-limit toasts stay
# empty. It is a tee side-branch, not a pipeline stage: `usagebar statusline`
# prints its own summary rather than passing JSON through, so chaining it
# inline would feed omc-hud garbage and drop the provider label that
# herdr/team.sh asserts on.
#
# herdr installs a plugin to <plugin id>-<first 12 hex of sha256(plugin id)>,
# which carries no version or commit, so this path survives reinstalls and tag
# bumps. If it ever looks wrong:
#   herdr plugin list --plugin usagebar --json
USAGEBAR="${HOME}/.config/herdr/plugins/github/usagebar-33803b79d616/bin/usagebar"

render() {
  "${NODE}" "${HOME}/.dotfiles/ai/claude/hud-ctx-fix.mjs" |
    "${NODE}" "${HUD}" |
    perl -CSD -pe 's/Model:\x{a0}?\s?//g; s/session://g; s/ctx://g'
}

if [ -x "${USAGEBAR}" ]; then
  tee >("${USAGEBAR}" statusline >/dev/null 2>&1) | render
else
  render
fi
