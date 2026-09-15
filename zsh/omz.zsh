# zsh/omz.zsh — oh-my-zsh settings. Must be sourced BEFORE the plugin bundle,
# since the omz lib/theme files read these at load time.
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Settings

# Informational: oh-my-zsh.sh is bypassed, so the theme actually loaded is the
# one listed in zsh.plugins.
ZSH_THEME="robbyrussell"

# Informational: oh-my-zsh.sh is bypassed, and zshrc runs compinit itself —
# `-C` (trust the dump) while it is fresh, `-u` (no insecure-directory
# prompt) when it rebuilds. Run `compaudit` if completions misbehave.
ZSH_DISABLE_COMPFIX="true"

# omz's own updater is unused: plugins come from antidote (`antidote update`).
DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="false"

# Command auto-correction off: it mis-fires on directory names that shadow a
# command ("correct 'nvim' to '.nvim'").
ENABLE_CORRECTION="false"

# Red dots while waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Don't mark untracked files as dirty — big speedup for the git prompt/status
# in large repos.
DISABLE_UNTRACKED_FILES_DIRTY="true"
