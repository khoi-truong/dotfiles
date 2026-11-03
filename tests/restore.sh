#!/usr/bin/env bash
# scripts/restore.sh undoes a setup run, under a throwaway HOME.
#
#   bash tests/restore.sh              every case_*
#   bash tests/restore.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

case_restore_file() {
  local h
  h="$(new_home)"
  echo orig >"$h/.gitconfig"
  in_home "$h" bash "${DOTFILES}/git/setup.sh"
  [ -L "$h/.gitconfig" ] || return 1
  in_home "$h" bash "${DOTFILES}/scripts/restore.sh"
  [ ! -L "$h/.gitconfig" ] && [ "$(cat "$h/.gitconfig")" = orig ]
}

case_restore_dir() {
  local h
  h="$(new_home)"
  mkdir -p "$h/.config/git/template"
  echo x >"$h/.config/git/template/x"
  in_home "$h" bash "${DOTFILES}/git/setup.sh"
  [ -L "$h/.config/git/template" ] || return 1
  in_home "$h" bash "${DOTFILES}/scripts/restore.sh"
  [ -d "$h/.config/git/template" ] && [ ! -L "$h/.config/git/template" ] &&
    [ -f "$h/.config/git/template/x" ]
}

run_suite "$@"
