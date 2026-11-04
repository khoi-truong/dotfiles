#!/usr/bin/env bash
# nvim/setup.sh and the headless IDE test, under a throwaway HOME with brew
# stubbed and the plugin layer switched off.
#
#   bash tests/nvim.sh              every case_*
#   bash tests/nvim.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

DOTFILES_NVIM_OFFLINE=1
export DOTFILES_NVIM_OFFLINE

attempts() { find "$1/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

case_setup_links_config() {
  local h
  h="$(new_home)"
  stub_brew
  run_module nvim "$h"
  [ "$(readlink "$h/.config/nvim")" = "${DOTFILES}/nvim" ]
}

case_existing_dir_backed_up_and_restored() {
  local h
  h="$(new_home)"
  stub_brew
  mkdir -p "$h/.config/nvim"
  echo original >"$h/.config/nvim/init.lua"
  run_module nvim "$h"
  [ -L "$h/.config/nvim" ] || return 1
  set -- "$h"/.local/state/dotfiles/backups/*/files/*/init.lua
  [ "$(cat "$1")" = original ] || return 1
  in_home "$h" bash "${DOTFILES}/scripts/restore.sh"
  [ -d "$h/.config/nvim" ] && [ ! -L "$h/.config/nvim" ] &&
    [ "$(cat "$h/.config/nvim/init.lua")" = original ]
}

case_rerun_is_noop() {
  local h before after
  h="$(new_home)"
  stub_brew
  run_module nvim "$h"
  before="$(attempts "$h")"
  sleep 1
  run_module nvim "$h"
  after="$(attempts "$h")"
  [ "$before" = "$after" ]
}

case_root_setup_drops_vimrc() {
  ! grep -q vimrc "${DOTFILES}/setup.sh" &&
    grep -E '^DEFAULT_MODULES=\(.*\bnvim\b' "${DOTFILES}/setup.sh" >/dev/null
}

case_ide_offline() {
  local x out
  if ! command -v nvim >/dev/null 2>&1; then
    echo "skip: nvim not installed"
    return 0
  fi
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  mkdir -p "$x/config"
  ln -s "${DOTFILES}/nvim" "$x/config/nvim"
  out="${WORK}/ide.out"
  XDG_CONFIG_HOME="$x/config" XDG_DATA_HOME="$x/data" XDG_STATE_HOME="$x/state" \
    XDG_CACHE_HOME="$x/cache" nvim --headless -l "${DOTFILES}/nvim/tests/ide.lua" >"$out" 2>&1 ||
    {
      cat "$out"
      return 1
    }
  ! grep -q '^FAIL' "$out"
}

run_suite "$@"
