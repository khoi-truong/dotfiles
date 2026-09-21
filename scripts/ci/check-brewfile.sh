#!/usr/bin/env bash
#
# brew/Brewfile is read by `brew bundle`, and by `brew bundle cleanup` — which
# uninstalls everything the file does not list. Two classes of mistake in it go
# unreported until one of those runs:
#
#   * a line that is not `<type> "name"` — a stray word, an unclosed quote, a
#     tab where a space belongs — is skipped by `brew bundle` rather than
#     reported, so the entry quietly never installs;
#   * the same (type, name) twice is harmless to install, but the file stops
#     reading as one entry per thing, and a later edit to one copy looks like
#     it took effect when the other is what runs.
#
# Comment and blank lines are skipped: this file documents itself with them,
# and deliberately keeps entries commented out (see the casks and mas blocks).
#
# Run by .github/workflows/lint.yml and scripts/ci/lint-local.sh; both files
# name the other, so a change here lands in both.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BREWFILE=brew/Brewfile

# The types `brew bundle` accepts, each followed by the quoted name it acts on.
# The closing quote is required: without it `brew "foo` would pass here and be
# skipped by brew, which is the failure this check exists to catch.
ENTRY_RE='^(tap|brew|cask|mas|vscode|whalebrew) "[^"]+"'

# Everything after the type is "name", the pair the uniqueness rule is about.
# `tap "user/repo"` and `brew "user/repo/x"` are different entries.
PAIR_RE='s/^([a-z]+) "([^"]+)".*/\1 \2/p'

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

    if ! printf '%s\n' "$line" | grep -qE "$ENTRY_RE"; then
      malformed+=("${lineno}: ${line}")
      continue
    fi

    pair="$(printf '%s\n' "$line" | sed -nE "$PAIR_RE")"
    [ -n "$pair" ] && pairs+=("$pair")
  done <"$BREWFILE"

  if [ "${#pairs[@]}" -gt 0 ]; then
    while IFS= read -r pair; do
      duplicates+=("$pair")
    done < <(printf '%s\n' "${pairs[@]}" | sort | uniq -d)
  fi

  if [ "${#malformed[@]}" -ne 0 ]; then
    printf 'These lines are not a <type> "name" entry; brew bundle would skip them:\n' >&2
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
