#!/usr/bin/env zsh
# shellcheck disable=SC1071  # shellcheck has no zsh mode; zsh -n is the check
# ai/claude/providers.zsh — run Claude Code against Anthropic-compatible
# providers, one process at a time. The Pro login is never touched.
# Sourced from ai/aliases.zsh. To add a provider, add one cc_provider call at
# the bottom; it generates claude-<name> and, with short=, <short>/<short>c/<short>r.

typeset -gA _cc_prov                 # "<name>:<field>" -> value
typeset -ga _cc_prov_names
# Every variable a provider launch may set; cc clears all of them.
typeset -gaU _cc_prov_vars=(
  ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL
  CC_PROVIDER CC_PROVIDER_LABEL
)

# cc_provider <name> url=<base-url> key=<op://…|env:VAR> model=<id>
#             [small=<id>] [pro=<id>] [label=<text>] [short=<cmd>]
#             [op_account=<account>] [env.<VAR>=<value>]…
function cc_provider {
  local name=$1 kv field req short
  local -a cmds
  shift
  [[ $name =~ '^[a-z0-9-]+$' ]] || { print -u2 "cc_provider: bad name '$name'"; return 1 }
  for kv in "$@"; do
    field=${kv%%=*}
    [[ $kv == *=* && -n $field ]] || { print -u2 "cc_provider ${name}: bad field '$kv'"; return 1 }
    [[ $field == env.* ]] && _cc_prov_vars+=(${field#env.})
    _cc_prov[${name}:$field]=${kv#*=}
  done
  for req in url key model; do
    [[ -n ${_cc_prov[${name}:$req]} ]] || { print -u2 "cc_provider ${name}: missing $req="; return 1 }
  done
  short=${_cc_prov[${name}:short]}
  [[ -z $short || $short =~ '^[a-z0-9]+$' ]] || { print -u2 "cc_provider ${name}: bad short '$short'"; return 1 }
  _cc_prov_names=(${_cc_prov_names:#$name} $name)
  # An alias beats a function of the same name, even one defined later.
  cmds=(claude-$name)
  [[ -n $short ]] && cmds+=($short ${short}c ${short}r)
  unalias $cmds 2>/dev/null
  eval "function claude-$name { _cc_run $name '' \"\$@\" }"
  [[ -n $short ]] || return 0
  eval "function $short { _cc_run $name '' \"\$@\" }
function ${short}c { _cc_run $name --continue \"\$@\" }
function ${short}r { _cc_run $name --resume \"\$@\" }"
}

# _cc_run <name> <leading-claude-flag|''> [--pro] [claude args…]
function _cc_run {
  local name=$1 pre=$2 model small ref k var f
  shift 2
  model=${_cc_prov[${name}:model]}
  if [[ $1 == --pro ]]; then
    model=${_cc_prov[${name}:pro]}
    [[ -n $model ]] || { print -u2 "claude-${name}: no pro= model configured"; return 1 }
    shift
  fi
  small=${_cc_prov[${name}:small]:-${_cc_prov[${name}:model]}}
  ref=${_cc_prov[${name}:key]}
  case $ref in
    op://*) k="$(op read --account "${_cc_prov[${name}:op_account]:-my.1password.com}" "$ref")" || return ;;
    env:*)  var=${ref#env:}; k=${(P)var} ;;
    *)      print -u2 "claude-${name}: key= must be op://… or env:VAR"; return 1 ;;
  esac
  [[ -n $k ]] || { print -u2 "claude-${name}: empty API key"; return 1 }
  (
    unset $_cc_prov_vars
    export ANTHROPIC_BASE_URL=${_cc_prov[${name}:url]} ANTHROPIC_AUTH_TOKEN=$k \
      ANTHROPIC_MODEL=$model ANTHROPIC_DEFAULT_OPUS_MODEL=$model \
      ANTHROPIC_DEFAULT_SONNET_MODEL=$small ANTHROPIC_DEFAULT_HAIKU_MODEL=$small \
      CLAUDE_CODE_SUBAGENT_MODEL=$small CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      CC_PROVIDER=$name CC_PROVIDER_LABEL=${_cc_prov[${name}:label]:-${(U)name}}
    for f in ${(k)_cc_prov[(I)${name}:env.*]}; do
      export "${f#${name}:env.}=${_cc_prov[$f]}"
    done
    claude ${pre:+$pre} "$@"   # the stty-fixing wrapper in zsh/functions.zsh
  )
}

# Claude Code on the Pro subscription, whatever the environment says.
unalias cc 2>/dev/null   # the old `alias cc=claude` survives a re-source
function cc { ( unset $_cc_prov_vars; claude "$@" ) }
alias ccc="cc --continue"
alias ccr="cc --resume"

# List configured providers and their commands.
function cc-providers {
  local n
  for n in $_cc_prov_names; do
    printf '%-10s %-18s %s  model=%s%s\n' $n \
      "claude-$n${_cc_prov[${n}:short]:+ / ${_cc_prov[${n}:short]}}" \
      ${_cc_prov[${n}:url]} ${_cc_prov[${n}:model]} "${_cc_prov[${n}:pro]:+ pro=${_cc_prov[${n}:pro]}}"
  done
}

# --- providers ---------------------------------------------------------------

# DeepSeek: key shared with omp (ai/omp/models.yml). Every model id,
# Opus included, is served by Flash.
#
# `env:` rather than `op://`, because _cc_run resolves the key on every launch
# and an `op read` puts a biometric prompt in front of it. A human at a
# terminal can answer that; an agent pane ai/herdr/team.sh spawned cannot, so
# the prompt is indistinguishable from a hung spawn and the whole unattended
# workflow stops there. omp never had the problem — it keeps its copy of this
# key in ~/.omp/agent/agent.db, which is also why `omp` panes start and `ccd`
# panes did not.
#
# DEEPSEEK_API_KEY is the 1Password field label: ai/setup.sh dumps that item
# to ai/env.secrets.zsh as one export per field, under the label verbatim. The
# item is where the name is decided. 1Password stays the place the key is
# *kept*; this is only about how it is *read* at launch.
cc_provider deepseek \
  url=https://api.deepseek.com/anthropic \
  key=env:DEEPSEEK_API_KEY \
  model=deepseek-flash \
  label=DS \
  short=ccd
