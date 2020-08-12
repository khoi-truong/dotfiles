#!/bin/sh

# ~/.macos — https://mths.be/macos
# https://github.com/kevinSuttle/macOS-Defaults

# Close any open System Preferences panes, to prevent them from overriding
# settings we’re about to change
echo "Begin setting up macos..."
osascript -e 'tell application "System Preferences" to quit'

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.macos` has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

###############################################################################
# System                                                                      #
###############################################################################

COMPUTER_NAME="MATRIX"
echo ""
echo "› System:"

echo "  › Set computer name and host name to ${COMPUTER_NAME}"
# As done via		: System Preferences > Sharing
sudo scutil --set ComputerName "${COMPUTER_NAME}"
sudo scutil --set HostName "${COMPUTER_NAME}"
sudo scutil --set LocalHostName "${COMPUTER_NAME}"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${COMPUTER_NAME}"

echo "  › Disable the sound effects on boot"
sudo nvram SystemAudioVolume=" "

###############################################################################
# General                                                                     #
###############################################################################

echo "  › Set macos appearance to Dark"
# As done via		: System Preferences > General > Appearance
# Possible values	: Dark, Light
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false

echo "  › Set accent color to Blue"
# As done via		: System Preferences > General > Highlight color
# Accent colour
# this setting defines two properties:
#   - AppleAccentColor
#   - AppleAquaColorVariant
# it also presets AppleHighlightColor, but this can be overriden
#
# note that AppleAquaColorVariant is alway "1" except for "Graphite", where it is "6".
# note that the AccentColor "Blue" is default (when there is no entry) and has no AppleHighlightColor definition.
#
# Color    AppleAquaColorVariant    AccentColor    AppleHighlightColor
#   Red            1                   0           "1.000000 0.733333 0.721569 Red"
#   Orange         1                   1           "1.000000 0.874510 0.701961 Orange"
#   Yellow         1                   2           "1.000000 0.937255 0.690196 Yellow"
#   Green          1                   3           "0.752941 0.964706 0.678431 Green"
#   Purple         1                   5           "0.968627 0.831373 1.000000 Purple"
#   Pink           1                   6           "1.000000 0.749020 0.823529 Pink"
#   Blue           1                   deleted     deleted
#   Graphite       6                   -1          "0.847059 0.847059 0.862745 Graphite"
defaults delete NSGlobalDomain AccentColor
defaults write NSGlobalDomain AppleAquaColorVariant -int 1

echo "  › Set macos highlight color to Blue"
# As done via		: System Preferences > General > Highlight color
defaults delete NSGlobalDomain AppleHighlightColor

echo "  › Set sidebar icon size to medium"
# As done via		: System Preferences > General > Sidebar icon size
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2

# echo "  › Disable transparency in the menu bar and elsewhere"
# Default value		: false
# defaults write com.apple.universalaccess reduceTransparency -bool true

echo "  › Automatic show scroll bars"
# As done via		: System Preferences > General > Show scroll bars: Automatic
# Possible values	: WhenScrolling, Automatic, Always
defaults write NSGlobalDomain AppleShowScrollBars -string "Automatic"

echo "  › Set scrollbars to jump to the spot that's clicked"
# As done via		: System Preferences > General > Click in the scrollbar to
# Default value		: false
defaults write NSGlobalDomain AppleScrollerPagingBehavior -bool true

echo "  › Disable restoring windows when re-open an app"
# As done via		: System Preferences > General > Close windows when quitting an app
# Default value		: true
defaults write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false

# echo "  › Disable the over-the-top focus ring animation"
# Default value		: true
# defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false

echo "  › Increase window resize speed for Cocoa applications"
# Default value		: 0.2
defaults write NSGlobalDomain NSWindowResizeTime -float 0.2

echo "  › Collapse save panel by default"
# Default value		: false
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool false
# Default value		: false
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool false

echo "  › Expand print panel by default"
# Default value		: false
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
# Default value		: false
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

echo "  › Save to disk (not to iCloud) by default"
# Default value		: true
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

echo "  › Automatically quit printer app once the print jobs complete"
# Default value		: false
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

echo "  › Disable the \"Are you sure you want to open this application?\" dialog"
# Default value		: true
defaults write com.apple.LaunchServices LSQuarantine -bool false

echo "  › Remove duplicates in the \"Open With\" menu (also see \`lscleanup\` alias)"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user

# echo "  › Display ASCII control characters using caret notation in standard text views"
# Default value		: false
# Try e.g. `cd /tmp; unidecode "\x{0000}" > cc.txt; open -e cc.txt`
# defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true

echo "  › Enable automatic termination of inactive apps"
# Default value		: false
defaults write NSGlobalDomain NSDisableAutomaticTermination -bool false

echo "  › Disable the crash reporter"
# Default value		: crashreport
defaults write com.apple.CrashReporter DialogType -string "none"

echo "  › Set Help Viewer windows to floating mode"
# Default value		: false
defaults write com.apple.helpviewer DevMode -bool false

echo "  › Reveal IP address, hostname, OS version, etc. when clicking the clock in the login window"
sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName

# echo "  › Disable Notification Center and remove the menu bar icon"
# launchctl unload -w /System/Library/LaunchAgents/com.apple.notificationcenterui.plist 2> /dev/null

# echo "  › Disable automatic capitalization as it’s annoying when typing code"
# defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# echo "  › Disable smart dashes as they’re annoying when typing code"
# defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# echo "  › Disable automatic period substitution as it’s annoying when typing code"
# defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# echo "  › Disable smart quotes as they’re annoying when typing code"
# defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

echo "  › Disable auto-correct"
# Default value		: true
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

###############################################################################
# Dock, Dashboard, and Mission Control                                        #
###############################################################################

echo ""
echo "› Dock, Dashboard, and Mission Control:"
echo "  › Enable highlight hover effect for the grid view of a stack (Dock)"
# Default value		: false
defaults write com.apple.dock mouse-over-hilite-stack -bool true

echo "  › Set the icon size of Dock items to 32 pixels"
# As done via		: System Preferences > Dock > Size
defaults write com.apple.dock tilesize -int 32

echo "  › Change minimize/maximize window effect"
# As done via		: System Preferences > Dock > Minimize windows using
# Possible values	: genie, scale
# Default value		: genie
defaults write com.apple.dock mineffect -string "genie"

echo "  › Minimize windows into application icon"
# As done via		: System Preferences > Dock > Minimize windows into application icon
# Default value		: false
defaults write com.apple.dock minimize-to-application -bool true

echo "  › Don’t animate opening applications from the Dock"
# As done via		: System Preferences > Dock > Animate opening applications
defaults write com.apple.dock launchanim -bool false

echo "  › Don't automatically hide and show the Dock"
# As done via		: System Preferences > Dock > Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool false

echo "  › Show indicators for open applications"
# As done via		: System Preferences > Dock > Show indicators for open applications
defaults write com.apple.dock show-process-indicators -bool true

echo "  › Show recent applications in Dock"
# As done via		: System Preferences > Dock > Show recent applications in Dock
defaults write com.apple.dock show-recents -bool true

echo "  › Enable spring loading for all Dock items"
# Default value		: false
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

echo "  › Speed up Mission Control animations"
defaults write com.apple.dock expose-animation-duration -float 0.1

echo "  › Group windows by application in Mission Control"
# As done via		: System Preferences > Mission Control > Group windows by application
defaults write com.apple.dock expose-group-by-app -bool false

echo "  › Don’t automatically rearrange Spaces based on most recent use"
# As done via		: System Preferences > Mission Control > Automatically rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

echo "  › Disable Dashboard"
defaults write com.apple.dashboard mcx-disabled -bool true

echo "  › Don’t show Dashboard as a Space"
defaults write com.apple.dock dashboard-in-overlay -bool true

# echo "  › Remove the auto-hiding Dock delay"
# defaults write com.apple.dock autohide-delay -float 0
# Restore
# defaults delete com.apple.dock autohide-delay

# echo "  › Remove the animation when hiding/showing the Dock"
# defaults write com.apple.dock autohide-time-modifier -float 0
# Restore
# defaults delete com.apple.dock autohide-time-modifier

# echo "  › Make Dock icons of hidden applications translucent"
# Default value		: false
# defaults write com.apple.dock showhidden -bool true

echo "  › Enable the Launchpad gesture (pinch with thumb and three fingers)"
# As done via		: System Preferences > Trackpad > Launchpad
defaults write com.apple.dock showLaunchpadGestureEnabled -bool true

# echo "  › Reset Launchpad, but keep the desktop wallpaper intact"
# find "${HOME}/Library/Application Support/Dock" -name "*-*.db" -maxdepth 1 -delete

# echo "  › Add iOS & Watch Simulator to Launchpad"
# sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" "/Applications/Simulator.app"
# sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator (Watch).app" "/Applications/Simulator (Watch).app"

# echo "  › Add a spacer to the left side of the Dock (where the applications are)"
# defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
# echo "  › Add a spacer to the right side of the Dock (where the Trash is)"
# defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type="spacer-tile";}'

# Hot corners
# Possible values:
#  0: no-op
#  2: Mission Control
#  3: Show application windows
#  4: Desktop
#  5: Start screen saver
#  6: Disable screen saver
#  7: Dashboard
# 10: Put display to sleep
# 11: Launchpad
# 12: Notification Center
# 13: Lock Screen
# Top left screen corner → Mission Control
# defaults write com.apple.dock wvous-tl-corner -int 2
# defaults write com.apple.dock wvous-tl-modifier -int 0
# Top right screen corner → Desktop
# defaults write com.apple.dock wvous-tr-corner -int 4
# defaults write com.apple.dock wvous-tr-modifier -int 0
# Bottom left screen corner → Desktop
echo "  › Set bottom left hot corner behavior to Show desktop"
# As done via		: System Preferences > Mission Control > Hot corners...
defaults write com.apple.dock wvous-bl-corner -int 4
defaults write com.apple.dock wvous-bl-modifier -int 0

###############################################################################
# Trackpad, mouse, keyboard, Bluetooth accessories, and input                 #
###############################################################################

echo ""
echo "› Trackpad, mouse, keyboard, Bluetooth accessories, and input:"

echo "  › Trackpad: enable tap to click for this user and for the login screen"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Trackpad: map bottom right corner to right-click
# defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
# defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
# defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
# defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true

echo "  › Disable \`natural\` (Lion-style) scrolling"
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

echo "  › Increase sound quality for Bluetooth headphones/headsets"
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

echo "  › Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# echo "  › Use scroll gesture with the Ctrl (^) modifier key to zoom"
# defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
# defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144

# echo "  › Follow the keyboard focus while zoomed in"
# defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true

echo "  › Enable press-and-hold for keys instead of key repeat"
# Default value		: true
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool true

echo "  › Set a blazingly fast keyboard repeat rate"
# As done via		: System Preferences > Keyboard > Key Repeat
# Possible values	: 120, 90, 60, 30, 12, 6, 2 (lower values are faster)
defaults write NSGlobalDomain KeyRepeat -int 2

echo "  › Set short delay until repeat"
# As done via		: System Preferences > Keyboard > Delay Until Repeat
# Possible values	: 120, 94, 68, 35, 25, 15 (lower values are shorter)
defaults write NSGlobalDomain InitialKeyRepeat -int 35

echo "  › Set preferred languages to English and Vietnamese"
# As done via		: System Preferences > Language & Region > Preferred languages
defaults write NSGlobalDomain AppleLanguages -array "en" "vi"

echo "  › Set locale to US and currency to USD"
# As done via		: System Preferences > Language & Region > Advanced...
# Possible values	: en_GB@currency=GBP, vi_VN@currency=VND
defaults write NSGlobalDomain AppleLocale -string "en_US@currency=USD"

echo "  › Set measurement units to Centimeters"
# Possible values	: Centimeters, Inches
# As done via		: System Preferences > Language & Region > Advanced...
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"

echo "  › Set temperature unit to Celsius"
# As done via		: System Preferences > Language & Region > Temperature
# Possible values	: Celsius, Fahrenheit
defaults write NSGlobalDomain AppleTemperatureUnit -string "Celsius"

echo "  › Enable metric units"
# As done via		: System Preferences > Language & Region > Advanced...
defaults write NSGlobalDomain AppleMetricUnits -bool true

echo "  › Show language menu in the top right corner of the boot screen"
# As done via		: System Preferences > Users & Groups > Login Options > Show Input menu in login window
sudo defaults write /Library/Preferences/com.apple.loginwindow showInputMenu -bool true

echo "  › Set the timezone to Asia/Ho_Chi_Minh"
# As done via		: System Preferences > Date & Time > Time Zone
# Possible value	: See `sudo systemsetup -listtimezones` for other values
sudo systemsetup -settimezone "Asia/Ho_Chi_Minh" > /dev/null

# echo "  › Stop iTunes from responding to the keyboard media keys"
# launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist 2> /dev/null

###############################################################################
# Screen                                                                      #
###############################################################################

echo ""
echo "› Screen:"

echo "  › Require password immediately after sleep or screen saver begins"
# As done via		: System Preferences > Security & Privacy > Require password
defaults write com.apple.screensaver askForPassword -bool true
defaults write com.apple.screensaver askForPasswordDelay -int 0

echo "  › Save screenshots to the Desktop"
defaults write com.apple.screencapture location -string "${HOME}/Desktop"

echo "  › Save screenshots in PNG format"
# Possible values	: PNG, BMP, GIF, JPG, PDF, TIFF
defaults write com.apple.screencapture type -string "png"

echo "  › Disable shadow in screenshots"
# Default value		: false
defaults write com.apple.screencapture disable-shadow -bool true

echo "  › Enable subpixel font rendering on non-Apple LCDs"
# Reference			: https://github.com/kevinSuttle/macOS-Defaults/issues/17#issuecomment-266633501
defaults write NSGlobalDomain AppleFontSmoothing -int 1

echo "  › Enable HiDPI display modes (requires restart)"
sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

###############################################################################
# Finder                                                                      #
###############################################################################

echo ""
echo "› Finder:"

# echo "  › Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons"
# defaults write com.apple.finder QuitMenuItem -bool true

# echo "  › Finder: disable window animations and Get Info animations"
# defaults write com.apple.finder DisableAllAnimations -bool true

echo "  › Hide icons for hard drives, servers, and removable media on the desktop"
# As done via		: Finder Preferences > General > Show these items on the desktop
# Note				: For other paths, use `PfLo` and `file:///full/path/here/`
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false

