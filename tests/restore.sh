#!/usr/bin/env bash
# scripts/restore.sh undoes a setup run, under a throwaway HOME.
#
#   bash tests/restore.sh              every case_*
#   bash tests/restore.sh <case_name>  that case only
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Run "$@" with fixture home $1 and nothing from the caller's environment that
# could point outside it.
in_home() {
  local h="$1"
  shift
  env -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u DOTFILES_ATTEMPT -u DOTFILES \
    HOME="$h" "$@" </dev/null >/dev/null 2>&1
}

case_restore_file() {
  local h
  h="$(mktemp -d "${WORK}/home.XXXXXX")"
  echo orig >"$h/.gitconfig"
  in_home "$h" bash "${DOTFILES}/git/setup.sh"
  [ -L "$h/.gitconfig" ] || return 1
  in_home "$h" bash "${DOTFILES}/scripts/restore.sh"
  [ ! -L "$h/.gitconfig" ] && [ "$(cat "$h/.gitconfig")" = orig ]
}

case_restore_dir() {
  local h
  h="$(mktemp -d "${WORK}/home.XXXXXX")"
  mkdir -p "$h/.config/git/template"
  echo x >"$h/.config/git/template/x"
  in_home "$h" bash "${DOTFILES}/git/setup.sh"
  [ -L "$h/.config/git/template" ] || return 1
  in_home "$h" bash "${DOTFILES}/scripts/restore.sh"
  [ -d "$h/.config/git/template" ] && [ ! -L "$h/.config/git/template" ] &&
    [ -f "$h/.config/git/template/x" ]
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
