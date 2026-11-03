#!/usr/bin/env bash
# vscode/setup.sh and vscode/update.sh against a copy of the module, a fake
# `code` and an empty applications dir, under a throwaway HOME.
#
#   bash tests/vscode.sh              every case_*
#   bash tests/vscode.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# fixture: a fresh copy of lib/ and vscode/ in $WORK/repo (so update.sh never
# rewrites the real extensions.vscode), a fake `code` and `uv` on PATH, and an
# empty applications dir so the real CLI is never linked into the brew prefix.
# Sets REPO, CODE_LOG, PATH and DOTFILES_APPLICATIONS_DIR for the case.
fixture() {
  REPO="${WORK}/repo"
  CODE_LOG="${WORK}/code.log"
  rm -rf "$REPO" "${WORK}/fakebin" "${WORK}/apps"
  mkdir -p "$REPO" "${WORK}/fakebin" "${WORK}/apps"
  cp -R "${DOTFILES}/lib" "${DOTFILES}/vscode" "$REPO/"
  : >"$CODE_LOG"
  : >"${WORK}/installed"
  cat >"${WORK}/fakebin/code" <<'STUB'
#!/bin/sh
echo "$*" >>"$CODE_LOG"
if [ "$1" = "--list-extensions" ]; then
  cat "$WORK/installed"
fi
STUB
  printf '#!/bin/sh\nexit 0\n' >"${WORK}/fakebin/uv"
  chmod +x "${WORK}/fakebin/code" "${WORK}/fakebin/uv"
  PATH="${WORK}/fakebin:${PATH}"
  DOTFILES_APPLICATIONS_DIR="${WORK}/apps"
  export WORK CODE_LOG PATH DOTFILES_APPLICATIONS_DIR
}

profile() { printf '%s/Library/Application Support/Code/User' "$1"; }

run_vscode() {
  local script="$1" h="$2"
  shift 2
  in_home "$h" bash "${REPO}/vscode/${script}.sh" "$@"
}

case_setup_links_profile() {
  local h p
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  p="$(profile "$h")"
  for f in settings.json keybindings.json snippets; do
    [ -L "$p/$f" ]
    [ "$(readlink "$p/$f")" = "$REPO/vscode/$f" ]
  done
}

case_setup_snippets_dir_not_nested() {
  local h p
  h="$(new_home)"
  fixture
  p="$(profile "$h")"
  mkdir -p "$p/snippets"
  echo '{}' >"$p/snippets/mine.json"
  run_vscode setup "$h"
  [ -L "$p/snippets" ]
  [ ! -e "$REPO/vscode/snippets/snippets" ]
  [ ! -e "$p/snippets/snippets" ]
  set -- "$h"/.local/state/dotfiles/backups/*/files/*/mine.json
  [ -f "$1" ]
}

case_setup_no_extensions_by_default() {
  local h
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  if grep -q -- '--install-extension' "$CODE_LOG"; then return 1; fi
  grep -q -- '--extensions' "${WORK}/last.out"
}

case_setup_extensions_flag_installs_each() {
  local h id
  h="$(new_home)"
  fixture
  run_vscode setup "$h" --extensions
  while read -r id; do
    [ -n "$id" ] || continue
    grep -qx -- "--install-extension $id" "$CODE_LOG"
  done <"$REPO/vscode/extensions.vscode"
  [ "$(grep -c -- '--install-extension' "$CODE_LOG")" -eq "$(grep -c . "$REPO/vscode/extensions.vscode")" ]
}

case_setup_unknown_flag_fails() {
  local h
  h="$(new_home)"
  fixture
  if run_vscode setup "$h" --bogus; then return 1; fi
  grep -q 'unknown argument' "${WORK}/last.out"
}

case_update_sorted_and_idempotent() {
  local h first
  h="$(new_home)"
  fixture
  printf 'b.Two\nz.last\nA.one\nb.Two\n' >"${WORK}/installed"
  run_vscode update "$h"
  first="$(shasum "$REPO/vscode/extensions.vscode")"
  [ "$(cat "$REPO/vscode/extensions.vscode")" = "$(printf 'A.one\nb.Two\nz.last')" ]
  LC_ALL=C sort -fuc "$REPO/vscode/extensions.vscode"
  run_vscode update "$h"
  [ "$(shasum "$REPO/vscode/extensions.vscode")" = "$first" ]
  set -- "$REPO"/vscode/extensions.vscode.*
  [ ! -e "$1" ]
}

