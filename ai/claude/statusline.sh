#!/usr/bin/env bash
# Claude Code statusLine, referenced from ai/claude/settings.json: stdin JSON ->
# hud-ctx-fix.mjs -> claude-hud, with its rows rearranged below. Prints a plain
# "model dir" line when node or the HUD is missing or renders nothing, and
# always exits 0.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
input=$(cat 2>/dev/null || true)

# mise runs without shims (hook_env.chpwd_only), so PATH may lack node in a
# shell Claude did not inherit from an activated zsh; fall back to mise's own.
node_bin() {
  local candidate mise="${MISE_DATA_DIR:-${HOME:-}/.local/share/mise}"
  for candidate in \
    "$(command -v node 2>/dev/null)" \
    "${mise}/shims/node" \
    "${mise}/installs/node/latest/bin/node"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# The newest claude-hud the plugin cache holds, like the plugin's own launcher
# does, so updates never need a setup step. Versions sort numerically; a
# directory that is not a plain semver is ignored.
hud_entry() {
  local file version
  for file in "${CLAUDE_DIR}"/plugins/cache/*/claude-hud/*/dist/index.js; do
    [[ -f "$file" ]] || continue
    version=$(basename "$(dirname "$(dirname "$file")")")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && printf '%s\t%s\n' "$version" "$file"
  done | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | cut -f2-
}

# "<label or model> <dir>", or "Claude" for what cannot be read.
plain() {
  local model="" dir="" label="${CC_PROVIDER_LABEL:-}"
  if command -v jq >/dev/null 2>&1; then
    model=$(jq -r '.model.display_name // .model.id // empty' <<<"$input" 2>/dev/null) || model=""
    dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null) || dir=""
  fi
  [[ -z "$label" ]] || model=$label
  [[ -z "$dir" ]] || dir=$(basename "$dir")
  printf '%s\n' "${model:-Claude}${dir:+ ${dir}}"
}

# usagebar (herdr/plugins.list) caches Claude's 5h/7d rate-limit windows and
# the prompt-cache expiry from this stdin payload; nothing else reports them,
# so without this branch the sidebar $limit and Claude rate-limit toasts stay
# empty. It is a tee side-branch, not a pipeline stage: `usagebar statusline`
# prints its own summary rather than passing JSON through, so chaining it
# inline would feed the HUD garbage and drop the provider label that
# herdr/team.sh asserts on.
#
# herdr installs a plugin to <plugin id>-<first 12 hex of sha256(plugin id)>,
# which carries no version or commit, so this path survives reinstalls and tag
# bumps. If it ever looks wrong:
#   herdr plugin list --plugin usagebar --json
USAGEBAR="${HOME:-}/.config/herdr/plugins/github/usagebar-33803b79d616/bin/usagebar"

# Only this payload reports Claude's 5h/7d windows, and the status line it
# renders is for the user: the model that routes work between Pro, ccd and omp
# never sees it. Cache the windows so ai/claude/quota-advice.sh can hand them
# to Claude on the next prompt. Account-wide on purpose — the limits are, so
# whichever pane rendered last refreshes them for all of them.
QUOTA_CACHE="${CLAUDE_DIR}/cache/pro-quota.json"

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

