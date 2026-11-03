#!/usr/bin/env bash
# zsh/functions.zsh and zsh/env.zsh in isolated `zsh -f` shells.
#
#   bash tests/zsh.sh              every case_*
#   bash tests/zsh.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# zrun HOME SNIPPET: run SNIPPET in `zsh -f` after sourcing functions.zsh.
zrun() {
  local h="$1"
  shift
  in_home "$h" zsh -f -c "source '${DOTFILES}/zsh/functions.zsh'; $*"
}

case_guards_reject_bad_argc() {
  local h fn status
  h="$(new_home)"
  for fn in urlencode urldecode mkd; do
    for args in "" "a b"; do
      status=0
      zrun "$h" "cd '$h'; $fn $args" || status=$?
      [ "$status" -eq 2 ]
      grep -q '^usage:' "${WORK}/last.out"
    done
  done
  [ -z "$(ls -A "$h")" ]
}

case_urlencode_roundtrip() {
  local h
  h="$(new_home)"
  # shellcheck disable=SC2016  # the snippet is zsh, expanded there
  zrun "$h" 'urldecode "$(urlencode "a b&c")"'
  [ "$(cat "${WORK}/last.out")" = 'a b&c' ]
}

case_claude_passes_status_no_tty() {
  local h bin
  h="$(new_home)"
  bin="${WORK}/bin.notty"
  mkdir -p "$bin"
  printf '#!/bin/sh\nexit 3\n' >"$bin/claude"
  printf '#!/bin/sh\necho called >>"%s/stty.log"\n' "$WORK" >"$bin/stty"
  chmod +x "$bin/claude" "$bin/stty"
  rm -f "${WORK}/stty.log"
  local status=0
  zrun "$h" "PATH='$bin':\$PATH; claude" || status=$?
  [ "$status" -eq 3 ]
  [ ! -e "${WORK}/stty.log" ]
}

case_claude_restores_echo_on_tty() {
  local h bin
  if ! command -v script >/dev/null 2>&1; then
    echo "SKIP case_claude_restores_echo_on_tty: script(1) not available" >&2
    return 0
  fi
  h="$(new_home)"
  bin="${WORK}/bin.tty"
  mkdir -p "$bin"
  printf '#!/bin/sh\nexit 1\n' >"$bin/claude"
  chmod +x "$bin/claude"
  # Under a pty: run the wrapper (status 1), then report stty -a and the status.
  HOME="$h" script -q /dev/null zsh -f -c "source '${DOTFILES}/zsh/functions.zsh'; PATH='$bin':\$PATH; claude; echo STATUS=\$?; stty -a" \
    </dev/null >"${WORK}/last.out" 2>&1 || true
  # script(1) without a controlling tty on stdin may not allocate one usefully.
  if ! grep -q 'STATUS=' "${WORK}/last.out"; then
    echo "SKIP case_claude_restores_echo_on_tty: script gave no usable pty" >&2
    return 0
  fi
  grep -q 'STATUS=1' "${WORK}/last.out"
  if grep -q 'speed' "${WORK}/last.out"; then
    # stty -a printed: echo must be on (shown as `echo`, not `-echo`).
    grep -Eq '(^|[[:space:]])echo([[:space:]]|$)' "${WORK}/last.out"
  else
    echo "SKIP case_claude_restores_echo_on_tty: stty -a produced no tty state" >&2
  fi
}

case_env_strips_version_managers() {
  local h out
  h="$(new_home)"
  out="$(in_home "$h" env PATH="$h/.nvm/versions/node/bin:$h/.pyenv/shims:$h/.yarn/bin:/usr/bin:/bin" \
    zsh -f -c "source '${DOTFILES}/zsh/env.zsh'; print -l \$path" && cat "${WORK}/last.out")"
  case "$out" in *".nvm"* | *".pyenv"* | *".yarn"*) return 1 ;; esac
  case "$out" in *"/usr/bin"*) ;; *) return 1 ;; esac
}

run_suite "$@"
