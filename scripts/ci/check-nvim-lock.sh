#!/usr/bin/env bash
# Fail unless every plugin in a lazy.nvim lockfile is checked out at the pinned
# commit. Usage: check-nvim-lock.sh LOCKFILE LAZY_DIR
# LAZY_DIR is <nvim data dir>/lazy, holding one directory per plugin.
set -euo pipefail

[ "$#" -eq 2 ] || {
  echo "usage: ${0##*/} LOCKFILE LAZY_DIR" >&2
  exit 2
}
lock="$1"
dir="$2"
status=0

while read -r name commit; do
  if [ ! -d "$dir/$name" ]; then
    echo "missing: $name" >&2
    status=1
    continue
  fi
  head="$(git -C "$dir/$name" rev-parse HEAD 2>/dev/null)" || head="unreadable"
  if [ "$head" != "$commit" ]; then
    echo "mismatch: $name is at $head, lockfile has $commit" >&2
    status=1
  fi
done < <(jq -r 'to_entries[] | "\(.key) \(.value.commit)"' "$lock")

exit "$status"