echo "  › Set ${HOME} as the default location for new Finder windows"
# As done via		: Finder Preferences > General > New Finder windows show
# Note				: For other paths, use `PfLo` and `file:///full/path/here/`
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

echo "  › Finder: hide hidden files by default"
defaults write com.apple.finder AppleShowAllFiles -bool false

echo "  › Finder: hide filename extensions if possible"
# As done via		: Finder Preferences > Advanced > Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool false

echo "  › Finder: disable the warning when changing a file extension"
# As done via		: Finder Preferences > Advanced > Show warning before changing an extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

echo "  › Finder: Enable the warning before emptying the Trash"
# As done via		: Finder Preferences > Advanced > Show warning before emptying the Trash
defaults delete com.apple.finder WarnOnEmptyTrash 2> /dev/null

echo "  › Finder: Keep folders on top when sorting by name"
# As done via		: Finder Preferences > Advanced > Keep folders on top
defaults write com.apple.finder _FXSortFoldersFirst -bool true

echo "  › Finder: when performing a search, search the current folder by default"
# As done via		: Finder Preferences > Advanced > When performing a search
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

echo "  › Finder: show status bar"
# As done via		: Finder > View > Show Status Bar
defaults write com.apple.finder ShowStatusBar -bool true

echo "  › Finder: show path bar"
# As done via		: Finder > View > Show Path Bar
defaults write com.apple.finder ShowPathbar -bool true

