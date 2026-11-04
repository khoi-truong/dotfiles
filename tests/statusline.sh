#!/usr/bin/env bash
# ai/claude/statusline.sh under a throwaway HOME with a stub `node` on PATH.
# The stub plays claude-hud: it prints the file it is given (dist/index.js),
# which each case fills with output in claude-hud v0.15.0's own format.
#
#   bash tests/statusline.sh              every case_*
#   bash tests/statusline.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

PAYLOAD='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/some/where/proj"},"rate_limits":{"five_hour":{"used_percentage":1}}}'

# claude-hud's colours and the U+FE0F its duration glyph carries.
DIM=$'\033[2m' RED=$'\033[31m' GRN=$'\033[32m' YEL=$'\033[33m' CYN=$'\033[36m' OFF=$'\033[0m'
VS16=$'\xef\xb8\x8f'

# Rows as claude-hud prints them, coloured.
BADGE="${CYN}[Opus ◔ medium]${OFF}"
PROJECT="${YEL}proj${OFF} git:(${CYN}main${OFF})"
DURATION="${DIM}⏱${VS16}  1h 23m${OFF}"
SPEED="${DIM}out: 88.3 tok/s${OFF}"
CONTEXT="Context ${GRN}▓▓▓░░${OFF} 36%"
USAGE="Usage ${GRN}▓░░░░${OFF} 5% (1h left)"
CACHE="Cache ${GRN}⏱ until 03:00 PM${OFF}"
TOOLS="${YEL}◐${OFF} ${CYN}Bash${OFF}${DIM}: ls${OFF} | ${GRN}✓${OFF} Read ${DIM}×3${OFF} | ${GRN}✓${OFF} Edit ${DIM}×2${OFF}"
COMPACTIONS="${DIM}Compactions: 2${OFF}"
SEP=' │ '

# fixture: a HOME and a bin dir holding jq (and nothing else from the caller's
# PATH). Sets H and BIN.
fixture() {
  H="$(new_home)"
  BIN="${WORK}/bin.$$.$RANDOM"
  mkdir -p "$BIN"
  ln -s "$(command -v jq)" "$BIN/jq"
}

# stub_node: a `node` on $BIN that passes stdin through (the context shim) or,
# given a dist/index.js, prints that file (the HUD).
stub_node() {
  cat >"$BIN/node" <<'STUB'
#!/bin/sh
case "$1" in
*/dist/index.js) cat >/dev/null; cat "$1" ;;
*) cat ;;
esac
STUB
  chmod +x "$BIN/node"
}

# hud_version VERSION: an installed claude-hud whose output is stdin.
hud_version() {
  local dir="$H/.claude/plugins/cache/claude-hud/claude-hud/$1/dist"
  mkdir -p "$dir"
  cat >"$dir/index.js"
}

# hud: install version 0.15.0 printing the given rows, one argument per row.
hud() {
  printf '%s\n' "$@" | hud_version 0.15.0
}

# statusline INPUT [ENV...]: run the script in the fixture, status in STATUS.
statusline() {
  local input="$1"
  shift
  STATUS=0
  printf '%s' "$input" | env -u CC_PROVIDER -u CC_PROVIDER_LABEL -u CLAUDE_CONFIG_DIR -u XDG_STATE_HOME \
    HOME="$H" PATH="$BIN:/usr/bin:/bin" "$@" \
    bash "${DOTFILES}/ai/claude/statusline.sh" >"${WORK}/last.out" 2>&1 || STATUS=$?
}

# shown: what the status line printed, minus colour.
shown() {
  sed $'s/\033\\[[0-9;]*m//g' "${WORK}/last.out"
}

# shows EXPECTED...: the colourless output is exactly these lines.
shows() {
  local expected actual
  expected="$(printf '%s\n' "$@")"
  actual="$(shown)"
  [ "$actual" = "$expected" ] || {
    printf 'want:\n%s\ngot:\n%s\n' "$expected" "$actual" >&2
    return 1
  }
}

# --- layout ------------------------------------------------------------

case_layout_moves_duration_compactions_speed_ahead_of_tools() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}${SEP}${DURATION}${SEP}${SPEED}" \
    "${CONTEXT}${SEP}${USAGE}${SEP}${CACHE}${SEP}${TOOLS}" \
    "${COMPACTIONS}"
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows '[Opus ◔ medium] │ proj git:(main)' \
    'Context ▓▓▓░░ 36% │ Usage ▓░░░░ 5% (1h left) │ Cache until 03:00 PM │ ⏱️ 1h23m │ Compactions: 2 │ ⚡ 88.3 tok/s │ ◐ Bash │ 🔧 5'
}

case_layout_keeps_colour_on_running_glyph() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}" "${CONTEXT}${SEP}${TOOLS}"
  statusline "$PAYLOAD"
  grep -q $'\033\\[33m◐\033\\[0m Bash' "${WORK}/last.out"
}

