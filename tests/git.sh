#!/usr/bin/env bash
# Journaling behaviour of the git module under a throwaway HOME.
#
#   bash tests/git.sh              every case_*
#   bash tests/git.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

setup_git() {
  run_module git "$1"
}

attempts() { find "$1/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

case_template_dir_backed_up() {
  local h
  h="$(new_home)"
  mkdir -p "$h/.config/git/template"
  echo x >"$h/.config/git/template/x"
  setup_git "$h"
  [ -L "$h/.config/git/template" ] || return 1
  set -- "$h"/.local/state/dotfiles/backups/*/files/*/x
  [ -f "$1" ]
}

case_rerun_writes_no_journal() {
  local h before after
  h="$(new_home)"
  setup_git "$h"
  before="$(attempts "$h")"
  sleep 1
  setup_git "$h"
  after="$(attempts "$h")"
  [ "$before" = "$after" ]
}

run_suite "$@"
