# zsh/env.zsh — environment variables and $PATH. Sourced first by zshrc.
#
# PATH is built exactly once here. `typeset -U path` keeps it deduplicated, so
# re-sourcing this file (or `exec zsh`) never grows the variable.

typeset -U path fpath

# --- Homebrew --------------------------------------------------------------
# Equivalent to `eval "$(brew shellenv)"` but without the subprocess, which is
# ~50ms of every shell start. Prefixes differ by architecture:
#   arm64  -> /opt/homebrew
#   x86_64 -> /usr/local
if [[ -x /opt/homebrew/bin/brew ]]; then
  export HOMEBREW_PREFIX=/opt/homebrew
  export HOMEBREW_REPOSITORY=/opt/homebrew
else
  export HOMEBREW_PREFIX=/usr/local
  export HOMEBREW_REPOSITORY=/usr/local/Homebrew
fi
export HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
# Prepended, not appended: brew-installed git/zsh/nvim must win over the
# macOS system copies.
path=("${HOMEBREW_PREFIX}/bin" "${HOMEBREW_PREFIX}/sbin" $path)
fpath=("${HOMEBREW_PREFIX}/share/zsh/site-functions" $fpath)
export MANPATH="${HOMEBREW_PREFIX}/share/man:${MANPATH}"
export INFOPATH="${HOMEBREW_PREFIX}/share/info:${INFOPATH}"

# --- Go ------------------------------------------------------------------------
# mise owns the toolchain (GOROOT + the `go` binary). GOPATH is left at its
# default (~/go); GOBIN points at ~/.local/bin (on PATH below) so `go install`
# binaries sit with the other user CLIs. GOMODCACHE keeps the large, disposable
# module cache under ~/.cache instead of ~/go.
export GOBIN="${HOME}/.local/bin"
export GOMODCACHE="${HOME}/.cache/go/mod"

# --- Rust ------------------------------------------------------------------
export CARGO_HOME="${HOME}/.cargo"
path+=("${CARGO_HOME}/bin")

# --- Android ---------------------------------------------------------------
export ANDROID_HOME="${HOME}/Library/Android/sdk"
path+=(
  "${ANDROID_HOME}/platform-tools"
  "${ANDROID_HOME}/emulator"
  "${ANDROID_HOME}/cmdline-tools/latest/bin"
)

# --- pipx / user-local binaries -------------------------------------------
path+=("${HOME}/.local/bin")

export PATH
