# Increase Bash history size. Allow 2^16 entries; the default is 500.
export HISTSIZE='65536';
export HISTFILESIZE="${HISTSIZE}";

# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

# Set format for history file
export HISTTIMEFORMAT="%F %T "

setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY