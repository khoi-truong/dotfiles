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

# Run nvim in a throwaway XDG tree ($1) with plugins on and github.com pointed at
# a closed local port, so a clone fails at once and offline. Output is
# stdout+stderr; the exit code is nvim's. Further args go to nvim.
nvim_unreachable() {
  local x="$1"
  shift
  mkdir -p "$x/config"
  ln -sfn "${DOTFILES}/nvim" "$x/config/nvim"
  env -u DOTFILES_NVIM_OFFLINE XDG_CONFIG_HOME="$x/config" XDG_DATA_HOME="$x/data" \
    XDG_STATE_HOME="$x/state" XDG_CACHE_HOME="$x/cache" GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=url.http://127.0.0.1:9/.insteadOf GIT_CONFIG_VALUE_0=https://github.com/ \
    nvim --headless "$@" 2>&1
}

need_nvim() {
  command -v nvim >/dev/null 2>&1 && return 0
  echo "skip: nvim not installed"
  return 1
}

lines_matching() { printf '%s\n' "$1" | grep -c -- "$2" || true; }

case_clone_failure_is_one_line() {
  local x out rc=0
  need_nvim || return 0
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  out="$(nvim_unreachable "$x" +qa)" || rc=$?
  [ "$rc" = 0 ] &&
    [ "$(lines_matching "$out" 'could not install lazy.nvim')" = 1 ] &&
    ! printf '%s' "$out" | grep -q 'stack traceback'
}

case_half_finished_clone_is_retried() {
  local x out rc=0
  need_nvim || return 0
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  mkdir -p "$x/data/nvim/lazy/lazy.nvim/.git"
  out="$(nvim_unreachable "$x" +qa)" || rc=$?
  [ "$rc" = 0 ] &&
    [ "$(lines_matching "$out" 'could not install lazy.nvim')" = 1 ] &&
    [ ! -e "$x/data/nvim/lazy/lazy.nvim" ]
}

case_broken_lazy_falls_back_to_core() {
  local x out rc=0
  need_nvim || return 0
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  mkdir -p "$x/data/nvim/lazy/lazy.nvim/lua/lazy"
  echo 'error("boom")' >"$x/data/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
  out="$(nvim_unreachable "$x" +qa)" || rc=$?
  [ "$rc" = 0 ] &&
    [ "$(lines_matching "$out" 'plugins incomplete (.*boom.*)')" = 1 ] &&
    ! printf '%s' "$out" | grep -q 'stack traceback'
}

case_clone_timeout_is_a_failure() {
  local x out rc=0 bin
  need_nvim || return 0
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  bin="$(mktemp -d "${WORK}/bin.XXXXXX")"
  printf '#!/bin/sh\nexec sleep 30\n' >"$bin/git"
  chmod +x "$bin/git"
  out="$(PATH="$bin:$PATH" DOTFILES_NVIM_CLONE_TIMEOUT_MS=500 nvim_unreachable "$x" +qa)" || rc=$?
  [ "$rc" = 0 ] &&
    [ "$(lines_matching "$out" 'could not install lazy.nvim (timed out')" = 1 ]
}

case_ide_test_installs_nothing() {
  local x out rc=0
  need_nvim || return 0
  x="$(mktemp -d "${WORK}/xdg.XXXXXX")"
  out="$(nvim_unreachable "$x" -l "${DOTFILES}/nvim/tests/ide.lua")" || rc=$?
  [ "$rc" = 0 ] &&
    ! printf '%s' "$out" | grep -q 'could not install' &&
    printf '%s' "$out" | grep -q '^skip plugin checks' &&
    [ ! -e "$x/data/nvim/lazy" ]
}

run_suite "$@"
