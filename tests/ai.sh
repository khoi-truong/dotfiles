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
    'Bash(./setup.sh)' 'Bash(./setup.sh *)' \
    'Bash(bash *setup.sh)' 'Bash(bash *setup.sh *)' \
    'Bash(brew bundle*)' \
    'Bash(mise install*)' 'Bash(mise use -g*)' 'Bash(mise use --global*)' \
    'Bash(defaults write*)' \
    'Bash(git push -f)' 'Bash(git push --force)'; do
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
  denied 'Read(~/.claude.json)'
  denied 'Read(~/.claude/.credentials.json)'
  denied 'Read(~/.config/github-copilot/apps.json)'
}

run_suite "$@"
