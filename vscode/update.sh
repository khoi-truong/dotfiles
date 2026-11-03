#!/usr/bin/env bash
# Regenerate vscode/extensions.vscode from the installed extensions, or with
# --check report drift between the repo and the live profile (writes nothing).
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

check=0
if [ "$#" -eq 1 ] && [ "$1" = "--check" ]; then
  check=1
elif [ "$#" -ne 0 ]; then
  printf 'usage: update.sh [--check]\n' >&2
  exit 2
fi

CURRENT_DIR="$(module_dir)"
VSCODE_HOME="${HOME}/Library/Application Support/Code/User"
VSCODE_CLI="${DOTFILES_APPLICATIONS_DIR:-/Applications}/Visual Studio Code.app/Contents/Resources/app/bin/code"

if [ "${check}" -eq 0 ] && [ -x "${VSCODE_CLI}" ]; then
  link "${VSCODE_CLI}" "$(brew_prefix)/bin/code"
fi

# Under --check, exit 2 ("cannot check") instead of 1 ("drift").
cannot() {
  if [ "${check}" -eq 1 ]; then
    printf 'vscode: cannot check: %s\n' "$*" >&2
    exit 2
  fi
  die "$*"
}

if command -v code >/dev/null 2>&1; then
  CODE=code
elif [ -x "${VSCODE_CLI}" ]; then
  CODE="${VSCODE_CLI}"
else
  cannot "code CLI not found."
fi

installed="$("${CODE}" --list-extensions)" || cannot "code --list-extensions failed."

if [ "${check}" -eq 0 ]; then
  tmp="$(mktemp "${CURRENT_DIR}/extensions.vscode.XXXXXX")"
  trap 'rm -f "${tmp}"' EXIT
  printf '%s\n' "${installed}" | sed '/^$/d' | LC_ALL=C sort -fu >"${tmp}"
  mv "${tmp}" "${CURRENT_DIR}/extensions.vscode"
  ok "Wrote ${CURRENT_DIR}/extensions.vscode"
  exit 0
fi

drift=0
report() {
  drift=1
  printf 'vscode: %s\n' "$*"
}

for name in settings.json keybindings.json snippets; do
  live="${VSCODE_HOME}/${name}"
  repo="${CURRENT_DIR}/${name}"
  if [ -L "${live}" ]; then
    [ "$(readlink "${live}")" = "${repo}" ] ||
      report "${name} is a symlink to $(readlink "${live}"), not ${repo}"
  elif [ -e "${live}" ]; then
    report "${name} is not a symlink to ${repo}"
    if [ -d "${live}" ]; then
      diff -ru "${repo}" "${live}" || true
    else
      diff -u "${repo}" "${live}" || true
    fi
  else
    report "${name} is missing from ${VSCODE_HOME}"
  fi
done

normalise() { tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u; }
installed="$(printf '%s\n' "${installed}" | normalise)"
listed="$(normalise <"${CURRENT_DIR}/extensions.vscode")"
while IFS= read -r id; do
  if [ -n "${id}" ]; then report "extension installed but not listed: ${id}"; fi
done < <(comm -23 <(printf '%s\n' "${installed}") <(printf '%s\n' "${listed}"))
while IFS= read -r id; do
  if [ -n "${id}" ]; then report "extension listed but not installed: ${id}"; fi
done < <(comm -13 <(printf '%s\n' "${installed}") <(printf '%s\n' "${listed}"))

if [ "${drift}" -eq 0 ]; then
  log "vscode: no drift"
fi
exit "${drift}"
