#!/usr/bin/env zsh
# shellcheck disable=SC1071  # shellcheck has no zsh mode; zsh -n is the check
# ai/aliases.zsh — AI CLI shortcuts. Sourced from zsh/zshrc.
#
# The `claude` wrapper function itself lives in zsh/functions.zsh.

# Claude Code
alias cc="claude"
alias ccc="claude --continue"
alias ccr="claude --resume"

# pi (DeepSeek)
alias pic="pi --continue"
alias pir="pi --resume"
# pi-mcp-adapter: read only ~/.pi/agent/mcp.json, never a project .mcp.json.
export PI_MCP_CONFIG_MODE=exclusive

# GitHub Copilot CLI (gh extension)
alias '??'="gh copilot suggest -t shell"
alias 'git?'="gh copilot suggest -t git"
alias 'gh?'="gh copilot suggest -t gh"
alias explain="gh copilot explain"

# Machine-local secrets (ANTHROPIC_API_KEY, ...). Gitignored.
[[ -r ${DOTFILES}/ai/env.local.zsh ]] && source "${DOTFILES}/ai/env.local.zsh"
