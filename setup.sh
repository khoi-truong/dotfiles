#!/usr/bin/env bash
#
# Bootstrap this machine.
#
#   ./setup.sh              default modules (see DEFAULT_MODULES)
#   ./setup.sh --all        default modules + the opt-in ones
#   ./setup.sh vscode git   only the named modules, in the order given
#   ./setup.sh --list       show available modules
#
# Every module is a self-contained <module>/setup.sh that can also be run on
# its own. Modules are idempotent: re-running is always safe.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
export DOTFILES
. "${DOTFILES}/lib/common.sh"
require_macos

# Run on every bootstrap.
DEFAULT_MODULES=(git brew mise macos gpg iterm alfred ai misc)

# Opt-in: GUI apps that aren't always installed, or one-off machines.
OPTIONAL_MODULES=(vscode xcode terminal)

usage() {
  cat <<EOF
usage: ./setup.sh [--all | --list | <module>...]

  default : ${DEFAULT_MODULES[*]}
  optional: ${OPTIONAL_MODULES[*]}
EOF
}

modules=("${DEFAULT_MODULES[@]}")
case "${1:-}" in
  --all) modules=("${DEFAULT_MODULES[@]}" "${OPTIONAL_MODULES[@]}") ;;
  --list)
    usage
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  -*) die "unknown option: $1" ;;
  *) modules=("$@") ;;
esac

# --- Homebrew --------------------------------------------------------------
# Install first: every other module may depend on brew-installed binaries.
if ! load_brew_shellenv; then
  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_shellenv || die "Homebrew install did not produce a usable brew."
fi
ok "Homebrew at $(brew_prefix)"

# --- sudo keep-alive -------------------------------------------------------
# macos/ needs it; asking once up front avoids prompts mid-run.
sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

# --- shell -----------------------------------------------------------------
info "Linking shell configuration..."
link "${DOTFILES}/zsh/zshenv" "${HOME}/.zshenv"
link "${DOTFILES}/zsh/zshrc" "${HOME}/.zshrc"
link "${DOTFILES}/ssh/config" "${HOME}/.ssh/config"
link "${DOTFILES}/curl/curlrc" "${HOME}/.curlrc"
link "${DOTFILES}/tmux/tmux.conf" "${HOME}/.tmux.conf"
link "${DOTFILES}/vim/vimrc" "${HOME}/.vimrc"

# Redundant state: history and the completion dump both live in zsh/local/.
rm -f "${HOME}/.zsh_history" "${HOME}"/.zcompdump*
rm -rf "${HOME}/.zsh_sessions"

# --- modules ---------------------------------------------------------------
for module in "${modules[@]}"; do
  script="${DOTFILES}/${module}/setup.sh"
  if [ ! -f "${script}" ]; then
    warn "no such module: ${module}"
    continue
  fi
  log ""
  info "── ${module} ──"
  bash "${script}"
done

log ""
ok "Setup complete. Open a new shell (or \`exec zsh\`)."
log "🚀🚀🚀"
