#!/usr/bin/env bash
# Installs and checks the herdr plugins pinned in plugins.toml.
#
#   bash ai/herdr/plugins.sh            install what is missing, link templates
#   bash ai/herdr/plugins.sh --check    report drift from the manifest, change nothing
#
# herdr_plugins_apply returns 0 ok, 1 a link failed (stop), 2 manifest error or no
# usable Python (warn and carry on).
#
# Sourced by ai/setup.sh, which calls herdr_plugins_apply so the `link` calls
# stay inside setup's transaction. plugins.py reads the manifest and needs
# Python 3.11+: DOTFILES_PYTHON, else the first python3 on PATH. Too old or
# missing, apply warns and returns 0 (setup carries on) and --check exits 2.
# DOTFILES_HERDR_PLUGINS points at another manifest.

HERDR_PLUGINS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# True when `herdr plugin list` reports the given plugin id. `herdr plugin
# config-dir` cannot answer this: it only computes a path and exits 0 for any
# string, whether the plugin exists or not.
herdr_plugin_installed() {
  herdr plugin list --plugin "$1" --json 2>/dev/null |
    grep -q '"plugins":\[[^]]'
}

# True when "$1" runs as a Python >= 3.11. Checks sys.version_info, not -V.
herdr_python_ok() {
  command -v "$1" >/dev/null 2>&1 &&
    "$1" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null
}

# Echoes a Python >= 3.11, or returns 1. DOTFILES_PYTHON, else python3 on PATH,
# else mise's: on a fresh machine ./setup.sh runs before mise's shims are on
# PATH, so python3 is the macOS 3.9 one.
herdr_plugins_python() {
  local py="${DOTFILES_PYTHON:-python3}"
  if herdr_python_ok "${py}"; then
    printf '%s\n' "${py}"
    return 0
  fi
  [ -z "${DOTFILES_PYTHON:-}" ] && command -v mise >/dev/null 2>&1 || return 1
  py="$(mise which python3 2>/dev/null)" || return 1
  herdr_python_ok "${py}" && printf '%s\n' "${py}"
}

herdr_plugins_apply() {
  local py rows drifted plugin repo ref needs tool plugin_config item missing
  if ! py="$(herdr_plugins_python)"; then
    warn "herdr plugins need Python 3.11+ (DOTFILES_PYTHON, python3 or mise's) — skipping; re-run in a new shell once mise is active."
    return 2
  fi
  if ! rows="$("${py}" "${HERDR_PLUGINS_DIR}/plugins.py" rows)"; then
    warn "herdr plugins manifest is invalid — skipping plugins."
    return 2
  fi
  # Installed at a ref other than the manifest's: reported per plugin below.
  drifted="$(herdr plugin list 2>/dev/null | "${py}" "${HERDR_PLUGINS_DIR}/plugins.py" check || true)"

  # Plugins are installed here, pinned to a release tag by plugins.toml. An
  # unpinned install re-fetches the default branch, so leaving the ref off
  # would silently move a plugin to current HEAD. This script is re-run after
  # every `brew upgrade herdr`, after a plugin install and on a new machine, so
  # that drift would be routine.
  #
  # Installs stop for the manifest preview (no --yes) because plugins run
  # unsandboxed as your user. Once a plugin is installed, this links the
  # versioned templates under herdr/plugins/<plugin id>/ into its config dir;
  # a plugin with no template dir simply gets nothing linked.
  #
  # "Installed?" is asked with `plugin list`, not `plugin config-dir`:
  # config-dir just computes a path and succeeds for any string, installed or
  # not, so testing it would skip every install. An uninstalled id lists as an
  # empty plugins array.
  #
  # The rows are read on fd 3, not stdin: the install prompt reads from stdin,
  # and would otherwise swallow the next plugin's row as its answer.
  while IFS=$'\t' read -r plugin repo ref needs <&3; do
    [ -n "${plugin}" ] || continue
    missing=""
    for tool in ${needs//,/ }; do
      command -v "${tool}" >/dev/null 2>&1 || {
        missing="${tool}"
        break
      }
    done
    if [ -n "${missing}" ]; then
      warn "herdr plugin ${plugin} needs ${missing} — skipping."
      continue
    fi
    if ! herdr_plugin_installed "${plugin}"; then
      info "herdr plugin ${plugin} not installed — installing ${repo}@${ref}."
      info "Read the manifest preview; this is not passed --yes."
      if ! herdr plugin install "${repo}" --ref "${ref}"; then
        warn "herdr plugin ${repo} install failed or was declined — skipping."
        continue
      fi
      if ! herdr_plugin_installed "${plugin}"; then
        warn "herdr plugin ${plugin} still not listed after install — skipping."
        continue
      fi
    else
      item="$(printf '%s\n' "${drifted}" | awk -v p="${plugin}: installed " 'index($0, p) == 1' || true)"
      if [ -n "${item}" ]; then
        warn "${item}"
        warn "to bump: herdr plugin uninstall ${plugin}, then re-run ai/setup.sh."
      fi
    fi
    plugin_config="$(herdr plugin config-dir "${plugin}" 2>/dev/null)" || plugin_config=""
    if [ -z "${plugin_config}" ]; then
      warn "herdr plugin ${plugin} has no config dir — skipping."
      continue
    fi
    for item in "${HERDR_PLUGINS_DIR}"/plugins/"${plugin}"/*; do
      [ -e "$item" ] || continue
      link "$item" "${plugin_config}/$(basename "$item")" || return 1
    done
  done 3<<<"${rows}"
}

# Exit 0 clean, 1 drift, 2 bad manifest or no usable Python.
herdr_plugins_check() {
  local py
  if ! py="$(herdr_plugins_python)"; then
    printf 'herdr plugins need Python 3.11+ (DOTFILES_PYTHON, python3 or mise)\n' >&2
    return 2
  fi
  herdr plugin list | "${py}" "${HERDR_PLUGINS_DIR}/plugins.py" check
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  # shellcheck source=lib/common.sh
  . "${HERDR_PLUGINS_DIR}/../../lib/common.sh"
  case "${1:-}" in
    --check) herdr_plugins_check ;;
    '') herdr_plugins_apply ;;
    *)
      printf 'usage: plugins.sh [--check]\n' >&2
      exit 2
      ;;
  esac
fi
