#!/usr/bin/env bash
# Set the computer/host name. Called by macos/setup.sh.
set -uo pipefail

printf 'Please enter your computer name (leave blank to keep the current one): '
read -r COMPUTER_NAME

if [ -z "${COMPUTER_NAME}" ]; then
  echo "  › Keeping the current computer name."
  exit 0
fi

echo ""
echo "› System:"
echo "  › Set computer name and host name to ${COMPUTER_NAME}"
# As done via: System Settings > General > Sharing
sudo scutil --set ComputerName "${COMPUTER_NAME}"
sudo scutil --set HostName "${COMPUTER_NAME}"
sudo scutil --set LocalHostName "${COMPUTER_NAME}"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server \
  NetBIOSName -string "${COMPUTER_NAME}"
