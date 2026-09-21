#!/usr/bin/env bash
#
# brew/Brewfile is read by `brew bundle`, and by `brew bundle cleanup` — which
# uninstalls everything the file does not list. Two classes of mistake in it go
# unreported until one of those runs:
#
#   * a line that is not a `<type> "name"` entry — `brew bundle` evaluates this
#     file as Ruby, so a stray word or an unclosed quote is a load error that
#     stops the whole run, not a line brew quietly steps over;
#   * the same (type, name) twice is harmless to install, but the file stops
#     reading as one entry per thing, and a later edit to one copy looks like
#     it took effect when the other is what runs.
#
# Parsing follows what Ruby accepts, because Ruby is what reads this file: an
# entry may be indented, the name may be single- or double-quoted, options
# after the name are `, key: value` (the mas block carries `id:`), and a
# trailing `#` is a comment. `cask_args` and the `if`/`else`/`end` conditionals
# are directives rather than entries, and are accepted as such.
#
# Comment and blank lines are skipped: this file documents itself with them,
# and deliberately keeps entries commented out (see the casks and mas blocks).
#
# Run by .github/workflows/lint.yml and scripts/ci/lint-local.sh; both files
# name the other, so a change here lands in both. lint.yml's removed-entry step
# parses the file with the same two rules — indentation and either quote style
# — so keep the two in step.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BREWFILE=brew/Brewfile

# A name in either quote style, quotes included.
QUOTED_RE="\"[^\"]*\"|'[^']*'"

# Everything that may follow the name: zero or more `, key: value` options and
# at most one trailing `#` comment. A value is a braced block such as
# `args: { force: true }`, a quoted string, or a bare run containing no comma,
# brace or hash — excluding `#` is what keeps a trailing comment from being
# swallowed into an option's value.
OPTION_RE="[[:space:]]*,[[:space:]]*[[:alpha:]_][[:alnum:]_]*[[:space:]]*:[[:space:]]*(\{[^}]*\}|${QUOTED_RE}|[^,{}#])*"

# Anchored at both ends, unlike the name-only pattern this replaced: `brew "foo"
# junk` is a Ruby SyntaxError, and only an anchored pattern rejects it. Ruby
# also rejects a bare `brew zsh`, which the unanchored one accepted.
ENTRY_RE="^[[:space:]]*(tap|brew|cask|mas|vscode|whalebrew)[[:space:]]+(${QUOTED_RE})(${OPTION_RE})*([[:space:]]*#.*)?[[:space:]]*$"

# Directives in that same Ruby: they name nothing that installs, so they are
# neither entries nor malformed lines.
DIRECTIVE_RE="^[[:space:]]*(cask_args|if|elsif|else|unless|end)([[:space:]]|$)"

# "type name" per entry, quotes removed. Two `s///p` expressions, one per quote
# style; a line can match at most one of them.
PAIR_SED=(
  -e "s/^[[:space:]]*(tap|brew|cask|mas|vscode|whalebrew)[[:space:]]+\"([^\"]*)\".*/\1 \2/p"
  -e "s/^[[:space:]]*(tap|brew|cask|mas|vscode|whalebrew)[[:space:]]+'([^']*)'.*/\1 \2/p"
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
    printf 'These lines are not a <type> "name" entry, so brew bundle cannot\n' >&2
    printf 'load the file — it is evaluated as Ruby:\n' >&2
    printf '  %s\n' "${malformed[@]}" >&2
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
