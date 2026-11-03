#!/usr/bin/env bash
# gpg/setup.sh under a throwaway HOME, stdin from /dev/null (no tty).
#
#   bash tests/gpg.sh              every case_*
#   bash tests/gpg.sh <case_name>  that case only
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

case_first_run_writes_both() {
  local h
  h="$(new_home)"
  run_module gpg "$h"
  [ "$(mode "$h/.gnupg")" = 700 ]
  [ "$(mode "$h/.gnupg/gpg.conf")" = 600 ]
  [ "$(mode "$h/.gnupg/gpg-agent.conf")" = 600 ]
  cmp -s "$DOTFILES/gpg/gpg.conf" "$h/.gnupg/gpg.conf"
}

case_second_run_unchanged() {
  local h m1 m2 n
  h="$(new_home)"
  run_module gpg "$h"
  m1="$(mtime "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg-agent.conf")"
  sleep 1
  run_module gpg "$h"
  m2="$(mtime "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg-agent.conf")"
  n="$(grep -c 'unchanged' "${WORK}/last.out")"
  [ "$n" -eq 2 ]
  [ "$m1" = "$m2" ]
}

case_drift_is_rewritten() {
  local h
  h="$(new_home)"
  run_module gpg "$h"
  echo "drifted-line" >>"$h/.gnupg/gpg.conf"
  run_module gpg "$h"
  cmp -s "$DOTFILES/gpg/gpg.conf" "$h/.gnupg/gpg.conf"
  [ "$(mode "$h/.gnupg/gpg.conf")" = 600 ]
}

case_unchanged_content_gets_mode_600() {
  local h
  h="$(new_home)"
  run_module gpg "$h"
  chmod 644 "$h/.gnupg/gpg-agent.conf"
  run_module gpg "$h"
  [ "$(mode "$h/.gnupg/gpg-agent.conf")" = 600 ]
}

# Answering n on a tty writes nothing: a pty via python3 pty.fork.
case_tty_n_writes_nothing() {
  local h before after
  if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP case_tty_n_writes_nothing: python3 not available" >&2
    return 0
  fi
  h="$(new_home)"
  mkdir -m 700 "$h/.gnupg"
  echo "# stale" >"$h/.gnupg/gpg.conf"
  chmod 640 "$h/.gnupg/gpg.conf"
  touch -t 202001010000 "$h/.gnupg/gpg.conf"
  before="$(shasum "$h/.gnupg/gpg.conf") $(mode "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg.conf")"
  python3 -I - "$h" "$DOTFILES/gpg/setup.sh" >"${WORK}/last.out" 2>&1 <<'PY'
import os, pty, sys, time
home, script = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    for k in ("XDG_STATE_HOME", "XDG_CONFIG_HOME", "DOTFILES_ATTEMPT", "DOTFILES"):
        os.environ.pop(k, None)
    os.environ["HOME"] = home
    os.execvp("bash", ["bash", script])
buf = b""
sent = False
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    buf += data
    if not sent and b"[y/N]" in buf:
        os.write(fd, b"n\n")
        sent = True
sys.stdout.write(buf.decode(errors="replace"))
_, status = os.waitpid(pid, 0)
if not sent:
    sys.exit("no prompt seen")
sys.exit(os.waitstatus_to_exitcode(status))
PY
  after="$(shasum "$h/.gnupg/gpg.conf") $(mode "$h/.gnupg/gpg.conf") $(mtime "$h/.gnupg/gpg.conf")"
  [ "$before" = "$after" ]
  [ ! -e "$h/.gnupg/gpg-agent.conf" ]
  grep -q 'GPG configuration unchanged' "${WORK}/last.out"
}

case_conf_parses() {
  local home
  if ! command -v gpg >/dev/null 2>&1; then
    echo "SKIP case_conf_parses: gpg not installed" >&2
    return 0
  fi
  home="$(mktemp -d "${WORK}/gnupg.XXXXXX")"
  chmod 700 "$home"
  GNUPGHOME="$home" gpg --options "$DOTFILES/gpg/gpg.conf" --gpgconf-test >"${WORK}/last.out" 2>&1
}

run_suite "$@"