echo "  › Finder: show SideBar"
# As done via		: Finder > View > Show Sidebar
defaults write com.apple.finder ShowSidebar -bool true

echo "  › Finder: show Preview pane"
# As done via		: Finder > View > Show Preview
defaults write com.apple.finder ShowPreviewPane -bool true

# echo "  › Finder: display full POSIX path as Finder window title"
# defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# echo "  › Finder: enable spring loading for directories"
# defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# echo "  › Finder: remove the spring loading delay for directories"
# defaults write NSGlobalDomain com.apple.springing.delay -float 0

echo "  › Avoid creating .DS_Store files on network or USB volumes"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

echo "  › Disable disk image verification"
defaults write com.apple.frameworks.diskimages skip-verify -bool true
defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

echo "  › Automatically open a new Finder window when a volume is mounted"
# defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
# defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
# defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

echo "  › Show item info near icons on the desktop and in other icon views"
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist

# echo "  › Show item info to the right of the icons on the desktop"
# /usr/libexec/PlistBuddy -c "Set DesktopViewSettings:IconViewSettings:labelOnBottom false" ~/Library/Preferences/com.apple.finder.plist

echo "  › Enable snap-to-grid for icons on the desktop and in other icon views"
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist

echo "  › Increase grid spacing for icons on the desktop and in other icon views"
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 80" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 80" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 80" ~/Library/Preferences/com.apple.finder.plist

