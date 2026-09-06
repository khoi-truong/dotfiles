# zsh/functions.zsh — shell functions. Anything that needs arguments or more
# than one line belongs here rather than in aliases.zsh.

# update — bring the machine up to date.
#   update          brew + mise
#   update --system also run `softwareupdate` (needs sudo, may reboot)
update() {
  local do_system=0
  [[ ${1:-} == "--system" ]] && do_system=1

  if (( $+commands[brew] )); then
    print -P "%F{blue}==>%f Homebrew"
    brew update && brew upgrade && brew cleanup
  fi

  if (( $+commands[mise] )); then
    print -P "%F{blue}==>%f mise"
    mise upgrade && mise prune --yes
  fi

  if (( do_system )); then
    print -P "%F{blue}==>%f macOS software update"
    sudo softwareupdate -i -a
  fi
}

# urlencode <string> — percent-encode a string.
urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$1"
}

# urldecode <string>
urldecode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote_plus(sys.argv[1]))' "$1"
}

# mkd <dir> — create a directory and cd into it.
mkd() {
  mkdir -p "$1" && cd "$1" || return
}

# mitm [args] — mitmproxy web UI on :8081, proxy on :8080. On first run it
# writes the CA to ~/.mitmproxy; trust it system-wide with `mitm-trust`.
mitm() {
  mitmweb --no-web-open-browser "$@"
}

# curlm [curl args] — curl routed through the running mitmproxy, trusting its CA.
curlm() {
  curl --proxy localhost:8080 \
    --cacert "${HOME}/.mitmproxy/mitmproxy-ca-cert.pem" "$@"
}

# mitm-trust — add the mitmproxy CA to the System keychain (needs sudo). Run
# once, after `mitm` has generated ~/.mitmproxy. Undo in Keychain Access.
mitm-trust() {
  sudo security add-trusted-cert -d -p ssl -k /Library/Keychains/System.keychain \
    "${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"
}

# claude — wrapper around the Claude Code CLI.
#
# Claude Code paints its startup banner before it drains stdin, so in the
# logged-in path (the Keychain check adds a beat) the terminal's replies to
# Claude's own XTVERSION/DA1 probes get echoed as literal garble around the
# logo. Turning echo off for the launch window closes that gap — Claude still
# reads and consumes the replies in raw mode.
claude() {
  local _stty _ret
  _stty=$(stty -g 2>/dev/null)
  if [[ -n $_stty ]]; then
    stty -echo 2>/dev/null
    trap 'stty "$_stty" 2>/dev/null' EXIT INT TERM
  fi
  command claude "$@"
  _ret=$?
  if [[ -n $_stty ]]; then
    stty "$_stty" 2>/dev/null
    trap - EXIT INT TERM
  fi
  return $_ret
}
