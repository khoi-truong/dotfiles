#!/usr/bin/env zsh
# shellcheck disable=SC1071  # shellcheck has no zsh mode; zsh -n is the check
# ai/aliases.zsh — AI CLI shortcuts. Sourced from zsh/zshrc.
#
# The `claude` wrapper function itself lives in zsh/functions.zsh.

# Claude Code: cc/ccc/ccr (Pro) and the other-provider launchers.
[[ -r ${DOTFILES}/ai/claude/providers.zsh ]] && source "${DOTFILES}/ai/claude/providers.zsh"

# oh-my-pi (DeepSeek)
alias ompc="omp --continue"
alias ompr="omp --resume"

# GitHub Copilot CLI (gh extension)
alias '??'="gh copilot suggest -t shell"
alias 'git?'="gh copilot suggest -t git"
alias 'gh?'="gh copilot suggest -t gh"
alias explain="gh copilot explain"

# Machine-local secrets (ANTHROPIC_API_KEY, ...). Gitignored.
[[ -r ${DOTFILES}/ai/env.local.zsh ]] && source "${DOTFILES}/ai/env.local.zsh"
