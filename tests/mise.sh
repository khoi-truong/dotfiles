#!/usr/bin/env bash
# mise/setup.sh against a stub `mise`, under a throwaway HOME.
#
#   bash tests/mise.sh              every case_*
#   bash tests/mise.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

case_links_global_toml_and_installs() {
  local h bin="${WORK}/bin"
  h="$(new_home)"
  mkdir -p "$bin"
  cat >"$bin/mise" <<'STUB'
#!/bin/sh
echo "$*" >>"$MISE_LOG"
STUB
  chmod +x "$bin/mise"
  MISE_LOG="${WORK}/mise.log"
  export MISE_LOG
  : >"$MISE_LOG"
  PATH="$bin:$PATH"
  run_module mise "$h"
  [ "$(readlink "$h/.config/mise/config.toml")" = "${DOTFILES}/mise/global.toml" ]
  grep -qx 'install' "$MISE_LOG"
}

case_no_mise_warns_and_exits_zero() {
  local h
  h="$(new_home)"
  PATH=/usr/bin:/bin
  run_module mise "$h"
  [ -L "$h/.config/mise/config.toml" ]
  grep -q 'mise is not installed' "${WORK}/last.out"
}

run_suite "$@"
