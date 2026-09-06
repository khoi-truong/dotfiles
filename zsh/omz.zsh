# zsh/omz.zsh — oh-my-zsh settings. Must be sourced BEFORE the plugin bundle,
# since oh-my-zsh.sh reads these at load time.
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Settings

ZSH_THEME="robbyrussell"

# Skip the `compaudit` insecure-directory scan on every start. This is the
# single biggest oh-my-zsh startup cost; it makes omz use `compinit -C -d
# $ZSH_COMPDUMP`, i.e. trust the existing dump instead of re-scanning $fpath.
# Re-enable temporarily (or run `compaudit`) if completions misbehave.
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
