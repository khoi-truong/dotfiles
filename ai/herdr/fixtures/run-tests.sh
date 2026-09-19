#!/usr/bin/env bash
# run-tests.sh — the acceptance checks for `team.sh dispatch --from-plan`.
#
# Static checks do not see inside team.sh's embedded python, and this
# repo has no test suite, so this script is the only thing that exercises the
# plan parser. Run it by hand after touching `plan_body`:
#
#   bash ai/herdr/fixtures/run-tests.sh
#
# Every case points HERDR_TEAM_HANDOFFS at a throwaway directory, so nothing
# here reads or writes the live .omc/handoffs — which would also shift the
# next-dispatch ids of a real Run.
set -uo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/../../.." && pwd)}"
FIXTURES="${DOTFILES}/ai/herdr/fixtures"
TEAM="${DOTFILES}/ai/herdr/team.sh"
RUN="R-fixture-0001"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export HERDR_TEAM_HANDOFFS="${TMP}/handoffs"
mkdir -p "${HERDR_TEAM_HANDOFFS}"
# Same reason: without an override `collect --plan` with no positional Run
# would read whatever Run the developer happens to have started.
export HERDR_TEAM_RUN_FILE="${TMP}/team-run"
printf '%s\n' "${RUN}" >"${HERDR_TEAM_RUN_FILE}"

pass=0 fail=0 skip=0

ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL %s\n    %s\n' "$1" "$2"; fail=$((fail + 1)); }
# A case the environment cannot run is not a case that passed. Say so.
sk() { printf '  skip %s\n    %s\n' "$1" "$2"; skip=$((skip + 1)); }

# handoff <task> <run> <outcome> <evidence> [dispatch] — one fixture handoff.
handoff() {
  local d="${5:-D-01}"
  cat >"${HERDR_TEAM_HANDOFFS}/${1}-${d}.md" <<EOF
---
run: ${2}
task: ${1}
dispatch: ${d}
outcome: ${3}
evidence: ${4}
---

## What was done
Fixture.
EOF
}

# sent <run> <task> <dispatch> — one line in the dispatch journal, standing in
# for a real `dispatch` that has not been answered yet.
sent() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"${HERDR_TEAM_HANDOFFS}/.dispatched"
}

