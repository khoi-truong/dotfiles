#!/usr/bin/env bash
# brew/setup.sh against a stub `brew`, under a throwaway HOME.
#
#   bash tests/brew.sh              every case_*
#   bash tests/brew.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# An inherited CI would answer the cleanup prompt for every case.
unset CI

case_plain_install_logs_bundle_install() {
  local h
  h="$(new_home)"
  stub_brew
  run_module brew "$h"
  grep -q '^bundle install --no-upgrade' "$BREW_LOG"
  if grep -q 'cleanup' "$BREW_LOG"; then return 1; fi
}

case_cleanup_answered_no_does_not_force() {
  local h
  h="$(new_home)"
  stub_brew
  printf 'n\n' >"${WORK}/answer"
  RUN_STDIN="${WORK}/answer" run_module brew "$h" --cleanup
  grep -q '^bundle cleanup$' "$BREW_LOG"
  if grep -q 'cleanup --force' "$BREW_LOG"; then return 1; fi
}

case_cleanup_yes_forces() {
  local h
  h="$(new_home)"
  stub_brew
  run_module brew "$h" --cleanup --yes
  grep -q '^bundle cleanup --force$' "$BREW_LOG"
}

case_cleanup_under_ci_forces() {
  local h
  h="$(new_home)"
  stub_brew
  CI=true run_module brew "$h" --cleanup
  grep -q '^bundle cleanup --force$' "$BREW_LOG"
}

case_unknown_argument_fails() {
  local h
  h="$(new_home)"
  stub_brew
  if run_module brew "$h" --nonsense; then
    return 1
  fi
  grep -q "unknown argument '--nonsense'" "${WORK}/last.out"
  if grep -q 'bundle' "$BREW_LOG"; then return 1; fi
}

run_suite "$@"
