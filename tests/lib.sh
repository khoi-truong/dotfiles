#!/usr/bin/env bash
# Shared plumbing for the fixture-home suites. Sourced, never run:
#
#   . "$(dirname "$0")/lib.sh"
#   case_something() { ... }
#   run_suite "$@"
#
# Every suite works in a throwaway HOME under $WORK and never touches the
# caller's own. bash 3.2-compatible.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
# shellcheck disable=SC2154
# bash 3.2 reports $? as 0 inside an EXIT trap when `set -eu` aborts on an
# unbound variable, which would turn a crashed suite into a pass. run_suite sets
# SUITE_DONE when it returns, so a clean 0 without it is a crash: exit 1.
trap 'rc=$?; rm -rf "$WORK"; if [ "$rc" -eq 0 ] && [ -z "${SUITE_DONE:-}" ]; then rc=1; fi; exit "$rc"' EXIT

# in_home HOME CMD [ARGS...]: run CMD with HOME set to the fixture and nothing
# from the caller's environment that could point outside it. Output goes to
# $WORK/last.out; stdin is $RUN_STDIN, default /dev/null.
in_home() {
  local h="$1"
  shift
  env -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u DOTFILES_ATTEMPT -u DOTFILES \
    HOME="$h" "$@" <"${RUN_STDIN:-/dev/null}" >"${WORK}/last.out" 2>&1
}

# run_module MODULE HOME [ARGS...]: run MODULE/setup.sh against the fixture.
run_module() {
  local module="$1" h="$2"
  shift 2
  in_home "$h" bash "${DOTFILES}/${module}/setup.sh" "$@"
}

# new_home: a fresh empty fixture HOME, path on stdout.
new_home() {
  mktemp -d "${WORK}/home.XXXXXX"
}

# stub_brew: a fake `brew` on PATH whose prefix is $WORK/prefix, so
# load_brew_shellenv is satisfied without a real Homebrew. It appends its argv
# to $WORK/brew.log; `shellenv` prints nothing. Call it inside a case: PATH,
# STUB_PREFIX and BREW_LOG are set for the case's subshell only.
stub_brew() {
  STUB_PREFIX="${WORK}/prefix"
  BREW_LOG="${WORK}/brew.log"
  export STUB_PREFIX BREW_LOG
  mkdir -p "${STUB_PREFIX}/bin"
  : >"$BREW_LOG"
  cat >"${STUB_PREFIX}/bin/brew" <<'STUB'
#!/bin/sh
echo "$*" >>"$BREW_LOG"
if [ "$1" = "--prefix" ]; then
  echo "$STUB_PREFIX"
fi
STUB
  chmod +x "${STUB_PREFIX}/bin/brew"
  PATH="${STUB_PREFIX}/bin:${PATH}"
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
      if [ -s "${WORK}/last.out" ]; then
        sed 's/^/     | /' "${WORK}/last.out"
      fi
      failed=1
    fi
  done
  return "$failed"
}

# run_suite [CASE...]: the named cases, or every case_* function. It must be
# the last command of a suite: its status is the suite's.
run_suite() {
  local status
  select_cases "$@" && status=0 || status=$?
  SUITE_DONE=1
  return "$status"
}

select_cases() {
  local cases=() name
  if [ "$#" -gt 0 ]; then
    run_cases "$@"
  else
    while IFS= read -r name; do cases+=("$name"); done < <(declare -F | awk '$3 ~ /^case_/ {print $3}')
    if [ "${#cases[@]}" -eq 0 ]; then
      printf 'run_suite: no case_* functions defined\n' >&2
      return 1
    fi
    run_cases "${cases[@]}"
  fi
}
