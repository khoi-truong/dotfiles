#!/usr/bin/env bash
# Journaling behaviour of the git module under a throwaway HOME.
#
#   bash tests/git.sh              every case_*
#   bash tests/git.sh <case_name>  that case only
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Run the git module against fixture home $1. Nothing from the caller's
# environment that could point outside the fixture survives.
setup_git() {
  env -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u DOTFILES_ATTEMPT -u DOTFILES \
    HOME="$1" bash "${DOTFILES}/git/setup.sh" </dev/null >/dev/null 2>&1
}

attempts() { find "$1/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

case_template_dir_backed_up() {
  local h
  h="$(mktemp -d "${WORK}/home.XXXXXX")"
  mkdir -p "$h/.config/git/template"
  echo x >"$h/.config/git/template/x"
  setup_git "$h"
  [ -L "$h/.config/git/template" ] || return 1
  set -- "$h"/.local/state/dotfiles/backups/*/files/*/x
  [ -f "$1" ]
}

case_rerun_writes_no_journal() {
  local h before after
  h="$(mktemp -d "${WORK}/home.XXXXXX")"
  setup_git "$h"
  before="$(attempts "$h")"
  sleep 1
  setup_git "$h"
  after="$(attempts "$h")"
  [ "$before" = "$after" ]
}

run_cases() {
  local failed=0 name status
  for name in "$@"; do
    # set -e is ignored inside an `if` or `||`, so run the case bare.
    set +e
    (
      set -e
      "$name"
    )
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s\n' "$name"
      failed=1
    fi
  done
  return "$failed"
}

if [ "$#" -gt 0 ]; then
  run_cases "$@"
else
  cases=()
  while IFS= read -r name; do cases+=("$name"); done < <(declare -F | awk '$3 ~ /^case_/ {print $3}')
  run_cases "${cases[@]}"
fi
