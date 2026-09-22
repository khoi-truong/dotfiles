#!/usr/bin/env zsh
# shellcheck disable=SC1071  # shellcheck has no zsh mode; zsh -n is the check
# ai/claude/providers.zsh — run Claude Code against Anthropic-compatible
# providers, one process at a time. The Pro login is never touched.
# Sourced from ai/aliases.zsh. To add a provider, add a `[provider.<name>]`
# entry to ai/providers.toml: the cc_provider calls are generated from it into
# the cache this file sources at the bottom. Each generates claude-<name> and,
# with a `short`, <short>/<short>c/<short>r.

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

# --- the cache ---------------------------------------------------------------
#
# No cc_provider call is written here. Providers are `[provider.<name>]`
# entries in ai/providers.toml — one definition, read by this cache, by
# ai/herdr/team.toml's `credential` fields and by `team.sh config` — and the
# calls are generated from it: reading TOML at every shell start is out of the
# question, so the shell compares two mtimes instead and pays the 100 ms only
# in the shell that follows an edit.
#
# A start costs three builtins. A start that regenerates forks python3, writes
# a temp file, checks it with `zsh -n` and `mv`s it into place, because a wave
# of team.sh's `zsh -ic` probes can arrive at once and a reader must never see
# half a file. Failure is not fatal and never silent: one warning, and the
# previous cache stays exactly as it was, so a registry nobody can parse costs
# a line on stderr rather than the `ccd` command. With no cache at all the
# shell still starts, without the provider launchers.
#
# One warning, not one per start: a failure leaves a stamp beside the cache, and
# the next start retries only once one of the two files it reads has moved past
# it. A registry that will not parse therefore costs a python3 per edit rather
# than per shell. The interpreter is the python3 PATH holds — mise puts it there,
# and it is the one herdr_team's reader runs — at 3.11 or newer, because the
# reader is stdlib `tomllib` and an older python3 cannot open the registry at
# all. There is no fallback to /usr/bin/python3: on this machine that is 3.9, a
# shim under the Command Line Tools whose only job is to say so, and picking it
# would mean warning at every start rather than building the cache.

typeset -g _cc_cache_dir=${XDG_CACHE_HOME:-${HOME}/.cache}/dotfiles
typeset -g _cc_cache=${_cc_cache_dir}/providers.zsh
# Beside the cache, written when a regeneration fails and removed when one
# works. `: >file` sets its mtime with no subprocess.
typeset -g _cc_stamp=${_cc_cache}.failed

# _cc_python_path — the interpreter to generate with, on stdout, or non-zero.
#
# Called only when a regeneration is due, which is what lets the version check
# be a fork: `$commands` is the hash zsh keeps of PATH, so finding the python3
# costs a lookup, and asking its version costs one `python3 -c` in the shell
# that follows an edit to ai/providers.toml and nothing in the shells that do
# not. The test is on `sys.version_info`, not a `-V` string, because a shim's
# output is not a promise; 3.11 is the floor because the registry is read with
# stdlib `tomllib`.
function _cc_python_path {
  local py=${commands[python3]}
  [[ -n $py ]] || return 1
  "$py" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null || return 1
  print -r -- "$py"
}

# _cc_registry_newer <file> — has the registry or the generator moved past it?
#
# Naming the two files rather than the directory around them is the point: a
# pull rewrites a file in place and leaves the directory's own mtime alone, so a
# directory test would miss exactly the change this is for.
function _cc_registry_newer {
  [[ ${DOTFILES}/ai/providers.toml -nt $1 ]] ||
    [[ ${DOTFILES}/ai/herdr/lib/providers.py -nt $1 ]]
}

# _cc_cache_refresh — rewrite the cache from the registry, atomically.
function _cc_cache_refresh {
  local tmp=${_cc_cache}.$$ line py=""
  [[ -d $_cc_cache_dir ]] || mkdir -p "$_cc_cache_dir" 2>/dev/null || return 1
  if ! py="$(_cc_python_path)"; then
    print -u2 "cc_provider: no python3 >= 3.11 to generate ${_cc_cache} from ai/providers.toml"
    print -u2 "             — mise provides one; the launchers are left as they were"
    : >"$_cc_stamp"
    return 1
  fi
  # The temp file this shell may die holding: INT is the one signal a shell sits
  # in the middle of a write under, and the trap is cleared at every exit below.
  trap 'rm -f "$tmp" "${tmp}.err"' INT
  # stderr goes to its own file, not into the cache: a python3 warning on the way
  # to a perfectly good cache would be sourced as zsh by the next line.
  if ! PYTHONPATH=${DOTFILES}/ai/herdr/lib "$py" -m providers zsh \
      >"$tmp" 2>"${tmp}.err"; then
    IFS= read -r line <"${tmp}.err"
    print -u2 "cc_provider: cannot regenerate ${_cc_cache}: ${line:-no output}"
    print -u2 "             keeping the last good cache; fix ai/providers.toml"
    print -u2 "             and start a new shell"
    rm -f "$tmp" "${tmp}.err"
    : >"$_cc_stamp"
    trap - INT
    return 1
  fi
  if ! zsh -n "$tmp" 2>/dev/null; then
    print -u2 "cc_provider: generated cache is not valid zsh — keeping the last good one"
    rm -f "$tmp" "${tmp}.err"
    : >"$_cc_stamp"
    trap - INT
    return 1
  fi
  mv -f "$tmp" "$_cc_cache"
  rm -f "${tmp}.err" "$_cc_stamp"
  trap - INT
}

if [[ ! -r $_cc_cache ]] || _cc_registry_newer "$_cc_cache"; then
  # A stamp older than both files says the last attempt failed on exactly what
  # is on disk now, and that its warning has been printed. Anything else — no
  # stamp, or an edit since — is worth one more try.
  if [[ -e $_cc_stamp ]] && ! _cc_registry_newer "$_cc_stamp"; then
    :
  else
    _cc_cache_refresh
  fi
fi
[[ -r $_cc_cache ]] && source "$_cc_cache"
