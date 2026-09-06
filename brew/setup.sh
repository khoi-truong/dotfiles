#!/usr/bin/env bash
# brew — install everything in brew/Brewfile.
#
#   brew/setup.sh            install only
#   brew/setup.sh --cleanup  install, then UNINSTALL anything not in the
#                            Brewfile (prompts unless --yes / $CI is set)
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
export HOMEBREW_BUNDLE_FILE="${CURRENT_DIR}/Brewfile"

do_cleanup=0
assume_yes="${CI:-0}"
for arg in "$@"; do
  case "$arg" in
    --cleanup) do_cleanup=1 ;;
    --yes | -y) assume_yes=1 ;;
    *) die "brew/setup.sh: unknown argument '$arg'" ;;
  esac
done

load_brew_shellenv || die "Homebrew not found. Install it first (see setup.sh)."

info "🍺 brew bundle install (${HOMEBREW_BUNDLE_FILE})"
brew bundle install --verbose

if [ "$do_cleanup" -eq 1 ]; then
  # `brew bundle cleanup -f` uninstalls every formula/cask not listed in the
  # Brewfile, so it is opt-in and confirmed.
  warn "The following would be UNINSTALLED:"
  brew bundle cleanup || true
  if [ "$assume_yes" != "1" ]; then
    printf 'Proceed with uninstall? [y/N] '
    read -r reply
    case "$reply" in
      [yY] | [yY][eE][sS]) ;;
      *)
        log "Skipped cleanup."
        exit 0
        ;;
    esac
  fi
  brew bundle cleanup --force
fi

ok "Homebrew bundle complete."