echo "  › Increase the size of icons on the desktop and in other icon views"
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 64" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 64" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 64" ~/Library/Preferences/com.apple.finder.plist

echo "  › Finder: use column view in all Finder windows by default"
# Possible values	: Four-letter codes for the other view modes: `Nlsv`, `icnv`, `clmv`, `glyv`
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"

# echo "  › Enable AirDrop over Ethernet and on unsupported Macs running Lion"
# defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

# echo "  › Show the ~/Library folder"
# chflags nohidden ~/Library && xattr -d com.apple.FinderInfo ~/Library

# echo "  › Show the /Volumes folder"
# sudo chflags nohidden /Volumes

echo "  › FExpand the following File Info panes: `General`, `Open with`, and `Sharing & Permissions`"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
	General -bool true \
	OpenWith -bool true \
	Privileges -bool true

###############################################################################
# Safari & WebKit                                                             #
###############################################################################

echo ""
echo "› Safari & WebKit:"

# Privacy: don’t send search queries to Apple
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Press Tab to highlight each item on a web page
defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks -bool true

# Show the full URL in the address bar (note: this still hides the scheme)
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true

# Set Safari’s home page to `about:blank` for faster loading
# defaults write com.apple.Safari HomePage -string "about:blank"

# Prevent Safari from opening ‘safe’ files automatically after downloading
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

