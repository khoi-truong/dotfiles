# ai/aliases.zsh — AI CLI shortcuts. Sourced from zsh/zshrc.
#
# The `claude` wrapper function itself lives in zsh/functions.zsh.

# Claude Code
alias cc="claude"
alias ccc="claude --continue"
alias ccr="claude --resume"

# GitHub Copilot CLI (gh extension)
alias '??'="gh copilot suggest -t shell"
alias 'git?'="gh copilot suggest -t git"
alias 'gh?'="gh copilot suggest -t gh"
alias explain="gh copilot explain"

# Machine-local secrets (ANTHROPIC_API_KEY, ...). Gitignored.
[[ -r ${DOTFILES}/ai/env.local.zsh ]] && source "${DOTFILES}/ai/env.local.zsh"
