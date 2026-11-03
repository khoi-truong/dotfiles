#!/usr/bin/env bash
# The one list of shell files every check reads: tracked files plus untracked
# ones that are not gitignored, so a new script is checked before it is staged.
#
#   list-shell-scripts.sh          bash/sh scripts, for shellcheck and shfmt
#   list-shell-scripts.sh --zsh    zsh files, for `zsh -n` (never shfmt)
#
# A file is classified by suffix first: `*.sh` is bash/sh; `*.zsh`, `zsh/zshrc`
# and `zsh/zshenv` are zsh. A file with no extension is classified by its
# shebang. Symlinks and paths missing from the working tree are skipped.
set -euo pipefail

want=bash
case "${1:-}" in
  '') ;;
  --zsh) want=zsh ;;
  *)
    printf 'usage: list-shell-scripts.sh [--zsh]\n' >&2
    exit 2
    ;;
esac

cd "$(git rev-parse --show-toplevel)"

classify() {
  case "$1" in
    *.sh) echo bash ;;
    *.zsh | zsh/zshrc | zsh/zshenv) echo zsh ;;
    *)
      case "${1##*/}" in
        *.*) return 0 ;;
      esac
      local first
      first="$(head -n 1 -- "$1" 2>/dev/null | LC_ALL=C tr -d '\0' || true)"
      case "$first" in
        '#!'*)
          if printf '%s\n' "$first" | grep -qE '\bzsh\b'; then
            echo zsh
          elif printf '%s\n' "$first" | grep -qE '\b(bash|sh)\b'; then
            echo bash
          fi
          ;;
      esac
      ;;
  esac
}

git ls-files -z --cached --others --exclude-standard | sort -zu | {
  while IFS= read -r -d '' file; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    kind="$(classify "$file")"
    if [ "$kind" = "$want" ]; then
      printf '%s\n' "$file"
    fi
  done
}
