#!/usr/bin/env bash
# ai/claude/settings.json deny guards and the generated policy files.
#
#   bash tests/ai.sh              every case_*
#   bash tests/ai.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

SETTINGS="${DOTFILES}/ai/claude/settings.json"

# denied ENTRY: succeed when ENTRY is in .permissions.deny.
denied() {
  jq -e --arg e "$1" '.permissions.deny | index($e) != null' "$SETTINGS" >/dev/null
}

case_settings_is_valid_json() {
  jq -e . "$SETTINGS" >/dev/null
}

case_claude_hud_config_is_valid() {
  jq -e '.lineLayout == "expanded" and (.display.mergeGroups | length) == 1' \
    "${DOTFILES}/ai/claude/claude-hud.json" >/dev/null
}

case_claude_hud_config_passes_hygiene() {
  python3 -B -I "${DOTFILES}/scripts/ci/hygiene.py" "${DOTFILES}/ai/claude/claude-hud.json" >"${WORK}/last.out" 2>&1
}

case_claude_hud_config_is_copied() {
  grep -q '^copy .*claude/claude-hud.json.*plugins/claude-hud/config.json' "${DOTFILES}/ai/setup.sh"
}

case_deny_has_guards() {
  local entry
  for entry in \
    'Bash(./setup.sh*)' 'Bash(./*/setup.sh*)' \
    'Bash(bash *setup.sh*)' 'Bash(sh *setup.sh*)' 'Bash(zsh *setup.sh*)' \
    'Bash(/bin/bash *setup.sh*)' 'Bash(/bin/sh *setup.sh*)' \
    'Bash(ai/setup.sh*)' 'Bash(brew/setup.sh*)' 'Bash(gh/setup.sh*)' \
    'Bash(git/setup.sh*)' 'Bash(gpg/setup.sh*)' 'Bash(iterm/setup.sh*)' \
    'Bash(macos/setup.sh*)' 'Bash(misc/setup.sh*)' 'Bash(mise/setup.sh*)' \
    'Bash(nvim/setup.sh*)' 'Bash(terminal/setup.sh*)' \
    'Bash(vscode/setup.sh*)' 'Bash(xcode/setup.sh*)' \
    'Bash(brew bundle*)' \
    'Bash(mise install*)' 'Bash(mise i)' 'Bash(mise i *)' \
    'Bash(mise use -g*)' 'Bash(mise use --global*)' \
    'Bash(mise use * -g*)' 'Bash(mise use * --global*)' \
    'Bash(mise u -g*)' 'Bash(mise u --global*)' 'Bash(mise u * -g*)' \
    'Bash(mise upgrade*)' 'Bash(mise up)' 'Bash(mise up *)' \
    'Bash(defaults write*)' 'Bash(defaults * write*)' 'Bash(defaults import*)' \
    'Bash(git push --force*)' 'Bash(git push -f*)'; do
    denied "$entry" || {
      printf 'missing deny: %s\n' "$entry" >"${WORK}/last.out"
      return 1
    }
  done
}

case_deny_has_no_duplicates() {
  jq -e '.permissions.deny | length == (unique | length)' "$SETTINGS" >/dev/null
}

case_credential_reads_denied() {
  denied 'Read(~/.claude.json)' || return 1
  denied 'Read(~/.claude/.credentials.json)' || return 1
  denied 'Read(~/.config/github-copilot/apps.json)' || return 1
}

case_policy_is_current() {
  python3 -B -I "${DOTFILES}/scripts/gen-policy.py" --check >"${WORK}/last.out" 2>&1
}

case_copilot_wrapper_sourced() {
  # shellcheck disable=SC2016  # the pattern is literal text from a zsh file
  grep -Fq '[[ -r ${DOTFILES}/ai/copilot/deny-tools.zsh ]] && source' "${DOTFILES}/ai/aliases.zsh"
}

case_copilot_wrapper_denies() {
  local home="${WORK}/home" out
  mkdir -p "${home}/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' >"${home}/bin/copilot"
  chmod +x "${home}/bin/copilot"
  out="$(HOME="$home" PATH="${home}/bin:${PATH}" zsh -fc \
    "source '${DOTFILES}/ai/copilot/deny-tools.zsh'; copilot hi" 2>&1)" || return 1
  printf '%s\n' "$out" >"${WORK}/last.out"
  [[ "$out" == *"--deny-tool=shell(sudo)"*$'\n'hi ]]
}

run_suite "$@"