# Allow hitting the Backspace key to go to the previous page in history
# defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled -bool true

# Hide Safari’s bookmarks bar by default
defaults write com.apple.Safari ShowFavoritesBar -bool false

# Hide Safari’s sidebar in Top Sites
defaults write com.apple.Safari ShowSidebarInTopSites -bool false

# Disable Safari’s thumbnail cache for History and Top Sites
# defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2

# Enable Safari’s debug menu
defaults write com.apple.Safari IncludeInternalDebugMenu -bool true

# Make Safari’s search banners default to Contains instead of Starts With
defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false

# Remove useless icons from Safari’s bookmarks bar
defaults write com.apple.Safari ProxiesInBookmarksBar "()"

# Enable the Develop menu and the Web Inspector in Safari
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true

# Add a context menu item for showing the Web Inspector in web views
defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

# Enable continuous spellchecking
defaults write com.apple.Safari WebContinuousSpellCheckingEnabled -bool true
# Disable auto-correct
defaults write com.apple.Safari WebAutomaticSpellingCorrectionEnabled -bool false

# Disable AutoFill
# defaults write com.apple.Safari AutoFillFromAddressBook -bool false
# defaults write com.apple.Safari AutoFillPasswords -bool false
# defaults write com.apple.Safari AutoFillCreditCardData -bool false
# defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false