# Rearranges claude-hud's rows. Every literal below is claude-hud v0.15.0
# output, so a HUD upgrade that rewords one only costs the tidy-up, never the
# line. Stdin is the HUD's rows, stdout the rearranged ones.
tidy() {
  awk -v sep=' │ ' '
    function plain(s) { gsub(/\033\[[0-9;]*m/, "", s); return s }
    # claude-hud joins the tools of one row with " | " (a regex, hence the bracket).
    function tools(s,    n, p, i, num, running, total) {
      n = split(plain(s), p, " [|] ")
      for (i = 1; i <= n; i++) {
        if (sub(/^◐ /, "", p[i])) {
          sub(/:.*/, "", p[i])
          running = running (running == "" ? "" : ", ") p[i]
        } else if (p[i] ~ /^✓ .* ×[0-9]+$/) {
          num = p[i]; sub(/.* ×/, "", num)
          total += num
        }
      }
      if (running != "") running = "\033[33m◐\033[0m " running
      total = total > 0 ? "⚒ " total : ""
      return running (running != "" && total != "" ? sep : "") total
    }
    # Tool parts, not agents: those end in an elapsed "(2m)".
    function tool_parts(s,    n, p, i) {
      n = split(plain(s), p, " [|] ")
      for (i = 1; i <= n; i++)
        if (p[i] !~ /^✓ .* ×[0-9]+$/ && p[i] !~ /^\+[0-9]+ more$/ && (p[i] !~ /^◐ / || p[i] ~ /\([^)]*\)$/)) return 0
      return 1
    }
    function is_tools(s) { return plain(s) ~ /^(✓|◐) / && tool_parts(s) }
    # The HUD wraps long rows at separators, so duration or speed can start a
    # row, and the merged context group can spill its usage, cache and tools
    # onto rows of their own.
    {
      # "Cache ⏱ until 03:00 PM" reads as "Cache until 03:00 PM".
      gsub(/⏱ until/, "until")
      if (plain($0) ~ /^Context /) { line[++count] = $0; merging = 1; next }
      n = split($0, part, sep)
      kept = ""
      for (i = 1; i <= n; i++) {
        p = plain(part[i])
        if ((NR > 1 || i > 1) && p ~ /^⏱/) {
          # "⏱️  1h 23m" (with its variation selector) reads as "⏱ 1h23m".
          if (match(part[i], /⏱[^0-9<]*/)) part[i] = substr(part[i], 1, RSTART - 1) "⏱ " substr(part[i], RSTART + RLENGTH)
          while (match(part[i], /[0-9][dhm] [0-9]/)) part[i] = substr(part[i], 1, RSTART + 1) substr(part[i], RSTART + 3)
          duration = duration sep part[i]
        } else if ((NR > 1 || i > 1) && p ~ /^Compactions: /) compactions = compactions sep part[i]
        else if ((NR > 1 || i > 1) && p ~ /tok\/s$/) {
          # The HUD has no option for its speed label.
          sub(/out: /, "", part[i])
          speed = speed sep part[i]
        } else kept = kept (kept == "" ? "" : sep) part[i]
      }
      if (plain(kept) ~ /^[[:space:]]*$/) next
      if (merging && plain(kept) ~ /^(Usage|Weekly|Cache) /) line[count] = line[count] sep kept
      else if (merging && tool_parts(kept)) {
        # A wrap inside the tools group drops its " | ", which the totals need.
        nlast = split(line[count], last, sep)
        line[count] = line[count] (is_tools(last[nlast]) ? " | " : sep) kept
      } else { line[++count] = kept; merging = 0 }
    }
    END {
      moved = duration compactions speed
      for (i = 2; i <= count; i++) {
        context = plain(line[i]) ~ /^Context /
        n = split(line[i], part, sep)
        rebuilt = ""
        for (j = 1; j <= n; j++) {
          if (is_tools(part[j])) {
            if (j > 1 && context) { rebuilt = rebuilt moved; moved = "" }
            part[j] = tools(part[j])
          }
          rebuilt = rebuilt (j == 1 ? "" : sep) part[j]
        }
        if (context) { rebuilt = rebuilt moved; moved = "" }
        line[i] = rebuilt
      }
      if (moved != "") line[1] = line[1] moved
      for (i = 1; i <= count; i++) print line[i]
    }'
}

payload=$input
if [ -x "${USAGEBAR}" ]; then
  printf '%s\n' "${payload}" | "${USAGEBAR}" statusline >/dev/null 2>&1 &
fi
printf '%s\n' "${payload}" | cache_quota

out=""
if node=$(node_bin) && hud=$(hud_entry) && [[ -n "$hud" && -f "${HERE}/hud-ctx-fix.mjs" ]]; then
  # Claude Code pads the status line by two columns on each side.
  if [[ "${COLUMNS:-0}" =~ ^[0-9]+$ && "${COLUMNS:-0}" -gt 4 ]]; then
    export COLUMNS=$((COLUMNS - 4))
  fi
  out=$(printf '%s' "$input" |
    "$node" "${HERE}/hud-ctx-fix.mjs" 2>/dev/null |
    "$node" "$hud" 2>/dev/null) || out=""
  if [[ -n "${out//[[:space:]]/}" ]]; then
    out=$(printf '%s\n' "$out" | tidy) || out=""
  fi
fi
if [[ -n "${out//[[:space:]]/}" ]]; then
  printf '%s\n' "$out"
else
  plain
fi
exit 0
