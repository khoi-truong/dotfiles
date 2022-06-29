echo "Please enter your computer name:"
read COMPUTER_NAME

echo ""
echo "› System:"

echo "  › Set computer name and host name to ${COMPUTER_NAME}"
# As done via		: System Preferences > Sharing
sudo scutil --set ComputerName "${COMPUTER_NAME}"
sudo scutil --set HostName "${COMPUTER_NAME}"
sudo scutil --set LocalHostName "${COMPUTER_NAME}"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${COMPUTER_NAME}"