# reset — no handoffs, no journal.
reset() {
  rm -f "${HERDR_TEAM_HANDOFFS}"/*.md "${HERDR_TEAM_HANDOFFS}/.dispatched"
}

# dispatch <args...> — always --dry-run, so no agent is required. Prints the
# prompt on stdout and the exit code as the last line of stderr's place.
dispatch() {
  "${TEAM}" dispatch exec-1 --run "${RUN}" --dry-run "$@" 2>"${TMP}/err"
}

# expect_exit <want> <label> <args...>
expect_exit() {
  local want="$1" label="$2"; shift 2
  local got
  dispatch "$@" >"${TMP}/out"
  got=$?
  if [ "$got" -eq "$want" ]; then
    ok "$label"
  else
    no "$label" "exit ${got}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  fi
}

echo "dispatch --from-plan"

# 1. The prompt is a pointer carrying the plan path, the task and the verify
#    command. Normalised against a golden file: the plan path and the handoff
#    directory are absolute and machine-specific.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
dispatch --task T-01 --from-plan "${FIXTURES}/plan-ok.md" >"${TMP}/out"
sed -e "s#${FIXTURES}#<FIXTURES>#g" -e "s#${HERDR_TEAM_HANDOFFS}#<HANDOFFS>#g" \
  "${TMP}/out" >"${TMP}/norm"
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
  cp "${TMP}/norm" "${FIXTURES}/golden/T-01-dispatch.prompt"
  ok "1 golden updated"
elif diff -u "${FIXTURES}/golden/T-01-dispatch.prompt" "${TMP}/norm" >"${TMP}/diff"; then
  ok "1 unblocked dispatch matches the golden prompt"
else
  no "1 unblocked dispatch matches the golden prompt" "$(head -20 "${TMP}/diff")"
fi

# 2. A blocker with no handoff at all.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
expect_exit 3 "2 blocked when the blocker has no handoff" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 3. The Run-scoping case: a verified handoff for T-01 under a *different* Run.
#    Task ids restart every Run and the filename carries no Run, so this is the
#    case that silently unblocks if the gate forgets to read the frontmatter.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
handoff T-01 "R-fixture-9999" succeeded verified
expect_exit 3 "3 blocked when the only verified handoff is another Run's" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 4. succeeded but only reported: a claim, not a result.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
handoff T-01 "${RUN}" succeeded reported
expect_exit 3 "4 blocked when the blocker is succeeded/reported" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 5. succeeded and verified, this Run.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
handoff T-01 "${RUN}" succeeded verified
expect_exit 0 "5 ready when the blocker is verified under this Run" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 6. --force is the human-gated escape.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
expect_exit 0 "6 --force dispatches over an unmet blocker" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md" --force
if grep -q 'force' "${TMP}/err"; then
  ok "6b --force warns on stderr"
else
  no "6b --force warns on stderr" "no warning in stderr"
fi

# 7. A section with no row is a plan that would silently drop work.
expect_exit 1 "7 refuses a plan whose sections and rows disagree" \
  --task T-01 --from-plan "${FIXTURES}/plan-orphan.md"

# 7b. A cycle in `blocks` is a whole-document property: the row for T-01 only
#     knows it waits on T-02, so this fails only if the parser reads every row.
expect_exit 1 "7b refuses a plan whose blocks form a cycle" \
  --task T-01 --from-plan "${FIXTURES}/plan-cycle.md"

echo
echo "body precedence"

# 8. argv still wins, with no plan involved.
rm -f "${HERDR_TEAM_HANDOFFS}"/*.md
if dispatch --task T-01 "do the thing" >"${TMP}/out" &&
  grep -q 'do the thing' "${TMP}/out"; then
  ok "8 argv body unchanged"
else
  no "8 argv body unchanged" "$(head -2 "${TMP}/err")"
fi

# 9. stdin still works when something is actually piped in.
if printf 'piped body\n' | dispatch --task T-01 >"${TMP}/out" &&
  grep -q 'piped body' "${TMP}/out"; then
  ok "9 stdin body unchanged"
else
  no "9 stdin body unchanged" "$(head -2 "${TMP}/err")"
fi

# 10. No argv, no plan, stdin is a terminal: an error, never a hang. This needs
#     a real pty for [ -t 0 ] to be true, which an agent pane or a CI runner
#     may not have — hence the skip rather than a pass. A hang here would be
#     indistinguishable from a slow dispatch, so the guard is worth the
#     awkwardness.
out=""
if [ -t 0 ]; then
  out="$("${TEAM}" dispatch exec-1 --run "${RUN}" --dry-run --task T-01 2>&1 </dev/tty || true)"
elif [ -e /dev/tty ] && script -q /dev/null true >/dev/null 2>&1; then
  out="$(script -q /dev/null \
    "${TEAM}" dispatch exec-1 --run "${RUN}" --dry-run --task T-01 2>&1 || true)"
else
  sk "10 a terminal with no body errors instead of hanging" "no pty available here"
fi
if [ -n "$out" ]; then
  if printf '%s' "$out" | grep -q 'no work description given'; then
    ok "10 a terminal with no body errors instead of hanging"
  else
    no "10 a terminal with no body errors instead of hanging" \
      "got: $(printf '%s' "$out" | head -2)"
  fi
fi

echo
echo "collect --plan"

# expect_collect <want-exit> <stdout-regex> <label> <args...> — an empty regex
# checks the exit code only.
expect_collect() {
  local want="$1" re="$2" label="$3"; shift 3
  local got
  "${TEAM}" collect "$@" >"${TMP}/out" 2>"${TMP}/err"
  got=$?
  if [ "$got" -ne "$want" ]; then
    no "$label" "exit ${got}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# 11. The live bug this flag had to fix: `collect --plan f` used to bind
#     "--plan" to the positional Run and report nothing, with exit 0.
reset
handoff T-01 "${RUN}" succeeded verified
expect_collect 0 '^T-01 +done' "11 --plan resolves the current Run, not the flag" \
  --plan "${FIXTURES}/plan-ok.md"

# 12. No Run at all is a precondition failure, not an empty report.
reset
mv "${HERDR_TEAM_RUN_FILE}" "${TMP}/run.away"
expect_collect 1 "" "12 --plan with no Run exits 1" --plan "${FIXTURES}/plan-ok.md"
mv "${TMP}/run.away" "${HERDR_TEAM_RUN_FILE}"

# 13. The fold rule. A Task that failed and was retried to success must read
#     `done`, or a loop watching this table can never terminate.
reset
handoff T-01 "${RUN}" failed reported D-01
handoff T-01 "${RUN}" succeeded verified D-02
expect_collect 0 '^T-01 +done +D-02' "13 the highest dispatch wins over an earlier failure" \
  --plan "${FIXTURES}/plan-ok.md"

# 14. The C1 case at the collect layer: a blocker verified under a different
#     Run must leave the dependent blocked, exactly as the dispatch gate does.
reset
handoff T-01 "R-fixture-9999" succeeded verified
expect_collect 0 '^T-02 +blocked +- +blocked on T-01' \
  "14 a blocker verified under another Run leaves the dependent blocked" \
  --plan "${FIXTURES}/plan-ok.md"

# 15. `succeeded` at `reported` is a claim: actionable as `review`, never done.
reset
handoff T-01 "${RUN}" succeeded reported
expect_collect 0 '^T-01 +review' "15 succeeded/reported is review, not done" \
  --plan "${FIXTURES}/plan-ok.md"

# 16. Dispatched with no handoff yet. Nothing but the journal can tell this
#     apart from never dispatched.
reset
sent "${RUN}" T-01 D-01
expect_collect 0 '^T-01 +running +D-01' "16 a journalled dispatch with no handoff is running" \
  --plan "${FIXTURES}/plan-ok.md"

# 17. Nothing actionable and something failed: the orchestrator stops.
reset
handoff T-01 "${RUN}" failed tool_error
expect_collect 2 '^T-01 +failed' "17 exits 2 when nothing is actionable and a Task failed" \
  --plan "${FIXTURES}/plan-ok.md"

# 18. A malformed plan fails whole, before any of it is reported.
reset
expect_collect 1 "" "18 --plan refuses a plan with a cycle" \
  --plan "${FIXTURES}/plan-cycle.md"

echo
echo "collect without --plan"

# 19. Unchanged: no Run named still means every Run. Defaulting this path to
#     the current Run would silently drop rows `collect` has always printed.
reset
handoff T-01 "${RUN}" succeeded verified
handoff T-02 "R-fixture-9999" failed reported
if "${TEAM}" collect >"${TMP}/out" 2>"${TMP}/err" &&
  grep -q "${RUN}" "${TMP}/out" && grep -q 'R-fixture-9999' "${TMP}/out"; then
  ok "19 no Run named still lists every Run"
else
  no "19 no Run named still lists every Run" "$(tr '\n' '|' <"${TMP}/out")"
fi

# 20. A positional Run still filters, and is still not confused with a flag.
if "${TEAM}" collect "${RUN}" >"${TMP}/out" 2>"${TMP}/err" &&
  grep -q "${RUN}" "${TMP}/out" && ! grep -q 'R-fixture-9999' "${TMP}/out"; then
  ok "20 a positional Run still filters"
else
  no "20 a positional Run still filters" "$(tr '\n' '|' <"${TMP}/out")"
fi

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
