#!/usr/bin/env bash
# ai/claude/statusline.sh under a throwaway HOME with node stubbed on PATH.
#
#   bash tests/statusline.sh              every case_*
#   bash tests/statusline.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

PAYLOAD='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/some/where/proj"},"rate_limits":{"five_hour":{"used_percentage":1}}}'

# fixture: a HOME with a HUD file and a bin dir holding jq (and nothing else
# from the caller's PATH). Sets H and BIN.
fixture() {
  H="$(new_home)"
  BIN="${WORK}/bin.$$.$RANDOM"
  mkdir -p "$BIN" "$H/.claude/hud"
  : >"$H/.claude/hud/omc-hud.mjs"
  ln -s "$(command -v jq)" "$BIN/jq"
}

# stub_node BODY: a `node` on $BIN running BODY.
stub_node() {
  printf '#!/bin/sh\n%s\n' "$1" >"$BIN/node"
  chmod +x "$BIN/node"
}

# statusline INPUT [ENV...]: run the script in the fixture, status in STATUS.
statusline() {
  local input="$1"
  shift
  STATUS=0
  printf '%s' "$input" | env -u CC_PROVIDER -u CLAUDE_CONFIG_DIR -u XDG_STATE_HOME \
    HOME="$H" PATH="$BIN:/usr/bin:/bin" "$@" \
    bash "${DOTFILES}/ai/claude/statusline.sh" >"${WORK}/last.out" 2>&1 || STATUS=$?
}

case_fallback_without_node() {
  fixture
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  [ "$(cat "${WORK}/last.out")" = "Opus · proj" ]
}

case_hud_crash_falls_back() {
  fixture
  stub_node 'cat >/dev/null; exit 1'
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  [ "$(cat "${WORK}/last.out")" = "Opus · proj" ]
}

case_hud_output_used() {
  fixture
  stub_node 'cat >/dev/null; echo HUD'
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  grep -q HUD "${WORK}/last.out"
  if grep -q proj "${WORK}/last.out"; then return 1; fi
}

case_hud_empty_output_falls_back() {
  fixture
  stub_node 'cat >/dev/null'
  statusline "$PAYLOAD"
  [ "$STATUS" -eq 0 ]
  [ "$(cat "${WORK}/last.out")" = "Opus · proj" ]
}

case_garbage_payload() {
  fixture
  statusline 'not json'
  [ "$STATUS" -eq 0 ]
  [ "$(cat "${WORK}/last.out")" = claude ]
}

case_no_jq() {
  fixture
  rm "$BIN/jq"
  # /usr/bin may carry jq, so PATH is the fixture bin alone, with only the
  # tools the script needs besides jq.
  local tool
  for tool in cat basename perl date mkdir; do ln -s "$(command -v "$tool")" "$BIN/$tool"; done
  STATUS=0
  printf '%s' "$PAYLOAD" | env HOME="$H" PATH="$BIN" /bin/bash "${DOTFILES}/ai/claude/statusline.sh" \
    >"${WORK}/last.out" 2>&1 || STATUS=$?
  [ "$STATUS" -eq 0 ]
  [ "$(cat "${WORK}/last.out")" = claude ]
}

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

run_suite "$@"