# Warn about fraudulent websites
defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true

# Disable plug-ins
# defaults write com.apple.Safari WebKitPluginsEnabled -bool false
# defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2PluginsEnabled -bool false

# Disable Java
# defaults write com.apple.Safari WebKitJavaEnabled -bool false
# defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled -bool false
# defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles -bool false

# Block pop-up windows
defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false

# Disable auto-playing video
#defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
#defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
#defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
#defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false

# Enable “Do Not Track”
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true

# Update extensions automatically
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true

###############################################################################
# Mail                                                                        #
###############################################################################

echo ""
echo "› Mail:"

# Disable send and reply animations in Mail.app
# defaults write com.apple.mail DisableReplyAnimations -bool true
# defaults write com.apple.mail DisableSendAnimations -bool true

# Copy email addresses as `foo@example.com` instead of `Foo Bar <foo@example.com>` in Mail.app
defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

# Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app
defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@\U21a9"

# Display emails in threaded mode, sorted by date (oldest at the top)
defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"

# Disable inline attachments (just show the icons)
defaults write com.apple.mail DisableInlineAttachmentViewing -bool true

# Disable automatic spell checking
defaults write com.apple.mail SpellCheckingBehavior -string "NoSpellCheckingEnabled"

###############################################################################
# Spotlight                                                                   #
###############################################################################

# Hide Spotlight tray-icon (and subsequent helper)
#sudo chmod 600 /System/Library/CoreServices/Search.bundle/Contents/MacOS/Search
# Disable Spotlight indexing for any volume that gets mounted and has not yet
# been indexed before.
# Use `sudo mdutil -i off "/Volumes/foo"` to stop indexing any volume.
# sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes"
# Change indexing order and disable some search results
# Yosemite-specific search results (remove them if you are using macOS 10.9 or older):
# 	MENU_DEFINITION
# 	MENU_CONVERSION
# 	MENU_EXPRESSION
# 	MENU_SPOTLIGHT_SUGGESTIONS (send search queries to Apple)
# 	MENU_WEBSEARCH             (send search queries to Apple)
# 	MENU_OTHER
# defaults write com.apple.spotlight orderedItems -array \
# 	'{"enabled" = 1;"name" = "APPLICATIONS";}' \
# 	'{"enabled" = 1;"name" = "SYSTEM_PREFS";}' \
# 	'{"enabled" = 1;"name" = "DIRECTORIES";}' \
# 	'{"enabled" = 1;"name" = "PDF";}' \
# 	'{"enabled" = 1;"name" = "FONTS";}' \
# 	'{"enabled" = 0;"name" = "DOCUMENTS";}' \
# 	'{"enabled" = 0;"name" = "MESSAGES";}' \
# 	'{"enabled" = 0;"name" = "CONTACT";}' \
# 	'{"enabled" = 0;"name" = "EVENT_TODO";}' \
# 	'{"enabled" = 0;"name" = "IMAGES";}' \
# 	'{"enabled" = 0;"name" = "BOOKMARKS";}' \
# 	'{"enabled" = 0;"name" = "MUSIC";}' \
# 	'{"enabled" = 0;"name" = "MOVIES";}' \
# 	'{"enabled" = 0;"name" = "PRESENTATIONS";}' \
# 	'{"enabled" = 0;"name" = "SPREADSHEETS";}' \
# 	'{"enabled" = 0;"name" = "SOURCE";}' \
# 	'{"enabled" = 0;"name" = "MENU_DEFINITION";}' \
# 	'{"enabled" = 0;"name" = "MENU_OTHER";}' \
# 	'{"enabled" = 0;"name" = "MENU_CONVERSION";}' \
# 	'{"enabled" = 0;"name" = "MENU_EXPRESSION";}' \
# 	'{"enabled" = 0;"name" = "MENU_WEBSEARCH";}' \
# 	'{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}'
# Load new settings before rebuilding the index
# killall mds > /dev/null 2>&1
# Make sure indexing is enabled for the main volume
# sudo mdutil -i on / > /dev/null
# Rebuild the index from scratch
# sudo mdutil -E / > /dev/null

