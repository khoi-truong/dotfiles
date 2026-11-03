#!/usr/bin/env bash
# lib/common.sh helpers (brew_prefix, link, backup) under a throwaway HOME.
#
#   bash tests/common.sh              every case_*
#   bash tests/common.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# in_common HOME FUNCTION [ARGS...]: call a lib/common.sh function in a fresh
# bash with the library sourced.
in_common() {
  local h="$1"
  shift
  # The single quotes are deliberate: $1 and "$@" expand in the child bash.
  # shellcheck disable=SC2016
  in_home "$h" bash -c '. "$1/lib/common.sh"; shift; "$@"' _ "$DOTFILES" "$@"
}

journal() { (cd "$1" && find .local/state -type f 2>/dev/null | sort | xargs cksum 2>/dev/null); }

case_brew_prefix_from_stub() {
  local h
  h="$(new_home)"
  stub_brew
  in_common "$h" brew_prefix
  [ "$(cat "${WORK}/last.out")" = "$STUB_PREFIX" ]
}

case_brew_prefix_arch_fallback() {
  local h want
  h="$(new_home)"
  PATH=/usr/bin:/bin
  in_common "$h" brew_prefix
  if [ "$(uname -m)" = arm64 ]; then want=/opt/; else want=/usr/; fi
  case "$(cat "${WORK}/last.out")" in
    "${want}"*) ;;
    *) return 1 ;;
  esac
}

case_link_creates_link_and_rerun_leaves_journal() {
  local h before after
  h="$(new_home)"
  echo x >"${WORK}/src"
  in_common "$h" link "${WORK}/src" "$h/.config/dst"
  [ -L "$h/.config/dst" ]
  [ "$(readlink "$h/.config/dst")" = "${WORK}/src" ]
  before="$(journal "$h")"
  sleep 1
  in_common "$h" link "${WORK}/src" "$h/.config/dst"
  after="$(journal "$h")"
  [ "$before" = "$after" ]
}

case_link_over_real_file_warns_and_backs_up() {
  local h
  h="$(new_home)"
  echo x >"${WORK}/src"
  echo precious >"$h/target"
  in_common "$h" link "${WORK}/src" "$h/target"
  grep -q 'transaction: replaced ~/target' "${WORK}/last.out"
  grep -q 'backup in ~/.local/state/dotfiles/backups/' "${WORK}/last.out"
  if grep -q precious "${WORK}/last.out"; then return 1; fi
  [ -L "$h/target" ]
  [ "$(cat "$h"/.local/state/dotfiles/backups/*/files/*-target)" = precious ]
}

case_backup_moves_aside_and_records() {
  local h manifest
  h="$(new_home)"
  echo keep >"$h/victim"
  in_common "$h" backup "$h/victim"
  [ ! -e "$h/victim" ]
  manifest="$(find "$h/.local/state/dotfiles/backups" -name manifest.jsonl)"
  [ -n "$manifest" ]
  grep -q '/victim' "$manifest"
  grep -rq keep "$h/.local/state/dotfiles/backups"
}

run_suite "$@"
