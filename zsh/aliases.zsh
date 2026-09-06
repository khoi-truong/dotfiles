# zsh/aliases.zsh — portable aliases. macOS-only ones live in aliases.macos.zsh.
# Sourced AFTER the plugin bundle so these win over plugin-provided aliases.

# --- navigation ------------------------------------------------------------
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias -- -="cd -"

alias dl="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias dot="cd ${DOTFILES}"

# --- ls --------------------------------------------------------------------
# Detect which `ls` flavour is in use.
if ls --color >/dev/null 2>&1; then # GNU coreutils
  colorflag="--color"
  export LS_COLORS='no=00:fi=00:di=01;31:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.zip=01;31:*.gz=01;31:*.bz2=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.png=01;35:*.mov=01;35:*.mp3=01;35:'
else # BSD / macOS
  colorflag="-G"
  export LSCOLORS='BxBxhxDxfxhxhxhxhxcxcx'
fi

alias ls="command ls ${colorflag}"
alias l="ls -lF"
alias la="ls -lAF"
alias lsd="ls -lF | grep --color=never '^d'"
unset colorflag

# --- grep ------------------------------------------------------------------
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# --- shortcuts -------------------------------------------------------------
alias g="git"
alias vim="nvim"          # muscle memory; only nvim is installed
alias sudo='sudo '        # trailing space lets the next word be alias-expanded
alias week='date +%V'
alias map="xargs -n1"     # e.g. find . -name .gitattributes | map dirname
alias reload="exec ${SHELL} -l"
alias path='echo -e ${PATH//:/\\n}'

# --- networking ------------------------------------------------------------
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# --- fallbacks for tools macOS lacks ---------------------------------------
command -v hd >/dev/null || alias hd="hexdump -C"
command -v md5sum >/dev/null || alias md5sum="md5"
command -v sha1sum >/dev/null || alias sha1sum="shasum"

# --- HTTP verbs (@janmoesen) ----------------------------------------------
if command -v lwp-request >/dev/null; then
  for method in GET HEAD POST PUT DELETE TRACE OPTIONS; do
    alias "${method}"="lwp-request -m '${method}'"
  done
  unset method
fi
