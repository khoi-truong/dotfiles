# zsh/config.zsh — shell options, history, and general environment.

# --- editor ----------------------------------------------------------------
export EDITOR='nvim'
export VISUAL="$EDITOR"

# --- locale ----------------------------------------------------------------
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# --- pager / man -----------------------------------------------------------
# Highlight section titles in manual pages (bold -> yellow).
export LESS_TERMCAP_md=$'\e[1;33m'
export LESS_TERMCAP_me=$'\e[0m'
# Don't clear the screen after quitting a manual page.
export MANPAGER='less -X'

# --- gpg -------------------------------------------------------------------
# Required for pinentry on a Homebrew gpg. $TTY is a zsh builtin, so this
# avoids forking `tty` on every shell start.
export GPG_TTY="$TTY"

# --- misc ------------------------------------------------------------------
# Hide the "default interactive shell is now zsh" warning in bash subshells.
export BASH_SILENCE_DEPRECATION_WARNING=1

# --- history ---------------------------------------------------------------
# HISTFILE is set in zshrc (zsh/local/history).
export HISTSIZE=65536
export SAVEHIST=$HISTSIZE

setopt EXTENDED_HISTORY       # record timestamp + duration
setopt INC_APPEND_HISTORY     # write as commands are entered, not on exit
setopt HIST_IGNORE_DUPS       # don't record an immediately repeated command
setopt HIST_IGNORE_ALL_DUPS   # drop older duplicates of a re-run command
setopt HIST_IGNORE_SPACE      # leading space keeps a command out of history
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY            # expand !! into the buffer instead of running it

# --- directories -----------------------------------------------------------
setopt AUTO_CD                # `..` / a bare directory name changes into it
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

# --- Claude Code session hygiene ------------------------------------------
# Strip leaked Claude Code session vars from interactive shells. When an app
# (iTerm2, VS Code, tmux) is launched from inside a Claude Code session,
# CLAUDECODE=1 etc. get baked into every child shell, so a fresh `claude` in a
# new tab thinks it's a nested child and corrupts its startup banner. Claude's
# own Bash-tool shells are non-interactive, so this leaves those untouched.
if [[ -o interactive ]]; then
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION AI_AGENT \
        CLAUDE_CODE_SESSION_ID CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_EXECPATH \
        CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN
fi
