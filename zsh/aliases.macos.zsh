# zsh/aliases.macos.zsh — macOS-only aliases. Sourced from zshrc when
# $OSTYPE is darwin*. Most of these come from mathiasbynens/dotfiles.

# --- networking ------------------------------------------------------------
alias localip="ipconfig getifaddr en0"
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"
alias ifactive="ifconfig | pcregrep -M -o '^[^\t:]+:([^\n]|\n\t)*status: active'"

# Flush the Directory Service (DNS) cache.
alias flush="sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"

# Wi-Fi details. The old `airport` binary was removed in macOS 14.4+.
alias wifi="system_profiler SPAirPortDataType"

# --- clipboard -------------------------------------------------------------
# Trim trailing newlines and copy to the clipboard.
alias c="tr -d '\n' | pbcopy"

# --- cleanup ---------------------------------------------------------------
# Recursively delete .DS_Store files below the current directory.
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Remove duplicate entries from the "Open With" menu.
alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# Empty the Trash on all mounted volumes, clear Apple's system logs, and clear
# the download quarantine history. https://mths.be/bum
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes ~/.Trash /private/var/log/asl/*.asl; sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV* 'delete from LSQuarantineEvent'"

# --- plists ----------------------------------------------------------------
# For when `defaults` isn't enough.
alias plistbuddy="/usr/libexec/PlistBuddy"

# --- JavaScriptCore REPL ---------------------------------------------------
jscbin="/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Resources/jsc"
[ -e "${jscbin}" ] && alias jsc="${jscbin}"
unset jscbin