case_layout_drops_out_label() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}${SEP}${SPEED}" "${CONTEXT}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium] │ proj git:(main)' 'Context ▓▓▓░░ 36% │ ⚡ 88.3 tok/s'
}

case_layout_cache_reads_until() {
  fixture
  stub_node
  hud "${BADGE}" "${CONTEXT}${SEP}${CACHE}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ Cache until 03:00 PM'
}

case_layout_expired_cache_keeps_its_glyph() {
  fixture
  stub_node
  hud "${BADGE}" "${CONTEXT}${SEP}Cache ${RED}⏱ expired${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ Cache ⏱ expired'
}

case_layout_duration_squeezed() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${DIM}⏱${VS16}  2d 4h 5m${OFF}" "${CONTEXT}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ ⏱️ 2d4h5m'
}

case_layout_short_duration() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${DIM}⏱${VS16}  <1m${OFF}" "${CONTEXT}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ ⏱️ <1m'
}

case_layout_tools_collapse_to_running_names_and_total() {
  fixture
  stub_node
  hud "${BADGE}" \
    "${CONTEXT}${SEP}${YEL}◐${OFF} Edit${DIM}: a.ts${OFF} | ${YEL}◐${OFF} Bash${DIM}: ls${OFF} | ${GRN}✓${OFF} Read ${DIM}×3${OFF} | ${GRN}✓${OFF} Grep ${DIM}×4${OFF} | ${DIM}+1 more${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ ◐ Edit, Bash │ 🔧 7'
}

case_layout_tools_only_completed() {
  fixture
  stub_node
  hud "${BADGE}" "${CONTEXT}${SEP}${GRN}✓${OFF} Read ${DIM}×3${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ 🔧 3'
}

case_layout_agents_untouched() {
  fixture
  stub_node
  hud "${BADGE}" "${CONTEXT}" \
    "${YEL}◐${OFF} explore ${DIM}[haiku]${OFF}: Find the thing ${DIM}(2m)${OFF}" \
    "${GRN}✓${OFF} general: done ${DIM}(1m)${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36%' \
    '◐ explore [haiku]: Find the thing (2m)' '✓ general: done (1m)'
}

case_layout_wrapped_row_starting_with_duration() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}" \
    "${DURATION}${SEP}${SPEED}" \
    "${CONTEXT}${SEP}${CACHE}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium] │ proj git:(main)' \
    'Context ▓▓▓░░ 36% │ Cache until 03:00 PM │ ⏱️ 1h23m │ ⚡ 88.3 tok/s'
}

case_layout_wrapped_row_starting_with_speed() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}" "${SPEED}" "${CONTEXT}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium] │ proj git:(main)' 'Context ▓▓▓░░ 36% │ ⚡ 88.3 tok/s'
}

case_layout_spilled_usage_and_cache_merge_into_context() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}" \
    "${CONTEXT}" \
    "${USAGE}${SEP}${CACHE}" \
    "${YEL}◐${OFF} Edit${DIM}: a.ts${OFF} | ${GRN}✓${OFF} Read ${DIM}×3${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium] │ proj git:(main)' \
    'Context ▓▓▓░░ 36% │ Usage ▓░░░░ 5% (1h left) │ Cache until 03:00 PM │ ◐ Edit │ 🔧 3'
}

case_layout_spilled_tools_wrapped_mid_group() {
  fixture
  stub_node
  hud "${BADGE}" \
    "${CONTEXT}${SEP}${YEL}◐${OFF} Edit${DIM}: a.ts${OFF} | ${GRN}✓${OFF} Read ${DIM}×3${OFF}" \
    "${GRN}✓${OFF} Grep ${DIM}×4${OFF}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium]' 'Context ▓▓▓░░ 36% │ ◐ Edit │ 🔧 7'
}

case_layout_without_context_row_appends_to_first() {
  fixture
  stub_node
  hud "${BADGE}${SEP}${PROJECT}${SEP}${DURATION}"
  statusline "$PAYLOAD"
  shows '[Opus ◔ medium] │ proj git:(main) │ ⏱️ 1h23m'
}

# --- which HUD ---------------------------------------------------------

case_hud_output_used() {
  fixture
  stub_node
  hud HUD
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows HUD
}

case_newest_hud_version_used() {
  fixture
  stub_node
  echo v0.9.0 | hud_version 0.9.0
  echo v0.15.0 | hud_version 0.15.0
  echo v0.2.1-beta | hud_version 0.2.1-beta
  echo v0.2.10 | hud_version 0.2.10
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows v0.15.0
}

case_hud_found_under_any_marketplace_dir() {
  fixture
  stub_node
  mkdir -p "$H/.claude/plugins/cache/other-market/claude-hud/0.1.0/dist"
  echo other >"$H/.claude/plugins/cache/other-market/claude-hud/0.1.0/dist/index.js"
  statusline "$PAYLOAD"
  shows other
}

