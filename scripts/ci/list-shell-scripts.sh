#!/usr/bin/env bash
# Lists tracked bash/sh scripts for shellcheck: every *.sh file, plus any
# tracked extensionless file whose shebang names bash or sh. Zsh files are
# excluded (they are checked separately with `zsh -n`).
set -euo pipefail

git ls-files | while IFS= read -r file; do
  case "$file" in
    *.sh)
      printf '%s\n' "$file"
      ;;
    *.zsh | zsh/zshrc | zsh/zshenv)
      ;;
    *.*)
      ;;
    *)
      if head -n 1 "$file" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b'; then
        printf '%s\n' "$file"
      fi
      ;;
  esac
done