case_update_unknown_arg_exits_2() {
  local h status=0
  h="$(new_home)"
  fixture
  run_vscode update "$h" --bogus || status=$?
  [ "$status" -eq 2 ]
}

case_check_clean_exits_0() {
  local h before after
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  cp "$REPO/vscode/extensions.vscode" "${WORK}/installed"
  before="$(cd "$REPO/vscode" && shasum settings.json keybindings.json extensions.vscode snippets/*)"
  run_vscode update "$h" --check
  grep -q 'vscode: no drift' "${WORK}/last.out"
  after="$(cd "$REPO/vscode" && shasum settings.json keybindings.json extensions.vscode snippets/*)"
  [ "$before" = "$after" ]
}

case_check_reports_replaced_keybindings() {
  local h p status=0 before
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  cp "$REPO/vscode/extensions.vscode" "${WORK}/installed"
  p="$(profile "$h")"
  rm "$p/keybindings.json"
  echo '[]' >"$p/keybindings.json"
  before="$(shasum "$p/keybindings.json")"
  run_vscode update "$h" --check || status=$?
  [ "$status" -eq 1 ]
  grep -q 'keybindings.json' "${WORK}/last.out"
  grep -q '^[-+]\[\]$' "${WORK}/last.out"
  [ ! -L "$p/keybindings.json" ]
  [ "$(shasum "$p/keybindings.json")" = "$before" ]
}

case_check_reports_missing_and_foreign_symlink() {
  local h p status=0
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  cp "$REPO/vscode/extensions.vscode" "${WORK}/installed"
  p="$(profile "$h")"
  rm "$p/settings.json" "$p/snippets"
  ln -s "$WORK" "$p/snippets"
  run_vscode update "$h" --check || status=$?
  [ "$status" -eq 1 ]
  grep -q 'settings.json is missing' "${WORK}/last.out"
  grep -q "snippets is a symlink to $WORK" "${WORK}/last.out"
}

case_check_reports_extension_drift() {
  local h status=0
  h="$(new_home)"
  fixture
  run_vscode setup "$h"
  cp "$REPO/vscode/extensions.vscode" "${WORK}/installed"
  echo extra.installed-only >>"${WORK}/installed"
  grep -vx 'golang.go' "${WORK}/installed" >"${WORK}/installed.new"
  mv "${WORK}/installed.new" "${WORK}/installed"
  run_vscode update "$h" --check || status=$?
  [ "$status" -eq 1 ]
  grep -q 'installed but not listed: extra.installed-only' "${WORK}/last.out"
  grep -q 'listed but not installed: golang.go' "${WORK}/last.out"
}

case_rubylsp_uses_mise() {
  python3 -B -I - "${DOTFILES}/vscode/settings.json" <<'PY'
import json, re, sys

text = open(sys.argv[1], encoding="utf-8").read()
# Strip // and /* */ comments outside strings, then trailing commas.
out, i, n, in_str = [], 0, len(text), False
while i < n:
    c = text[i]
    if in_str:
        out.append(c)
        if c == "\\":
            out.append(text[i + 1])
            i += 1
        elif c == '"':
            in_str = False
    elif c == '"':
        in_str = True
        out.append(c)
    elif text.startswith("//", i):
        while i < n and text[i] != "\n":
            i += 1
        continue
    elif text.startswith("/*", i):
        i = text.index("*/", i) + 2
        continue
    else:
        out.append(c)
    i += 1
data = json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))
manager = data.get("rubyLsp.rubyVersionManager")
identifier = manager.get("identifier") if isinstance(manager, dict) else data.get("rubyLsp.rubyVersionManager.identifier")
assert identifier == "mise", identifier
assert "rubyLsp.rubyExecutablePath" not in data
PY
}

run_suite "$@"
