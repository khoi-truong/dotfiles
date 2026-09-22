#!/usr/bin/env bash
# UserPromptSubmit hook, referenced from ai/claude/settings.json.
#
# Claude never sees the status line — it is rendered for the user — so the
# rate-limit windows that ai/claude/statusline.sh caches would otherwise not
# reach the model that routes the work. This prints a routing advisory on
# stdout, which Claude Code injects as additional context.
#
# It is deliberately silent below the threshold: an advisory on every prompt
# is noise, and noise gets ignored exactly when it starts mattering.
set -uo pipefail

CACHE="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/cache/pro-quota.json"

# On a provider pane the Pro windows are not the budget being spent, and the
# cache was written by some other (Pro) session. Advising from it would be a
# lie. Same variable ai/herdr/team.sh asserts on.
[ -z "${CC_PROVIDER:-}" ] || exit 0

# The advice routes work to ccd and omp panes, which only exist inside herdr.
# A plain session has nowhere to route to, so it gets no advice at all.
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -r "${CACHE}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

now="$(date +%s)"

# A window whose reset is in the past has already rolled over, so the cached
# percentage describes a window that no longer exists. Absence of data is not
# evidence of headroom: say nothing rather than advise from fiction.
read -r five seven five_reset ok < <(
  jq -r --argjson now "${now}" '
    .rate_limits as $r
    | [ ($r.five_hour.used_percentage // -1),
        ($r.seven_day.used_percentage // -1),
        ($r.five_hour.resets_at // 0),
        (if ($r.five_hour.resets_at // 0) > $now then "ok" else "stale" end) ]
    | @tsv' "${CACHE}" 2>/dev/null
) || exit 0

[ "${ok:-stale}" = "ok" ] || exit 0
[ "${five:--1}" -ge 0 ] 2>/dev/null || exit 0

resets="$(date -r "${five_reset}" '+%H:%M' 2>/dev/null || echo '?')"
status="Pro 5h window ${five}% used (resets ${resets}), 7d ${seven}%."

# Thresholds mirror the routing rule in README "Which to use": work whose
# mistakes a lint run or a diff read catches cheaply is what moves first.
if [ "${seven}" -ge 80 ]; then
  verdict="7d window is nearly spent and refills slowly. Keep Pro for decisions only — planning, review, security, anything that ships silently. Everything executable goes to ccd, research to omp."
elif [ "${five}" -ge 75 ]; then
  verdict="Pro is tight. Reserve it for planning, review and work that shapes later work; hand implementation, tests, lint and CI fixes to ccd, and web or docs lookups to omp."
elif [ "${five}" -ge 50 ]; then
  verdict="Prefer ccd for implementation, tests, lint and CI fixes when a mechanical check would catch a wrong answer. Planning and review stay on Pro."
else
  exit 0
fi

printf '[quota] %s %s\n' "${status}" "${verdict}"
printf '[quota] Quota is a tiebreaker, not the trigger: below the protocol break-even, doing it inline on Pro still costs less than a spawn/dispatch/collect cycle.\n'
