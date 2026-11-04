#!/usr/bin/env bash
# ai/herdr/plugins.sh and plugins.py against a stub `herdr` and a fixture manifest.
#
#   bash tests/herdr_plugins.sh              every case_*
#   bash tests/herdr_plugins.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

PLUGINS_SH="${DOTFILES}/ai/herdr/plugins.sh"

# stub_herdr: a fake `herdr` first on PATH. It appends its argv to
# $WORK/herdr.log, prints $WORK/herdr.list for `plugin list`, answers
# `plugin list --plugin ID --json` from the same file, and prints
# $WORK/config/ID for `plugin config-dir ID`.
stub_herdr() {
  mkdir -p "${WORK}/bin" "${WORK}/config"
  : >"${WORK}/herdr.log"
  : >"${WORK}/herdr.list"
  cat >"${WORK}/bin/herdr" <<'STUB'
#!/bin/sh
echo "$*" >>"$WORK/herdr.log"
[ "$1" = plugin ] || exit 0
case "$2" in
  list)
    if [ "$3" = --plugin ]; then
      if grep -q "^- $4 " "$WORK/herdr.list"; then
        echo '{"result":{"plugins":[{"id":"'"$4"'"}]}}'
      else
        echo '{"result":{"plugins":[]}}'
      fi
    else
      cat "$WORK/herdr.list"
    fi
    ;;
  config-dir) mkdir -p "$WORK/config/$3" && echo "$WORK/config/$3" ;;
esac
STUB
  chmod +x "${WORK}/bin/herdr"
  export WORK
  PATH="${WORK}/bin:${PATH}"
}

# refute PATTERN FILE: fail when FILE matches PATTERN. (`! grep` would not trip
# errexit.)
refute() {
  if grep -q -- "$1" "$2"; then
    printf 'unexpected match for %s\n' "$1" >>"${WORK}/last.out"
    return 1
  fi
}

# manifest BODY: write the fixture manifest and point the code at it.
manifest() {
  printf '%s\n' "$1" >"${WORK}/plugins.toml"
  export DOTFILES_HERDR_PLUGINS="${WORK}/plugins.toml"
}

ONE='[[plugin]]
id = "cloudmanic.herdr-plus"
repo = "cloudmanic/herdr-plus"
ref = "v0.1.24"
why = "x"'

# list_line ID REPO REF: one installed plugin in `herdr plugin list` shape.
list_line() {
  printf -- '- %s (Name) enabled [github:%s@%s]\n  config: /x/%s\n' "$1" "$2" "$3" "$1" >>"${WORK}/herdr.list"
}

# apply HOME: run herdr_plugins_apply the way setup does.
apply() {
  # shellcheck disable=SC2016
  in_home "$1" bash -c '. "$1/lib/common.sh"; . "$1/ai/herdr/plugins.sh"; herdr_plugins_apply' _ "${DOTFILES}"
}

case_needs_missing_skips() {
  stub_herdr
  manifest '[[plugin]]
id = "a.first"
repo = "o/first"
ref = "v1.0.0"
needs = ["no-such-tool-xyz"]
why = "x"

[[plugin]]
id = "b.second"
repo = "o/second"
ref = "v2.0.0"
why = "x"'
  apply "$(new_home)"
  grep -q 'a.first needs no-such-tool-xyz' "${WORK}/last.out"
  refute 'install o/first' "${WORK}/herdr.log"
  grep -q 'install o/second --ref v2.0.0' "${WORK}/herdr.log"
}

case_check_reports_drift() {
  stub_herdr
  manifest "$ONE"
  list_line cloudmanic.herdr-plus cloudmanic/herdr-plus v0.1.20
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'cloudmanic.herdr-plus' "${WORK}/last.out"
  grep -q 'v0.1.20' "${WORK}/last.out"
  grep -q 'v0.1.24' "${WORK}/last.out"
  refute 'install' "${WORK}/herdr.log"
}

case_check_clean() {
  stub_herdr
  manifest "$ONE"
  list_line cloudmanic.herdr-plus cloudmanic/herdr-plus v0.1.24
  in_home "$(new_home)" bash "$PLUGINS_SH" --check
}

case_check_not_installed() {
  stub_herdr
  manifest "$ONE"
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'cloudmanic.herdr-plus: not installed' "${WORK}/last.out"
}

case_disabled_ignored() {
  stub_herdr
  manifest "$ONE
enabled = false"
  list_line cloudmanic.herdr-plus cloudmanic/herdr-plus v0.1.20
  in_home "$(new_home)" bash "$PLUGINS_SH" --check
  apply "$(new_home)"
  refute 'install' "${WORK}/herdr.log"
}

# invalid BODY NEEDLE: the manifest fails with exit 2 and a message naming NEEDLE.
invalid() {
  stub_herdr
  manifest "$1"
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 2 ]
  grep -q "plugins.toml: .*$2" "${WORK}/last.out"
}

case_invalid_manifest_unknown_key() {
  invalid "${ONE}
bogus = 1" bogus
}

case_invalid_manifest_bad_ref() {
  invalid "${ONE//v0.1.24/main}" "'ref'"
}

case_invalid_manifest_duplicate_id() {
  invalid "${ONE}

${ONE}" 'duplicate id'
}

case_invalid_manifest_needs_not_list() {
  invalid "${ONE}
needs = \"go\"" "'needs'"
}

case_invalid_manifest_apply_warns() {
  stub_herdr
  manifest "${ONE}
bogus = 1"
  local rc=0
  apply "$(new_home)" || rc=$?
  [ "$rc" -eq 2 ]
  grep -q 'bogus' "${WORK}/last.out"
}

