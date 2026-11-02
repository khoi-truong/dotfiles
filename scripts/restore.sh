#!/usr/bin/env bash
# Undo a setup run from its journal.
#
#   scripts/restore.sh            undo the newest run not yet restored
#   scripts/restore.sh <attempt>  undo that run
#   scripts/restore.sh --list     list recorded runs, newest first
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"

case "${1:-}" in
  --list) set -- list ;;
  -h | --help)
    sed -n '2,6p' "$0"
    exit 0
    ;;
  *) set -- restore "$@" ;;
esac

exec "${DOTFILES_PYTHON:-python3}" -B "${DOTFILES}/lib/transaction.py" "$@"
