#!/usr/bin/env bash
# Alfred — point the app's sync folder at this repo.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
SYNC_FILE="${CURRENT_DIR}/Alfred.alfredpreferences"
PREFS_JSON="${HOME}/Library/Application Support/Alfred/prefs.json"
PREFS_PLIST="${HOME}/Library/Preferences/com.runningwithcrayons.Alfred-Preferences.plist"

info "Setting up Alfred..."

# Alfred rewrites these files on quit, so it must not be running.
for app in "Alfred" "Alfred Preferences"; do
  killall "${app}" >/dev/null 2>&1 || true
done

mkdir -p "$(dirname "${PREFS_JSON}")"
# Paths inside prefs.json are JSON strings with escaped slashes.
cat >"${PREFS_JSON}" <<EOF
{
  "current" : "${SYNC_FILE//\//\\/}",
  "syncfolders" : {
    "4" : "${CURRENT_DIR//\//\\/}"
  }
}
EOF

defaults write com.runningwithcrayons.Alfred-Preferences syncfolder -string "${CURRENT_DIR}"
if [ -f "${PREFS_PLIST}" ]; then
  /usr/libexec/PlistBuddy -c "Set :syncfolder ${CURRENT_DIR}" "${PREFS_PLIST}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :syncfolder string ${CURRENT_DIR}" "${PREFS_PLIST}"
fi

ok "Alfred sync folder -> ${CURRENT_DIR}"
