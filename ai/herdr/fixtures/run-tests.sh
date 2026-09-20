#!/usr/bin/env bash
# run-tests.sh — the acceptance checks for `team.sh dispatch --from-plan`,
# `collect --plan`, `wait` and `teardown`.
#
# Static checks do not see inside team.sh's embedded python, and this
# repo has no test suite, so this script is the only thing that exercises the
# plan parser. Run it by hand after touching `plan_body`, `plan_rows`,
# `dispatched`, `cmd_wait` or the teardown guard:
#
#   bash ai/herdr/fixtures/run-tests.sh
#
# Every case points HERDR_TEAM_HANDOFFS at a throwaway directory, so nothing
# here reads or writes the live .omc/handoffs — which would also shift the
# next-dispatch ids of a real Run. The `wait` cases drive herdr itself through
# stubs on PATH: a fixture run has no herdr session, and a case that cannot run
# is a skip, not a pass. The `teardown` cases go further and register a real
# throwaway worktree under ${TMP}: the guard is a `git` question, so a fixture
# that answered it would be testing the fixture.
set -uo pipefail

# The tree under test is the tree this file is part of, resolved from its own
# path rather than inherited. DOTFILES is exported by the developer's shell
# profile and names the main checkout, so honouring it would have this suite
# reporting on main's team.sh — every case here would pass on a branch whose
# own copy is broken, and the `wait` cases would fail on a branch whose copy is
# right. Exported because team.sh reads it for the same root.
DOTFILES="$(cd "$(dirname "$0")/../../.." && pwd)"
export DOTFILES
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

# proven <task> — the `commands:` body that proves plan-ok.md's verify for that
# task: what an honest handoff carries. It mirrors the fixture plan, so a change
# there has to come here too — and when it does not, every case expecting `done`
# fails loudly instead of passing on a stale string.
proven() {
  case "$1" in
    T-01) printf '[{"cmd": "shellcheck -x ai/setup.sh", "exit": 0}]' ;;
    T-02) printf '[{"cmd": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1", "exit": 0}]' ;;
    *) printf '[]' ;;
  esac
}

