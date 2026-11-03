#!/usr/bin/env bash
# ai/claude/settings.json deny guards.
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

case_deny_has_guards() {
  local entry
  for entry in \
    'Bash(./setup.sh *)' 'Bash(./*/setup.sh*)' \
    'Bash(bash *setup.sh)' 'Bash(bash *setup.sh *)' \
    'Bash(sh *setup.sh*)' 'Bash(zsh *setup.sh*)' \
    'Bash(/bin/bash *setup.sh*)' 'Bash(/bin/sh *setup.sh*)' \
    'Bash(ai/setup.sh*)' 'Bash(brew/setup.sh*)' 'Bash(gh/setup.sh*)' \
    'Bash(git/setup.sh*)' 'Bash(gpg/setup.sh*)' 'Bash(iterm/setup.sh*)' \
    'Bash(macos/setup.sh*)' 'Bash(misc/setup.sh*)' 'Bash(mise/setup.sh*)' \
    'Bash(terminal/setup.sh*)' 'Bash(vscode/setup.sh*)' 'Bash(xcode/setup.sh*)' \
    'Bash(brew bundle*)' \
    'Bash(mise install*)' 'Bash(mise i)' 'Bash(mise i *)' \
    'Bash(mise use -g*)' 'Bash(mise use --global*)' \
    'Bash(mise use * -g*)' 'Bash(mise use * --global*)' \
    'Bash(mise u -g*)' 'Bash(mise u --global*)' 'Bash(mise u * -g*)' \
    'Bash(mise upgrade*)' 'Bash(mise up)' 'Bash(mise up *)' \
    'Bash(defaults write*)' 'Bash(defaults * write*)' 'Bash(defaults import*)' \
    'Bash(git push --force*)' 'Bash(git push -f *)'; do
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

run_suite "$@"
