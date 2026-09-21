#!/usr/bin/env bash
#
# brew/Brewfile is read by `brew bundle`, and by `brew bundle cleanup` — which
# uninstalls everything the file does not list. Two classes of mistake in it go
# unreported until one of those runs:
#
#   * a line that is not an entry this check recognises — `brew bundle`
#     evaluates this file as Ruby, so a stray word, an unclosed quote or an
#     unclosed brace is a load error that stops the whole run, not a line brew
#     quietly steps over;
#   * the same (type, name) twice is harmless to install, but the file stops
#     reading as one entry per thing, and a later edit to one copy looks like
#     it took effect when the other is what runs.
#
# Parsing follows what Ruby accepts, because Ruby is what reads this file: an
# entry may be indented; the name may be quoted either way and may be written
# `brew("name")`; arguments after the name are positional or `, key: value`; an
# option's value is a bare token, a quoted string, a `{…}` hash or a `[…]`
# array; one trailing `if`/`unless` modifier is allowed; a trailing `#` is a
# comment. `cask_args` and the `if`/`else`/`end` conditionals are directives
# rather than entries, and are accepted as such.
#
# The check is deliberately narrower than Ruby: a form it does not know is
# reported even though brew might accept it. That is the safe direction — a
# false report costs one edit, while a missed malformed line costs a `brew
# bundle` run and a missed removal costs whatever `brew bundle cleanup`
# uninstalls.
#
# Comment and blank lines are skipped: this file documents itself with them,
# and deliberately keeps entries commented out (see the casks and mas blocks).
#
# Run by .github/workflows/lint.yml and scripts/ci/lint-local.sh; both files
# name the other, so a change here lands in both. lint.yml's removed-entry step
# parses the file with the same entry types, the same optional parens and the
# same two quote styles — so keep the two in step.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BREWFILE=brew/Brewfile

# A name in either quote style, quotes included. At least one character: the
# empty string names nothing brew could install.
QUOTED_RE="\"[^\"]+\"|'[^']+'"

# Every type `brew bundle` has a subcommand for, which is what makes one of
# these lines an entry rather than a bare Ruby method call.
TYPES_RE='tap|brew|cask|mas|vscode|whalebrew|go|cargo|uv'

# One value: a braced hash such as `{ force: true }`, a bracketed array such as
# `["a", "b"]`, a quoted string, or a single bare token. A bare token stops at
# whitespace and at every character that could open a structure, so `id: 1 2 3`
# consumes only the `1` and the rest of the line is then a load error — which is
# what Ruby does with it too. Excluding `#` is what keeps a trailing comment
# from being swallowed into an option's value; excluding the four bracket
# characters is what stops `args: ["a", "b"` from being read as the bare token
# `[` followed by two quoted strings, which is how an unclosed array slipped
# through the first version of this pattern.
VALUE_RE="\{[^}]*\}|\[[^]]*\]|${QUOTED_RE}|[^][:space:],{}#\"'[]+"

# Everything after the name: zero or more arguments, each a `, key: value`
# option or a positional value. The two are one alternation because brew's DSL
# takes them in any order and mix — `tap "user/repo", "https://…git"` ends in a
# positional.
ARGS_RE="([[:space:]]*,[[:space:]]*([[:alpha:]_][[:alnum:]_]*[[:space:]]*:[[:space:]]*(${VALUE_RE})*|${VALUE_RE}))*"

# `brew "foo" if OS.mac?` — a Ruby modifier on the call, not an argument.
MODIFIER_RE='[[:space:]]+(if|unless)[[:space:]]+[^[:space:]]+'

# The name, bare or in parens. `[(]`/`[)]` rather than `\(`: a backslash before
# a paren is undefined in ERE, while a one-character bracket expression is a
# literal everywhere this runs. Both parens are required or neither, so
# `brew("foo"` is not quietly accepted as valid Ruby.
NAME_RE="[(][[:space:]]*(${QUOTED_RE})[[:space:]]*[)]|${QUOTED_RE}"

# Anchored at both ends, unlike the name-only pattern this replaced: `brew "foo"
# junk` is a Ruby SyntaxError, and only an anchored pattern rejects it. Ruby
# also rejects a bare `brew zsh`, which the unanchored one accepted.
ENTRY_RE="^[[:space:]]*(${TYPES_RE})[[:space:]]*(${NAME_RE})(${ARGS_RE})?(${MODIFIER_RE})?([[:space:]]*#.*)?[[:space:]]*$"

# Directives in that same Ruby: they name nothing that installs, so they are
# neither entries nor malformed lines. `if`/`unless`/`elsif`/`cask_args` are
# matched on their first word alone, because the rest of the line is a Ruby
# expression this check has no business parsing. `end` and `else` take nothing,
# so they are anchored — `end garbage` is a syntax error, not a directive.
DIRECTIVE_RE="^[[:space:]]*(cask_args|if|elsif|unless)([[:space:]]|\$)|^[[:space:]]*(end|else)[[:space:]]*(#.*)?\$"

# "type name" per entry, quotes removed and any parens dropped. One `s///p` per
# quote style; a line can match at most one of them.
PAIR_SED=(
  -e "s/^[[:space:]]*(${TYPES_RE})[[:space:]]*[(]?\"([^\"]+)\"[)]?.*/\1 \2/p"
  -e "s/^[[:space:]]*(${TYPES_RE})[[:space:]]*[(]?'([^']+)'[)]?.*/\1 \2/p"
)

main() {
  local -a malformed=() pairs=() duplicates=()
  local line pair
  local lineno=0

  if [ ! -f "$BREWFILE" ]; then
    printf 'check-brewfile: %s is missing — run this from the repository root\n' \
      "$BREWFILE" >&2
    return 1
  fi

  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "${line#"${line%%[![:space:]]*}"}" in
      '' | '#'*) continue ;;
    esac

    if printf '%s\n' "$line" | grep -qE "$DIRECTIVE_RE"; then
      continue
    fi

    if ! printf '%s\n' "$line" | grep -qE "$ENTRY_RE"; then
      malformed+=("${lineno}: ${line}")
      continue
    fi

    pair="$(printf '%s\n' "$line" | sed -nE "${PAIR_SED[@]}")"
    if [ -n "$pair" ]; then
      pairs+=("$pair")
    fi
  done <"$BREWFILE"

  if [ "${#pairs[@]}" -gt 0 ]; then
    while IFS= read -r pair; do
      duplicates+=("$pair")
    done < <(printf '%s\n' "${pairs[@]}" | sort | uniq -d)
  fi

  if [ "${#malformed[@]}" -ne 0 ]; then
    printf 'These lines are not an entry this check recognises:\n' >&2
    printf '  %s\n' "${malformed[@]}" >&2
    printf 'An entry is a known type, a quoted name it may put in parens, and\n' >&2
    printf 'then nothing but arguments, a modifier or a comment — see this file.\n' >&2
  fi
  if [ "${#duplicates[@]}" -ne 0 ]; then
    printf 'These (type, name) pairs appear more than once:\n' >&2
    printf '  %s\n' "${duplicates[@]}" >&2
  fi
  if [ "${#malformed[@]}" -ne 0 ] || [ "${#duplicates[@]}" -ne 0 ]; then
    return 1
  fi

  printf 'check-brewfile: %d entries, all well-formed and unique\n' "${#pairs[@]}"
}

main "$@"
