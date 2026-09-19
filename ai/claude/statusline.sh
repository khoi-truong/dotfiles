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

# Only this payload reports Claude's 5h/7d windows, and the status line it
# renders is for the user: the model that routes work between Pro, ccd and omp
# never sees it. Cache the windows so ai/claude/quota-advice.sh can hand them
# to Claude on the next prompt. Account-wide on purpose — the limits are, so
# whichever pane rendered last refreshes them for all of them.
QUOTA_CACHE="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/cache/pro-quota.json"

# A provider pane reports its own endpoint's limits, not the Pro window, so it
# must never overwrite the cache. CC_PROVIDER is what ai/claude/providers.zsh
# exports and `cc` unsets; ai/herdr/team.sh asserts on the same variable.
cache_quota() {
  [ -z "${CC_PROVIDER:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "${QUOTA_CACHE}")" 2>/dev/null || return 0
  tmp="${QUOTA_CACHE}.$$"
  # `select` drops a payload with no rate_limits, leaving an empty file that
  # the -s test rejects, so a stale-but-real cache survives a payload that
  # cannot refresh it. mv is atomic: the hook never reads a half-written file.
  if jq -c --argjson now "$(date +%s)" \
      'select(.rate_limits != null) | {cached_at: $now, rate_limits}' \
      >"${tmp}" 2>/dev/null && [ -s "${tmp}" ]; then
    mv -f "${tmp}" "${QUOTA_CACHE}"
  else
    rm -f "${tmp}"
  fi
}

render() {
  "${NODE}" "${HOME}/.dotfiles/ai/claude/hud-ctx-fix.mjs" |
    "${NODE}" "${HUD}" |
    perl -CSD -pe 's/Model:\x{a0}?\s?//g; s/session://g; s/ctx://g'
}

if [ -x "${USAGEBAR}" ]; then
  tee >("${USAGEBAR}" statusline >/dev/null 2>&1) >(cache_quota) | render
else
  tee >(cache_quota) | render
fi
