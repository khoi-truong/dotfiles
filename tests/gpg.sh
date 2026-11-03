#!/usr/bin/env bash
# gpg/setup.sh under a throwaway HOME, stdin from /dev/null (no tty).
#
#   bash tests/gpg.sh              every case_*
#   bash tests/gpg.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

case_first_run_writes_both() {
  local h
  h="$(new_home)"
  run_module gpg "$h"
  [ "$(mode "$h/.gnupg")" = 700 ]
  [ "$(mode "$h/.gnupg/gpg.conf")" = 600 ]
  [ "$(mode "$h/.gnupg/gpg-agent.conf")" = 600 ]
  cmp -s "$DOTFILES/gpg/gpg.conf" "$h/.gnupg/gpg.conf"
}

case_second_run_unchanged() {
  local h m1 m2 n
  h="$(new_home)"
  run_module gpg "$h"
  m1="$(mtime "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg-agent.conf")"
  sleep 1
  run_module gpg "$h"
  m2="$(mtime "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg-agent.conf")"
  n="$(grep -c 'unchanged' "${WORK}/last.out")"
  [ "$n" -eq 2 ]
  [ "$m1" = "$m2" ]
}

case_drift_is_rewritten() {
  local h
  h="$(new_home)"
  run_module gpg "$h"
  echo "drifted-line" >>"$h/.gnupg/gpg.conf"
  run_module gpg "$h"
  cmp -s "$DOTFILES/gpg/gpg.conf" "$h/.gnupg/gpg.conf"
  [ "$(mode "$h/.gnupg/gpg.conf")" = 600 ]
}

case_conf_parses() {
  local home
  if ! command -v gpg >/dev/null 2>&1; then
    echo "SKIP case_conf_parses: gpg not installed" >&2
    return 0
  fi
  home="$(mktemp -d "${WORK}/gnupg.XXXXXX")"
  chmod 700 "$home"
  GNUPGHOME="$home" gpg --options "$DOTFILES/gpg/gpg.conf" --version >"${WORK}/last.out" 2>&1
}

run_suite "$@"