###############################################################################
# Time Machine                                                                #
###############################################################################

echo ""
echo "› Time Machine:"

echo "  › Prevent Time Machine from prompting to use new hard drives as backup volume"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

echo "  › Disable local Time Machine backups"
hash tmutil &> /dev/null && sudo tmutil disable

###############################################################################
# Activity Monitor                                                            #
###############################################################################

echo ""
echo "› Activity Monitor:"

# Show the main window when launching Activity Monitor
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true

# Visualize CPU usage in the Activity Monitor Dock icon
defaults write com.apple.ActivityMonitor IconType -int 5

# Show all processes in Activity Monitor
defaults write com.apple.ActivityMonitor ShowCategory -int 0

# Sort Activity Monitor results by CPU usage
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
defaults write com.apple.ActivityMonitor SortDirection -int 0

###############################################################################
# Address Book, Dashboard, TextEdit, and Disk Utility                   #
###############################################################################

echo ""
echo "› Address Book, Dashboard, TextEdit, and Disk Utility:"

# Enable the debug menu in Address Book
# defaults write com.apple.addressbook ABShowDebugMenu -bool true

# Enable Dashboard dev mode (allows keeping widgets on the desktop)
# defaults write com.apple.dashboard devmode -bool true

# Use plain text mode for new TextEdit documents
defaults write com.apple.TextEdit RichText -int 0
# Open and save files as UTF-8 in TextEdit
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

# Enable the debug menu in Disk Utility
# defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
# defaults write com.apple.DiskUtility advanced-image-options -bool true

# Auto-play videos when opened with QuickTime Player
defaults write com.apple.QuickTimePlayerX MGPlayMovieOnOpen -bool true

###############################################################################
# Mac App Store                                                               #
###############################################################################

# Enable the WebKit Developer Tools in the Mac App Store
# defaults write com.apple.appstore WebKitDeveloperExtras -bool true

# Enable Debug Menu in the Mac App Store
# defaults write com.apple.appstore ShowDebugMenu -bool true

# Enable the automatic update check
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

# Check for software updates daily, not just once per week
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

# Download newly available updates in background
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1

# Install System data files & security updates
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1

# Automatically download apps purchased on other Macs
# defaults write com.apple.SoftwareUpdate ConfigDataInstall -int 1

# Turn on app auto-update
# defaults write com.apple.commerce AutoUpdate -bool true

# Allow the App Store to reboot machine on macOS updates
# defaults write com.apple.commerce AutoUpdateRestartRequired -bool true

###############################################################################
# Photos                                                                      #
###############################################################################

# Prevent Photos from opening automatically when devices are plugged in
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

###############################################################################
# Messages                                                                    #
###############################################################################

# Disable automatic emoji substitution (i.e. use plain text smileys)
# defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false

# Disable smart quotes as it’s annoying for messages that contain code
# defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false

# Disable continuous spell checking
defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false

###############################################################################
# Kill affected applications                                                  #
###############################################################################

for app in "Activity Monitor" \
	"Address Book" \
	"Calendar" \
	"cfprefsd" \
	"Contacts" \
	"Dock" \
	"Finder" \
	"Mail" \
	"Messages" \
	"Photos" \
	"Safari" \
	"SystemUIServer" \
	"Terminal"; do
	killall "${app}" &> /dev/null
done
echo "Done. Note that some of these changes require a logout/restart to take effect."
