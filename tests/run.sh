#!/usr/bin/env bash
# Runs every test suite and prints each one's wall time. Exits 1 if any fails.
#
#   bash tests/run.sh
#
# The three Python unit suites run first, then every tests/*.sh except this file
# and lib.sh. lib_units.py checks the journal under macOS's own /usr/bin/python3
# (3.9), the oldest interpreter it must work on. hygiene_units.py and
# policy_units.py need tomllib, so they run under the first python3 on PATH that
# is 3.11 or newer.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000'; }

failed=()
times=()

# run_one NAME CMD...: run one suite, record its wall time and status.
run_one() {
  local name="$1" start status ms
  shift
  printf '\n==> %s\n' "$name"
  start="$(now_ms)"
  "$@"
  status=$?
  ms=$(($(now_ms) - start))
  times+=("$(printf '%s %d.%03ds' "$name" $((ms / 1000)) $((ms % 1000)))")
  if [ "$status" -ne 0 ]; then
    failed+=("$name")
  fi
}

system_python=/usr/bin/python3
[ -x "$system_python" ] || system_python=python3

modern_python=
for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    modern_python="$candidate"
    break
  fi
done

run_one lib_units.py "$system_python" -B -I tests/lib_units.py
if [ -n "$modern_python" ]; then
  run_one hygiene_units.py "$modern_python" -B -I tests/hygiene_units.py
  run_one policy_units.py "$modern_python" -B -I tests/policy_units.py
else
  printf '\n==> hygiene_units.py, policy_units.py\nrun.sh: no python3 >= 3.11 on PATH\n' >&2
  failed+=(hygiene_units.py policy_units.py)
fi

for suite in tests/*.sh; do
  case "$suite" in
    tests/lib.sh | tests/run.sh) continue ;;
  esac
  run_one "$(basename "$suite")" "$BASH" "$suite"
done

printf '\n==> wall time\n'
printf '  %s\n' "${times[@]}"

if [ "${#failed[@]}" -ne 0 ]; then
  printf '\nrun.sh: FAILED - %s\n' "${failed[*]}"
  exit 1
fi
printf '\nrun.sh: all suites passed\n'