case_config_dir_override() {
  fixture
  stub_node
  mkdir -p "$WORK/cfg/plugins/cache/m/claude-hud/1.0.0/dist"
  echo custom >"$WORK/cfg/plugins/cache/m/claude-hud/1.0.0/dist/index.js"
  statusline "$PAYLOAD" CLAUDE_CONFIG_DIR="$WORK/cfg"
  shows custom
}

case_launcher_copy_is_not_used() {
  fixture
  stub_node
  mkdir -p "$H/.claude/plugins/claude-hud"
  : >"$H/.claude/plugins/claude-hud/statusline.mjs"
  statusline "$PAYLOAD"
  shows 'Opus proj'
}

case_bare_name_invocation_finds_hud() {
  fixture
  stub_node
  hud HUD
  mkdir "$WORK/copy"
  cp "${DOTFILES}/ai/claude/statusline.sh" "${DOTFILES}/ai/claude/hud-ctx-fix.mjs" "$WORK/copy/"
  STATUS=0
  (cd "$WORK/copy" && printf '%s' "$PAYLOAD" | env HOME="$H" PATH="$BIN:/usr/bin:/bin" \
    bash statusline.sh >"${WORK}/last.out" 2>&1) || STATUS=$?
  [ "$STATUS" -eq 0 ]
  shows HUD
}

case_node_found_via_mise_shim() {
  fixture
  stub_node
  hud HUD
  mkdir -p "$H/.local/share/mise/shims"
  mv "$BIN/node" "$H/.local/share/mise/shims/node"
  statusline "$PAYLOAD"
  shows HUD
}

# --- fallback ----------------------------------------------------------

case_fallback_without_node() {
  fixture
  hud HUD
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_fallback_without_hud() {
  fixture
  stub_node
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_hud_crash_falls_back() {
  fixture
  printf '#!/bin/sh\ncat >/dev/null; exit 1\n' >"$BIN/node"
  chmod +x "$BIN/node"
  hud HUD
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_hud_empty_output_falls_back() {
  fixture
  stub_node
  : | hud_version 0.15.0
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_hud_whitespace_falls_back() {
  fixture
  stub_node
  printf '  \n\n' | hud_version 0.15.0
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_provider_label_names_the_fallback() {
  fixture
  statusline "$PAYLOAD" CC_PROVIDER_LABEL=Kimi
  shows 'Kimi proj'
}

case_unset_home_still_prints() {
  fixture
  STATUS=0
  printf '%s' "$PAYLOAD" | env -u HOME PATH="$BIN:/usr/bin:/bin" \
    bash "${DOTFILES}/ai/claude/statusline.sh" >"${WORK}/last.out" 2>&1 || STATUS=$?
  [ "$STATUS" -eq 0 ]
  shows 'Opus proj'
}

case_garbage_payload() {
  fixture
  statusline 'not json'
  [ "$STATUS" -eq 0 ]
  shows Claude
}

case_no_jq() {
  fixture
  rm "$BIN/jq"
  # /usr/bin may carry jq, so PATH is the fixture bin alone, with only the
  # tools the script needs besides jq.
  local tool
  for tool in cat dirname basename perl date mkdir; do ln -s "$(command -v "$tool")" "$BIN/$tool"; done
  STATUS=0
  printf '%s' "$PAYLOAD" | env HOME="$H" PATH="$BIN" /bin/bash "${DOTFILES}/ai/claude/statusline.sh" \
    >"${WORK}/last.out" 2>&1 || STATUS=$?
  [ "$STATUS" -eq 0 ]
  shows Claude
}

# --- quota cache -------------------------------------------------------

case_quota_cached_on_pro_pane() {
  fixture
  statusline "$PAYLOAD"
  [ -s "$H/.claude/cache/pro-quota.json" ]
}

case_provider_pane_skips_cache() {
  fixture
  statusline "$PAYLOAD" CC_PROVIDER=x
  [ "$STATUS" -eq 0 ]
  [ ! -e "$H/.claude/cache/pro-quota.json" ]
}

# cache_quota returning without reading its stdin closed the pipe under the
# printf feeding it, which printed "write error: Broken pipe" whenever it lost
# the race. A payload past the 64K pipe buffer makes the race certain, and an
# ignored SIGPIPE (inherited, as on CI runners) turns it into that message.
case_skipped_cache_drains_payload() {
  fixture
  local pad
  pad=$(head -c 200000 /dev/zero | tr '\0' x)
  STATUS=0
  # shellcheck disable=SC2016 # $1 is the inner shell's.
  printf '{"model":{"display_name":"Opus"},"pad":"%s"}' "$pad" |
    env -u CC_PROVIDER_LABEL -u CLAUDE_CONFIG_DIR -u XDG_STATE_HOME HOME="$H" PATH="$BIN:/usr/bin:/bin" CC_PROVIDER=x \
      bash -c 'trap "" PIPE; exec bash "$1"' _ "${DOTFILES}/ai/claude/statusline.sh" >"${WORK}/last.out" 2>&1 || STATUS=$?
  [ "$STATUS" -eq 0 ]
  ! grep -q 'Broken pipe' "${WORK}/last.out"
}

run_suite "$@"