# handoff <task> <run> <outcome> <evidence> [dispatch] [commands] — one fixture
# handoff. `commands` is written verbatim after the colon: the default proves
# that task's plan-ok verify, `none` writes no commands line at all (absence is
# never evidence), and the wrong-command, non-zero-exit and pre-contract shapes
# are what the cases pass in.
handoff() {
  local task="$1" d="${5:-D-01}" cmds=""
  if [ $# -ge 6 ]; then cmds="$6"; else cmds="$(proven "$task")"; fi
  {
    printf -- '---\n'
    printf 'run: %s\ntask: %s\ndispatch: %s\n' "$2" "$task" "$d"
    printf 'outcome: %s\nevidence: %s\n' "$3" "$4"
    [ "$cmds" = "none" ] || printf 'commands: %s\n' "$cmds"
    printf -- '---\n\n## What was done\n\nFixture.\n'
  } >"${HERDR_TEAM_HANDOFFS}/${task}-${d}.md"
}

# sent <run> <task> <dispatch> [agent] — one line in the dispatch journal,
# standing in for a real `dispatch` that has not been answered yet. The agent is
# the fourth column `dispatch` writes; leaving it off writes the three-column
# shape an older journal still has on disk, which both verbs have to read.
sent() {
  if [ $# -ge 4 ]; then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${HERDR_TEAM_HANDOFFS}/.dispatched"
  else
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"${HERDR_TEAM_HANDOFFS}/.dispatched"
  fi
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
expect_collect 3 '^T-01 +running +D-01' "16 a journalled dispatch with no handoff is running" \
  --plan "${FIXTURES}/plan-ok.md"

# 16b. Nothing to dispatch and nothing wrong: every Task settled. A loop needs
#      this apart from 0, or it re-reads the table to find out it is finished.
reset
handoff T-01 "${RUN}" succeeded verified
handoff T-02 "${RUN}" succeeded verified
expect_collect 3 '^T-02 +done' "16b exits 3 when every Task is done" \
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
echo "plan lint"

# expect_lint <want-exit> <stdout-regex> <label> <file>
expect_lint() {
  local want="$1" re="$2" label="$3" file="$4"
  local got
  "${TEAM}" plan lint "${FIXTURES}/${file}" >"${TMP}/out" 2>"${TMP}/err"
  got=$?
  if [ "$got" -ne "$want" ]; then
    no "$label" "exit ${got}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# 21-27. One fixture per finding. A check with no fixture is a check nobody
#        has seen fail, which is the same as not having it.
expect_lint 1 "no '## Tasks' json block" "21 missing task block" plan-no-block.md
expect_lint 1 'not valid JSON' "22 invalid JSON" plan-bad-json.md
expect_lint 1 'T-01 blocks on T-09' "23 blocks names a task with no row" plan-dangling.md
expect_lint 1 'cycle: T-01 -> T-02 -> T-01' "24 a cycle in blocks" plan-cycle.md
expect_lint 1 "row for T-02 but no '### T-02' section" "25 a row with no section" plan-no-section.md
expect_lint 1 'sections with no row: T-02' "26 a section with no row" plan-orphan.md
expect_lint 1 "verify pipes without a leading 'set -o pipefail'" \
  "27 a verify whose exit code is masked" plan-masking-verify.md

# 28. The passing case. plan-ok's piped verify leads with `set -o pipefail`,
#     which is exactly the shape the check is meant to allow.
expect_lint 0 ': ok$' "28 a well-formed plan passes" plan-ok.md

# 29. Every finding in one run — the whole reason plan_rows returns them
#     rather than raising on the first.
"${TEAM}" plan lint "${FIXTURES}/plan-many.md" >"${TMP}/out" 2>/dev/null
if [ "$(wc -l <"${TMP}/out")" -eq 3 ]; then
  ok "29 a plan with three problems reports all three"
else
  no "29 a plan with three problems reports all three" \
    "got $(wc -l <"${TMP}/out") line(s): $(tr '\n' '|' <"${TMP}/out")"
fi

# 30. The same plan through dispatch stops at the first, and still refuses.
reset
expect_exit 1 "30 dispatch refuses the same plan" \
  --task T-01 --from-plan "${FIXTURES}/plan-many.md"
if [ "$(grep -c '^dispatch: ' "${TMP}/err")" -eq 1 ]; then
  ok "30b dispatch reports one finding, not all of them"
else
  no "30b dispatch reports one finding, not all of them" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi

# 31. No file named is an error, not a clean plan.
if "${TEAM}" plan lint >/dev/null 2>&1; then
  no "31 plan lint with no file exits non-zero" "exited 0"
else
  ok "31 plan lint with no file exits non-zero"
fi

echo
echo "wait"

# `wait` blocks on a live pane, which a fixture run does not have, so herdr is
# stubbed on PATH. One stub per behaviour a real pane can have, and each case
# picks the one that makes its claim falsifiable rather than merely true.
mkdir -p "${TMP}/poison" "${TMP}/idle" "${TMP}/stuck" "${TMP}/error"
# Fails and records the call, so a `wait` that reaches herdr when it must not
# fails loudly instead of quietly passing.
cat >"${TMP}/poison/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/herdr-called"
exit 1
SH
# Returns at once, the way a pane that just reached a terminal state does.
cat >"${TMP}/idle/herdr" <<'SH'
#!/usr/bin/env bash
exit 0
SH
# Never returns: an agent that has not settled while the caller is watching.
cat >"${TMP}/stuck/herdr" <<'SH'
#!/usr/bin/env bash
exec sleep 300
SH
# Fails at once without matching, the shape of a herdr that cannot find the
# agent the journal names.
cat >"${TMP}/error/herdr" <<'SH'
#!/usr/bin/env bash
exit 3
SH
chmod +x "${TMP}/poison/herdr" "${TMP}/idle/herdr" "${TMP}/stuck/herdr" \
  "${TMP}/error/herdr"

# The window, for case 44: the handoff appears after the journal has been read.
# python3 is what reads it, so a python3 that runs the real interpreter first
# and writes the handoff after puts the file in the gap between the read and the
# fan-out on every run, instead of hoping to win a race. The content is never
# read — `wait` stats the path — and the herdr beside it is the poison one, so a
# `wait` that falls through to herdr fails that case rather than passing it.
mkdir -p "${TMP}/window"
REAL_PY="$(command -v python3)"
export REAL_PY
cat >"${TMP}/window/python3" <<'SH'
#!/usr/bin/env bash
"${REAL_PY}" "$@"
printf -- '---\nrun: fixture\ntask: T-01\ndispatch: D-01\noutcome: succeeded\nevidence: verified\n---\n' \
  >"${HERDR_TEAM_HANDOFFS}/T-01-D-01.md"
SH
cp "${TMP}/poison/herdr" "${TMP}/window/herdr"
chmod +x "${TMP}/window/python3" "${TMP}/window/herdr"

# wait_on <stub> <want-exit> <stdout-regex> <label> [args...] — `wait` with that
# stub's herdr first on PATH. An empty regex checks the exit code only. The
# timeout args are the cases' own: a wait that stops blocking fails the case
# eventually instead of wedging the suite.
wait_on() {
  local stub="$1" want="$2" re="$3" label="$4" code=0
  shift 4
  env PATH="${TMP}/${stub}:${PATH}" "${TEAM}" wait "$@" >"${TMP}/out" 2>"${TMP}/err" ||
    code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# 32. Nothing sent is nothing to wait for — and it is 3, not 0, so a caller
#     cannot read "I waited and nothing happened" into a Run that has no work.
reset
wait_on poison 3 "" "32 an empty journal has nothing to wait for"

# 33. The outstanding definition, from the other side: a Dispatch whose handoff
#     is on disk has settled, so it must not be blocked on. The stub fails and
#     records the call, so a `wait` that blocks here anyway is a failure here.
reset
sent "${RUN}" T-01 D-01 exec-1
handoff T-01 "${RUN}" succeeded verified D-01
rm -f "${TMP}/herdr-called"
wait_on poison 3 "" "33 a Dispatch with a handoff is not outstanding: exit 3, herdr untouched"
if [ ! -e "${TMP}/herdr-called" ]; then
  ok "33b herdr was not reached for a settled Dispatch"
else
  no "33b herdr was not reached for a settled Dispatch" \
    "herdr called with: $(tr '\n' '|' <"${TMP}/herdr-called")"
fi

# 34. The four-column line: the agent column is what `wait` fans out on. A
#     three-column journal cannot even reach herdr, so this is also the case
#     that says `dispatch` writes the agent.
reset
sent "${RUN}" T-01 D-01 exec-1
wait_on idle 0 '^exec-1 T-01 settled$' "34 a four-column line names the agent to wait on" \
  --timeout 5000

# 35. The same line through the table, so the two verbs agree on what is out.
reset
sent "${RUN}" T-01 D-01 exec-1
expect_collect 3 '^T-01 +running +D-01' "35 a four-column line still reads as running" \
  --plan "${FIXTURES}/plan-ok.md"

# 36/37. The legacy three-column journal, both verbs, as separate cases. Reading
#        one shape and refusing the other is the regression this pair catches:
#        collect must keep counting the Dispatch, and wait must say why it
#        cannot watch it rather than crashing or blocking on nothing.
reset
sent "${RUN}" T-01 D-01
expect_collect 3 '^T-01 +running +D-01' "36 a legacy three-column line still reads as running" \
  --plan "${FIXTURES}/plan-ok.md"

reset
sent "${RUN}" T-01 D-01
rm -f "${TMP}/herdr-called"
wait_on poison 3 "" "37 wait skips a legacy line with a warning instead of crashing"
if grep -q 'no agent in the journal' "${TMP}/err" && [ ! -e "${TMP}/herdr-called" ]; then
  ok "37b the skip names the Dispatch and reaches no agent"
else
  no "37b the skip names the Dispatch and reaches no agent" \
    "herdr called: $(tr '\n' '|' <"${TMP}/herdr-called" 2>/dev/null); $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi

# 38. No Run and no run file: a precondition failure, like every other verb.
reset
mv "${HERDR_TEAM_RUN_FILE}" "${TMP}/run.away"
wait_on poison 1 "" "38 wait with no Run exits 1"
mv "${TMP}/run.away" "${HERDR_TEAM_RUN_FILE}"

# 39. A journal line this code cannot read is a Dispatch it cannot watch.
#     Skipping it would let a wait outlive the work it was started for.
reset
printf '%s\tT-01\n' "${RUN}" >>"${HERDR_TEAM_HANDOFFS}/.dispatched"
wait_on poison 1 "" "39 a journal line that is neither 3 nor 4 columns is refused"
if grep -q 'journal line 1 is not 3 or 4 columns' "${TMP}/err"; then
  ok "39b the refused line is named by number"
else
  no "39b the refused line is named by number" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 40. A timeout is a checkpoint, not an empty answer: 4, never 3. An agent that
#     has not settled looks exactly like no agent at all if these are the same.
reset
sent "${RUN}" T-01 D-01 exec-1
wait_on stuck 4 "" "40 --timeout with nothing settled exits 4, not 3" --timeout 400

# 41. herdr exiting non-zero is reported rather than acted on — its exit codes
#     on a match and on an expiry are not documented as distinguishable.
reset
sent "${RUN}" T-01 D-01 exec-1
wait_on error 0 '^exec-1 T-01 settled$' "41 a non-zero herdr still settles and is reported" \
  --timeout 5000
if grep -q 'exited 3' "${TMP}/err"; then
  ok "41b the herdr exit code is named in the warning"
else
  no "41b the herdr exit code is named in the warning" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 42. Two Dispatch out at once, which is the fan-in's reason to exist: one of
#     them settling returns the caller, not all of them, and one line says so.
reset
sent "${RUN}" T-01 D-01 exec-1
sent "${RUN}" T-02 D-01 exec-2
wait_on idle 0 'settled$' "42 one settling Dispatch returns with two out" --timeout 5000
if [ "$(grep -c 'settled$' "${TMP}/out")" -eq 1 ]; then
  ok "42b exactly one settling is reported"
else
  no "42b exactly one settling is reported" "$(tr '\n' '|' <"${TMP}/out")"
fi

# 43. --plan is accepted and dropped, so `wait` and `collect --plan` read alike
#     in a loop: blocking is a question about the Run, not about the plan.
reset
sent "${RUN}" T-01 D-01 exec-1
wait_on idle 0 '^exec-1 T-01 settled$' "43 --plan is accepted and changes nothing" \
  --plan "${FIXTURES}/plan-ok.md" --timeout 5000

# 44. The window: a Dispatch that settles after the journal was read but before
#     the fan-out. Staged rather than raced — python3 is the last thing between
#     those two, so a python3 that runs the real interpreter and only then
#     writes the handoff lands in the gap every time. A herdr subscription does
#     not replay, so this is the case that would hang forever without the
#     short-circuit, and the stub below fails loudly if `wait` falls through.
reset
sent "${RUN}" T-01 D-01 exec-1
rm -f "${TMP}/herdr-called"
wait_on window 0 '^exec-1 T-01 settled$' "44 a handoff appearing in the window settles without herdr" \
  --timeout 5000
if [ ! -e "${TMP}/herdr-called" ]; then
  ok "44b herdr was not reached for a handoff that appeared"
else
  no "44b herdr was not reached for a handoff that appeared" \
    "herdr called with: $(tr '\n' '|' <"${TMP}/herdr-called")"
fi

# 45. The live case: a real pane, a real agent, a real transition.
sk "45 a live agent settling returns from wait" \
  "a fixture run has no herdr session — drive it by hand: team.sh wait while a dispatched agent works"

echo
echo "verify ↔ commands:"

# One `commands:` shape per case. Each is the string a handoff puts after
# `commands: ` — the default, which proves plan-ok's verify, is case 46.
BAD_EXIT='[{"cmd": "shellcheck -x ai/setup.sh", "exit": 1}]'
OTHER_CMD='[{"cmd": "shellcheck -x README.md", "exit": 0}]'
PRE_CONTRACT='[{cmd: "shellcheck -x ai/setup.sh", exit: 0}]'

# 46. The contract holding: the handoff names the row's verify at exit 0.
reset
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 0 '^T-01 +done +D-01' "46 a proved verify is done" \
  --plan "${FIXTURES}/plan-ok.md"

# 47. The same command at a non-zero exit proves nothing. This is the case the
#     mutation check deletes the `"exit": 0` requirement to break.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$BAD_EXIT"
expect_collect 0 '^T-01 +review +D-01 +UNVERIFIED' "47 exit 1 is UNVERIFIED, not done" \
  --plan "${FIXTURES}/plan-ok.md"

# 48. A handoff full of commands that are not this Task's verify.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$OTHER_CMD"
expect_collect 0 '^T-01 +review +D-01 +UNVERIFIED' "48 another command is UNVERIFIED" \
  --plan "${FIXTURES}/plan-ok.md"

# 49. No commands line at all. Absence is never evidence, and it has to be
#     tellable apart from 50.
reset
handoff T-01 "${RUN}" succeeded verified D-01 none
expect_collect 0 '^T-01 +review +D-01 +UNVERIFIED' "49 an absent commands line is UNVERIFIED" \
  --plan "${FIXTURES}/plan-ok.md"

# 50. The shape every handoff written before this task carries. A human has to
#     be able to tell it from a claim that does not hold — hence UNPARSED.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$PRE_CONTRACT"
expect_collect 0 '^T-01 +review +D-01 +UNPARSED' "50 an unquoted-key commands line is UNPARSED" \
  --plan "${FIXTURES}/plan-ok.md"

# 51. An empty verify is the planner's own choice: nothing to check, done
#     stands — even with no commands line to check against, which is 49's shape
#     read as a result. Nothing actionable follows, so the exit is 3.
reset
handoff T-01 "${RUN}" succeeded verified D-01 none
expect_collect 3 '^T-01 +done +D-01' "51 an empty verify needs no commands entry" \
  --plan "${FIXTURES}/plan-empty-verify.md"

# 52. The case the whole task exists for: a dependent of an UNVERIFIED Task
#     waits, because `done` is the only state that unblocks anything.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$BAD_EXIT"
expect_collect 0 '^T-02 +blocked +- +blocked on T-01' \
  "52 a dependent of an UNVERIFIED Task is blocked, not ready" \
  --plan "${FIXTURES}/plan-ok.md"
if grep -qE '^T-01 +review +D-01 +UNVERIFIED' "${TMP}/out"; then
  ok "52b the blocker itself reads UNVERIFIED"
else
  no "52b the blocker itself reads UNVERIFIED" "$(tr '\n' '|' <"${TMP}/out")"
fi

# 53. The prompt's golden line is the contract this check reads: quoted keys on
#     one line, and a value json.loads accepts. A multi-line value would break
#     the line-oriented frontmatter parser, which is why it stays one line.
cmds="$(grep -m1 '^commands: ' "${FIXTURES}/golden/T-01-dispatch.prompt" | sed 's/^commands: //')"
if [ -n "$cmds" ] && printf '%s' "$cmds" | python3 -c '
import json, sys
entries = json.load(sys.stdin)
ok = (isinstance(entries, list) and entries and isinstance(entries[0], dict)
      and "cmd" in entries[0] and entries[0]["exit"] == 0)
sys.exit(0 if ok else 1)
'; then
  ok "53 the golden prompt's commands: line is JSON the check can read"
else
  no "53 the golden prompt's commands: line is JSON the check can read" \
    "value: ${cmds:-<none>}"
fi

echo
echo "teardown"

# The guard is a `git` question, so it is asked of real git state: a throwaway
# branch cut from main in this repo, registered and removed again by these
# cases. One path, reused — case 54's teardown removes the worktree, the next
# case puts it back — and one stub herdr, which reports that path as exec-9's
# cwd. A branch with an upstream is measured against it; a branch without one
# against main, which is what a worktree branch here is cut from.
T05_BRANCH="fixture-t05-$$"
WT="${TMP}/throwaway"
mkdir -p "${TMP}/teardown"
cat >"${TMP}/teardown/herdr" <<SH
#!/usr/bin/env bash
if [ "\$1" = "agent" ] && [ "\$2" = "list" ]; then
  printf '{"result": {"agents": [{"name": "exec-9", "cwd": "${WT}", "workspace_id": "ws-fixture", "pane_id": "pane-9"}]}}\n'
  exit 0
fi
exit 0
SH
chmod +x "${TMP}/teardown/herdr"

# wt_add <suffix> — the throwaway worktree, cut fresh from main. Anything left
# at that path comes off first: a case that failed to tear the worktree down
# would otherwise decide what the next case is looking at, and a run whose
# guard is broken has to fail the same way every time.
wt_add() {
  git -C "${DOTFILES}" worktree remove --force "${WT}" 2>/dev/null || true
  rm -rf "${WT}"
  git -C "${DOTFILES}" worktree add --quiet -b "${T05_BRANCH}-$1" "${WT}" main 2>"${TMP}/err"
}

# teardown_on <want-exit> <stdout-regex> <label> — teardown of exec-9, whose
# stub herdr reports the throwaway worktree as its cwd.
teardown_on() {
  local want="$1" re="$2" label="$3" code=0
  env PATH="${TMP}/teardown:${PATH}" "${TEAM}" teardown exec-9 \
    >"${TMP}/out" 2>"${TMP}/err" || code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in stdout: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

if wt_add a; then
  # 54. The defect this task exists for: zero commits of its own, no upstream.
  #     There is nothing to lose, so there is nothing to refuse over — and no
  #     reason to reach for --force on a guard that was right to fire.
  teardown_on 0 'torn down' "54 a branch level with main tears down without --force"
  if [ ! -d "${WT}" ]; then
    ok "54b the worktree is gone, not just the pane"
  else
    no "54b the worktree is gone, not just the pane" "still at ${WT}"
  fi

  # 55. The case the guard is right about, still refused without --force. The
  #     commit is empty and skips hooks: this is about the count of commits
  #     ahead, not about what is in them.
  wt_add b
  git -C "${WT}" -c commit.gpgsign=false -c user.email=fixture@example.com \
    -c user.name=fixture commit --quiet --no-verify --allow-empty -m "unpushed"
  teardown_on 1 '' "55 one unpushed commit and no upstream is still refused"
  if grep -q 'unpushed commits' "${TMP}/err" && grep -q -- '--force' "${TMP}/err"; then
    ok "55b the refusal names the work, and the way past it"
  else
    no "55b the refusal names the work, and the way past it" "$(tr '\n' '|' <"${TMP}/err")"
  fi
  if [ -d "${WT}" ]; then
    ok "55c the refusal left the worktree alone"
  else
    no "55c the refusal left the worktree alone" "the worktree it refused is gone"
  fi

  # 56. A branch with an upstream and nothing ahead of it: already pushed, by
  #     the only test of that this suite can make without a network. The
  #     mechanism is the same `@{u}..HEAD` a real push satisfies.
  git -C "${DOTFILES}" worktree remove --force "${WT}" 2>/dev/null
  wt_add c
  git -C "${WT}" branch --set-upstream-to=main --quiet
  teardown_on 0 'torn down' "56 a branch level with its upstream tears down without --force"

  git -C "${DOTFILES}" worktree remove --force "${WT}" 2>/dev/null
  for b in a b c; do git -C "${DOTFILES}" branch -D "${T05_BRANCH}-$b"; done >/dev/null 2>&1
else
  sk "54 a branch level with main tears down without --force" \
    "no throwaway worktree: $(head -1 "${TMP}/err")"
  sk "55 one unpushed commit and no upstream is still refused" "no throwaway worktree"
  sk "56 a branch level with its upstream tears down without --force" "no throwaway worktree"
fi

echo
echo "collect --plan: releasable"

# 57. The marker's positive case: the Task is done and the agent that worked it
#     has nothing else out under this Run, so it can be released — and the row
#     names it, because `settle` needs a name and re-deriving one from the
#     journal is the work this column is here to save.
reset
sent "${RUN}" T-01 D-01 exec-1
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 0 '^T-01 +done +D-01 +releasable exec-1' "57 a done Task names its idle agent releasable" \
  --plan "${FIXTURES}/plan-ok.md"

# 58. The same agent holding a second Task that is still out. Settling its pane
#     would take it away from work it is in the middle of, so no marker — and
#     this is the case a marker keyed on the Task rather than the agent fails.
reset
sent "${RUN}" T-01 D-01 exec-1
sent "${RUN}" T-02 D-01 exec-1
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 3 '^T-01 +done +D-01 +succeeded/verified' \
  "58 a done Task is not releasable while its agent has another Task out" \
  --plan "${FIXTURES}/plan-ok.md"
if grep -q 'releasable' "${TMP}/out"; then
  no "58b nothing is marked releasable" "$(tr '\n' '|' <"${TMP}/out")"
else
  ok "58b nothing is marked releasable"
fi

# 59. A review is not an outstanding Dispatch: the agent's work is handed in,
#     and it is a reviewer who owes an answer now. Case 57 covers the marker's
#     positive side; this is what keeps it from disappearing entirely.
reset
sent "${RUN}" T-01 D-01 exec-1
sent "${RUN}" T-02 D-01 exec-1
handoff T-01 "${RUN}" succeeded verified D-01
handoff T-02 "${RUN}" succeeded reported D-01
expect_collect 0 '^T-01 +done +D-01 +releasable exec-1' \
  "59 a Task awaiting review does not hold its agent back" \
  --plan "${FIXTURES}/plan-ok.md"

# 60. A three-column journal: the older shape has no agent to name, so there is
#     nothing to settle and nothing to mark. Naming a Task rather than an agent
#     would mark this row, and `settle` would fail on the name.
reset
sent "${RUN}" T-01 D-01
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 0 '^T-01 +done +D-01 +succeeded/verified' \
  "60 a legacy journal line marks nothing releasable" \
  --plan "${FIXTURES}/plan-ok.md"

# 61. A journal entry for a Task the plan does not list. `outstanding` is a
#     question about the Run, not about the plan: a Dispatch in the journal is
#     out whether or not a row mentions it, so the agent is not idle and the
#     done row must not say it is.
reset
sent "${RUN}" T-01 D-01 exec-1
sent "${RUN}" T-09 D-01 exec-1
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 0 '^T-01 +done +D-01 +succeeded/verified' \
  "61 a Dispatch outside the plan still holds its agent" \
  --plan "${FIXTURES}/plan-ok.md"

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
