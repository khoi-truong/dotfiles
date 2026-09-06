#!/usr/bin/env bash
# Stats — import the menu bar layout / sensor selection.
#
# Stats (eu.exelban.Stats) has no dotfile; it keeps everything in
# ~/Library/Preferences/eu.exelban.Stats.plist. This module imports the
# committed copy. After changing anything in Stats' UI, re-export with
# `bash misc/stats/update.sh` and commit the diff.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
PLIST="${CURRENT_DIR}/eu.exelban.Stats.plist"

if [ ! -d "/Applications/Stats.app" ]; then
  warn "Stats is not installed; skipping preference import."
  exit 0
fi

info "Importing Stats preferences..."
killall Stats 2>/dev/null || true
defaults import eu.exelban.Stats "${PLIST}"
ok "Stats preferences imported (open Stats to apply)."
