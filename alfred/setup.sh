#!/bin/sh

[ "$(uname -s)" != "Darwin" ] && exit 0

echo ""
echo "Setting up Alfred..."

for app in "Alfred" \
	"Alfred Preferences"; do
	killall "${app}" &> /dev/null
done

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";
SYNC_FOLDER="${DOTFILES}/alfred"
SYNC_FILE="${SYNC_FOLDER}/Alfred.alfredpreferences"
# Using Parameter expansion
# https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
# https://www.cyberciti.biz/tips/bash-shell-parameter-substitution-2.html
PREF="{
  \"current\" : \"${SYNC_FILE//\//\\/}\",
  \"syncfolders\" : {
    \"4\" : \"${SYNC_FOLDER//\//\\/}\"
  }
}"
echo "${PREF}" > ~/Library/Application\ Support/Alfred/prefs.json
defaults write com.runningwithcrayons.Alfred-Preferences "syncfolder" -string "${SYNC_FOLDER}"
/usr/libexec/PlistBuddy -c "Set :syncfolder ${SYNC_FOLDER}" ~/Library/Preferences/com.runningwithcrayons.Alfred-Preferences.plist