case_templates_linked() {
  stub_herdr
  manifest '[[plugin]]
id = "persiyanov.reviewr"
repo = "persiyanov/herdr-reviewr"
ref = "v0.38.0"
why = "x"'
  list_line persiyanov.reviewr persiyanov/herdr-reviewr v0.38.0
  apply "$(new_home)"
  [ -L "${WORK}/config/persiyanov.reviewr/config.toml" ]
  refute 'install' "${WORK}/herdr.log"
}

case_old_python_skips() {
  stub_herdr
  manifest "$ONE"
  printf '#!/bin/sh\nexit 1\n' >"${WORK}/oldpy"
  chmod +x "${WORK}/oldpy"
  export DOTFILES_PYTHON="${WORK}/oldpy"
  local rc=0
  apply "$(new_home)" || rc=$?
  [ "$rc" -eq 2 ]
  grep -q 'Python 3.11' "${WORK}/last.out"
  grep -q 'new shell' "${WORK}/last.out"
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 2 ]
}

case_check_linked_plugin_is_drift() {
  stub_herdr
  manifest "$ONE"
  printf -- '- cloudmanic.herdr-plus (Name) enabled [linked:/x]\n' >"${WORK}/herdr.list"
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'manifest cloudmanic/herdr-plus@v0.1.24' "${WORK}/last.out"
}

case_first_failed_link_stops() {
  stub_herdr
  manifest '[[plugin]]
id = "persiyanov.reviewr"
repo = "persiyanov/herdr-reviewr"
ref = "v0.38.0"
why = "x"

[[plugin]]
id = "usagebar"
repo = "senna-lang/herdr-agent-usage"
ref = "v0.5.14"
why = "x"'
  list_line persiyanov.reviewr persiyanov/herdr-reviewr v0.38.0
  list_line usagebar senna-lang/herdr-agent-usage v0.5.14
  local rc=0
  export LINK_LOG="${WORK}/link.log"
  : >"$LINK_LOG"
  # Called the way ai/setup.sh calls it: under `set -e`, in an `||` list, where
  # errexit is off inside the function.
  # shellcheck disable=SC2016
  in_home "$(new_home)" bash -c 'set -euo pipefail
    . "$1/lib/common.sh"; . "$1/ai/herdr/plugins.sh"
    link() { echo "$1" >>"$LINK_LOG"; return 1; }
    rc=0
    herdr_plugins_apply || rc=$?
    exit "$rc"' _ "${DOTFILES}" || rc=$?
  [ "$rc" -eq 1 ]
  [ "$(wc -l <"${WORK}/link.log")" -eq 1 ]
}

case_mise_python_fallback() {
  stub_herdr
  manifest "$ONE"
  mkdir -p "${WORK}/fake"
  printf '#!/bin/sh\nexit 1\n' >"${WORK}/fake/python3"
  printf '#!/bin/sh\necho "%s"\n' "$(command -v python3)" >"${WORK}/fake/mise"
  chmod +x "${WORK}/fake/python3" "${WORK}/fake/mise"
  PATH="${WORK}/fake:${PATH}"
  unset DOTFILES_PYTHON
  apply "$(new_home)"
  grep -q 'install cloudmanic/herdr-plus' "${WORK}/herdr.log"
}

case_drift_match_is_anchored() {
  stub_herdr
  manifest '[[plugin]]
id = "usagebar"
repo = "senna-lang/herdr-agent-usage"
ref = "v0.5.14"
why = "x"

[[plugin]]
id = "x.usagebar"
repo = "x/usagebar"
ref = "v1.0.0"
why = "x"'
  list_line usagebar senna-lang/herdr-agent-usage v0.5.14
  list_line x.usagebar x/usagebar v9.9.9
  apply "$(new_home)"
  # Only the sibling drifted: one warning, not a second for usagebar.
  [ "$(grep -c 'usagebar: installed' "${WORK}/last.out")" -eq 1 ]
}

case_listed_without_ref_keeps_repo() {
  stub_herdr
  manifest "$ONE"
  printf -- '- cloudmanic.herdr-plus (Name) enabled [github:cloudmanic/herdr-plus]\n' >"${WORK}/herdr.list"
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'installed cloudmanic/herdr-plus@,' "${WORK}/last.out"
}

case_repo_subdir_accepted() {
  stub_herdr
  manifest "${ONE//cloudmanic\/herdr-plus/cloudmanic/herdr-plus/sub}"
  list_line cloudmanic.herdr-plus cloudmanic/herdr-plus/sub v0.1.24
  in_home "$(new_home)" bash "$PLUGINS_SH" --check
}

case_check_herdr_missing() {
  manifest "$ONE"
  mkdir -p "${WORK}/nobin"
  ln -s "$(command -v bash)" "${WORK}/nobin/bash"
  local rc=0
  in_home "$(new_home)" env PATH="${WORK}/nobin:/usr/bin:/bin" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 2 ]
  grep -q 'herdr not found' "${WORK}/last.out"
}

case_check_list_fails() {
  stub_herdr
  manifest "$ONE"
  printf '#!/bin/sh\nexit 1\n' >"${WORK}/bin/herdr"
  local rc=0
  in_home "$(new_home)" bash "$PLUGINS_SH" --check || rc=$?
  [ "$rc" -eq 2 ]
  grep -q 'plugin list failed' "${WORK}/last.out"
}

run_suite "$@"
