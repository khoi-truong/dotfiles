# Increase Bash history size. Allow 2^16 entries; the default is 500.
export HISTSIZE='65536';
export HISTFILESIZE="${HISTSIZE}";

# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth';

# Set format for history file
export HISTTIMEFORMAT="%F %T "

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"

setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY