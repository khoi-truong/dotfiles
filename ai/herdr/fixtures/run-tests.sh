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

# T-06: one pane, one knob. `${TMP}/status` is the state that pane is in, and
# two agents are always live in it — exec-1, who the journal below knows, and
# exec-9, who it does not. `agent wait` matches at once and exits 0 whatever
# the status says, because the real one does: idle, done and blocked share an
# exit code (T-01), which is exactly why `wait` cannot read the state out of
# the wait and has to ask the agent. `agent read` records its argv, so a case
# can see the read it was given and not just the text that came back.
mkdir -p "${TMP}/panes"
cat >"${TMP}/panes/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent wait") exit 0 ;;
  "agent list")
    st="\$(cat "${TMP}/status")"
    printf '{"result":{"agents":['
    printf '{"name":"exec-1","pane_id":"wM:p1","agent_status":"%s"},' "\$st"
    printf '{"name":"exec-9","pane_id":"wM:p9","agent_status":"%s"}' "\$st"
    printf ']}}\n'
    ;;
  "agent read")
    printf '%s\n' "\$*" >>"${TMP}/read-called"
    printf 'Approve running this command? [y/n]\n'
    ;;
  *) exit 9 ;;
esac
SH
chmod +x "${TMP}/panes/herdr"
printf 'idle\n' >"${TMP}/status"

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

# 45b. Blocked is not settled, and 5 is how the orchestrator learns there is a
#      question without watching the pane — the manual step this exists to
#      remove. The stub's `agent wait` exits 0 exactly as it does for a settle,
#      so this fails if the state is read out of that exit code.
reset
sent "${RUN}" T-01 D-01 exec-1
printf 'blocked\n' >"${TMP}/status"
wait_on panes 5 '^exec-1 T-01 blocked$' "45b a blocked agent exits 5, not 0" --timeout 5000
if grep -q 'surface exec-1' "${TMP}/err"; then
  ok "45c the warning says what to do about it"
else
  no "45c the warning says what to do about it" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 45d. The counterpart, so 5 cannot be a constant: the same stub with the agent
#      idle is 0 and says settled. A stub that answers no state at all is a
#      third shape, covered by 34 and 42 — the empty answer has to stay a
#      settle, or every `idle` case in this section would turn into a 5.
reset
sent "${RUN}" T-01 D-01 exec-1
printf 'idle\n' >"${TMP}/status"
wait_on panes 0 '^exec-1 T-01 settled$' "45d an idle agent is still exit 0" --timeout 5000

# 45e. And the other terminal state, so the pair the plan names is the pair
#      this suite holds: the check is "blocked and nothing else", not "idle".
reset
sent "${RUN}" T-01 D-01 exec-1
printf 'done\n' >"${TMP}/status"
wait_on panes 0 '^exec-1 T-01 settled$' "45e a done agent is still exit 0" --timeout 5000

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
echo "surface"

# expect_surface <stub> <want-exit> <stdout-regex> <label> [args...] — wait_on's
# shape for the verb that shows a pane instead of waiting on one. A `die` lands
# on stderr, so a case wanting a refusal's wording greps ${TMP}/err itself.
expect_surface() {
  local stub="$1" want="$2" re="$3" label="$4" code=0
  shift 4
  env PATH="${TMP}/${stub}:${PATH}" "${TEAM}" surface "$@" >"${TMP}/out" 2>"${TMP}/err" ||
    code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# 62. The question in one block: whose it is, and what the pane says. This is
#     the other half of exit 5 — a wait that only said "blocked" would send the
#     orchestrator looking for a screen it has no verb to read.
reset
sent "${RUN}" T-01 D-01 exec-1
printf 'blocked\n' >"${TMP}/status"
rm -f "${TMP}/read-called"
expect_surface panes 0 'Approve running this command' \
  "62 surface prints the pane's visible screen" exec-1
if grep -q "^Run: ${RUN}\$" "${TMP}/out" && grep -q '^Task: T-01$' "${TMP}/out" &&
  grep -q '^Dispatch: D-01$' "${TMP}/out"; then
  ok "62b it names the Run, Task and Dispatch from the journal"
else
  no "62b it names the Run, Task and Dispatch from the journal" "$(tr '\n' '|' <"${TMP}/out")"
fi
# The read is the protocol's sanctioned diagnostic one (SKILL.md): the visible
# screen, capped. Neither flag shows in the output, so the argv the stub
# recorded is the only place a lost one would appear — and a scrollback read of
# a pane nobody asked about is the mistake that would be.
if grep -q -e '--source visible.*--lines 80' "${TMP}/read-called"; then
  ok "62c the screen read is the capped visible one"
else
  no "62c the screen read is the capped visible one" \
    "$(tr '\n' '|' <"${TMP}/read-called" 2>/dev/null)"
fi

# 63. Live, but this Run's journal has no line for it. The screen is what the
#     human was asked to come and look at, so it is printed either way; what
#     changes is that the header says unknown instead of inventing a Task.
reset
sent "${RUN}" T-01 D-01 exec-1
printf 'blocked\n' >"${TMP}/status"
expect_surface panes 0 'Approve running this command' \
  "63 an agent with no journal line still prints its screen" exec-9
if grep -q '^Task: unknown$' "${TMP}/out" && grep -q '^Dispatch: unknown$' "${TMP}/out" &&
  grep -q 'no journal line' "${TMP}/err"; then
  ok "63b and says the Task and Dispatch are unknown rather than inventing them"
else
  no "63b and says the Task and Dispatch are unknown rather than inventing them" \
    "$(tr '\n' '|' <"${TMP}/out")"
fi

# 64. An agent that is not live is a precondition failure, not an empty screen:
#     there is no pane to put in front of anyone.
reset
expect_surface panes 1 '' "64 surface on an unknown agent exits 1" nosuch
if grep -q 'no live agent named nosuch' "${TMP}/err"; then
  ok "64b the refusal names the agent it could not find"
else
  no "64b the refusal names the agent it could not find" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 65. Bare `surface` is the same usage error every other verb missing its
#     argument is, not a report on whatever pane happens to be around.
reset
expect_surface panes 1 'team\.sh surface' "65 surface with no agent prints the usage"

# 66. The no-answer rule, asserted mechanically because it is the one property
#     here that no output can demonstrate: `surface` reads panes, it does not
#     type into them. An approval dialog is the human's to answer, so a call
#     that sends keys added to the body fails this case.
if [ "$(awk '/^cmd_surface\(\)/,/^}/' "${TEAM}" | grep -c 'send-keys')" -eq 0 ]; then
  ok "66 cmd_surface sends nothing"
else
  no "66 cmd_surface sends nothing" "the body calls a key-sending verb"
fi

echo
echo "spawn: the provider check"

# The check T-09 repairs. `spawn` used to launch the pane and then poll the
# visible screen for the provider label's glyph, which nothing renders any
# more — so every `ccd` spawn failed on a marker and blamed 1Password for it.
# What it guards is real, and it is asserted here instead: the `key=env:VAR` a
# provider names has to resolve to something in the pane's own login shell,
# asked before the pane exists rather than inferred from a glyph after.
#
# The stubs answer as a login shell would, so most of these cases are about
# what spawn does with the answer. The two `realzsh` cases ask a real zsh with
# the probe team.sh actually sends it: a stub answers in whatever shape the
# case chose, so a probe and a parser that disagree about the separator would
# pass every stubbed case here and fail in the field.
mkdir -p "${TMP}/spawn"
cat >"${TMP}/spawn/herdr" <<SH
#!/usr/bin/env bash
echo "\$*" >>"${TMP}/herdr-called"
case "\$1 \$2" in
  "agent list")
    # Call one is the liveness question spawn asks before anything else, and it
    # answers empty so the spawn gets past it; call two is the detection loop,
    # which wants the pane that was just opened.
    n=\$(cat "${TMP}/list-calls" 2>/dev/null || echo 0)
    n=\$((n + 1))
    printf '%s\n' "\$n" >"${TMP}/list-calls"
    if [ "\$n" -ge 2 ]; then
      printf '{"result":{"agents":[{"name":"fixture","pane_id":"wT:p1","agent_status":"working"}]}}\n'
    else
      printf '{"result":{"agents":[]}}\n'
    fi
    ;;
  "worktree open")
    printf '{"result":{"workspace":{"workspace_id":"wT:t1","active_tab_id":"wT:t1"},"root_pane":{"pane_id":"wT:p1"},"already_open":false}}\n'
    ;;
  "tab rename" | "pane run" | "pane send-keys" | "agent rename") ;;
  *) exit 9 ;;
esac
exit 0
SH
chmod +x "${TMP}/spawn/herdr"

# The login shell as the check meets it: the answer from the probe file, or the
# failure of a shell that cannot give one. What it was asked goes to a record,
# because "the shell was never asked" is a property of no output.
cat >"${TMP}/spawn/zsh" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "\$3" "\$4" >>"${TMP}/zsh-called"
[ -f "${TMP}/probe" ] || exit 3
cat "${TMP}/probe"
SH
chmod +x "${TMP}/spawn/zsh"

# The real login shell, with the provider `ccd` names pointed at a ref of the
# case's choosing: appended last, so it wins the probe's lookup, and injected
# ahead of the script the probe is handed, so it lands after the rc files have
# had their say. Whatever this machine's providers.zsh says about ccd, the
# answer comes from the fixture — which is what lets a case about an empty key
# run without touching the developer's own.
REAL_ZSH="$(command -v zsh)"
mkdir -p "${TMP}/realzsh"
cat >"${TMP}/realzsh/zsh" <<SH
#!/usr/bin/env bash
[ "\$1" = "-ic" ] || exit 9
exec "${REAL_ZSH}" -ic "_cc_prov_names+=(herdr-fixture); _cc_prov[herdr-fixture:short]=ccd; _cc_prov[herdr-fixture:key]=\$FIXTURE_REF; \$2" "\${@:3}"
SH
chmod +x "${TMP}/realzsh/zsh"

# spawn_on <stub-dirs> <want-exit> <label> <args...> — one spawn against the
# stubs, with the records of what it called cleared first.
spawn_on() {
  local dirs="$1" want="$2" label="$3" code=0
  shift 3
  rm -f "${TMP}/list-calls" "${TMP}/herdr-called" "${TMP}/zsh-called"
  env PATH="${dirs}:${PATH}" "${TEAM}" spawn "$@" >"${TMP}/out" 2>"${TMP}/err" || code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  else
    ok "$label"
  fi
}

# 67. The defect, and the whole of it: an empty key. The refusal has to name the
#     variable, because "1Password locked" was a guess at a cause and a wrong
#     one — the variable is what the human has to export. The branch does not
#     exist and nothing may be created looking for it: the check runs before the
#     first mutating call, which is the only reason it can be trusted over the
#     launch it is protecting.
printf 'env:HERDR_FIXTURE_KEY HERDR_FIXTURE_KEY empty\n' >"${TMP}/probe"
spawn_on "${TMP}/spawn" 1 "67 an empty key fails the spawn" \
  exec-7 --branch fixture-t09-absent --provider ccd
if grep -q 'would launch with HERDR_FIXTURE_KEY empty' "${TMP}/err"; then
  ok "67b the refusal names the variable that was empty"
else
  no "67b the refusal names the variable that was empty" "$(tr '\n' '|' <"${TMP}/err")"
fi
if grep -qE 'worktree open|pane run|agent rename' "${TMP}/herdr-called"; then
  no "67c nothing was created before the check" "$(tr '\n' '|' <"${TMP}/herdr-called")"
else
  ok "67c nothing was created before the check"
fi

if wt_add s; then
  # 68. A key that is set, so the spawn gets past the check and does its work.
  printf 'env:HERDR_FIXTURE_KEY HERDR_FIXTURE_KEY set\n' >"${TMP}/probe"
  spawn_on "${TMP}/spawn" 0 "68 a set key spawns" \
    exec-7 --branch "${T05_BRANCH}-s" --provider ccd
  if grep -q 'pane run' "${TMP}/herdr-called" && grep -q 'agent rename' "${TMP}/herdr-called"; then
    ok "68b the pane was launched and the agent named"
  else
    no "68b the pane was launched and the agent named" "$(tr '\n' '|' <"${TMP}/herdr-called")"
  fi
  # The old check read the pane. This is the property that says it no longer
  # does, asserted over the calls the spawn actually made rather than the
  # source: a `read` that reached the pane by some other name would pass 73.
  if grep -q 'agent read' "${TMP}/herdr-called"; then
    no "68c the spawn reads no pane" "$(tr '\n' '|' <"${TMP}/herdr-called")"
  else
    ok "68c the spawn reads no pane"
  fi

  # 69. --skip-provider-check has to skip the question, not answer it: with a
  #     shell that cannot answer at all, the spawn proceeds and never asks.
  rm -f "${TMP}/probe"
  spawn_on "${TMP}/spawn" 0 "69 --skip-provider-check spawns on a shell that cannot answer" \
    exec-7 --branch "${T05_BRANCH}-s" --provider ccd --skip-provider-check
  if [ -s "${TMP}/zsh-called" ]; then
    no "69b the login shell was never asked" "$(tr '\n' '|' <"${TMP}/zsh-called")"
  else
    ok "69b the login shell was never asked"
  fi

  # 70. An op:// ref. Only the launch can resolve it, and it may ask 1Password
  #     while doing so, so the check cannot assert it — but it does know what it
  #     is looking at, and says so instead of leaving a pane to wait.
  printf 'op://Private/Thing/credential\n' >"${TMP}/probe"
  spawn_on "${TMP}/spawn" 0 "70 an op:// key does not fail the spawn" \
    exec-7 --branch "${T05_BRANCH}-s" --provider ccd
  if grep -q 'op:// ref' "${TMP}/err"; then
    ok "70b and the spawn warns that the pane resolves it itself"
  else
    no "70b and the spawn warns that the pane resolves it itself" "$(tr '\n' '|' <"${TMP}/err")"
  fi

  # 71/72. The acceptance, end to end and with no stub in the middle: a real zsh
  #     runs the probe team.sh actually sends it, and spawn splits what comes
  #     back. Empty fails, set succeeds.
  export HERDR_FIXTURE_PRESENT=fixture-value
  FIXTURE_REF=env:HERDR_FIXTURE_ABSENT spawn_on "${TMP}/realzsh:${TMP}/spawn" 1 \
    "71 the real login shell reports the key empty" \
    exec-7 --branch "${T05_BRANCH}-s" --provider ccd
  if grep -q 'would launch with HERDR_FIXTURE_ABSENT empty' "${TMP}/err"; then
    ok "71b and the refusal names the variable the real shell read"
  else
    no "71b and the refusal names the variable the real shell read" "$(tr '\n' '|' <"${TMP}/err")"
  fi
  FIXTURE_REF=env:HERDR_FIXTURE_PRESENT spawn_on "${TMP}/realzsh:${TMP}/spawn" 0 \
    "72 the real login shell reports the key set" \
    exec-7 --branch "${T05_BRANCH}-s" --provider ccd
  unset HERDR_FIXTURE_PRESENT

  git -C "${DOTFILES}" worktree remove --force "${WT}" 2>/dev/null
  git -C "${DOTFILES}" branch -D "${T05_BRANCH}-s" >/dev/null 2>&1
else
  sk "68 a set key spawns" "no throwaway worktree: $(head -1 "${TMP}/err")"
  sk "69 --skip-provider-check spawns on a shell that cannot answer" "no throwaway worktree"
  sk "70 an op:// key does not fail the spawn" "no throwaway worktree"
  sk "71 the real login shell reports the key empty" "no throwaway worktree"
  sk "72 the real login shell reports the key set" "no throwaway worktree"
fi

# 73. The mechanical half of the same property, and the one the plan asks for:
#     with no read of a pane anywhere in cmd_spawn there is no glyph left for a
#     spawn to be decided by. A body that went back to scraping the screen
#     would pass every case above by way of the stub and fail this one.
if [ "$(awk '/^cmd_spawn\(\)/,/^}/' "${TEAM}" | grep -c 'agent read')" -eq 0 ]; then
  ok "73 cmd_spawn reads no pane"
else
  no "73 cmd_spawn reads no pane" "the body calls agent read"
fi

# 73b. The same for the marker itself. `--skip-provider-check` stays as the
#      escape hatch, but nothing may still be waiting on a label that is not
#      rendered: that is the failure this Task exists to remove.
if grep -q 'CC_PROVIDER_LABEL' "${TEAM}"; then
  no "73b no provider label is left to poll for" "$(grep -n 'CC_PROVIDER_LABEL' "${TEAM}" | head -2 | tr '\n' '|')"
else
  ok "73b no provider label is left to poll for"
fi

echo "settle: reuse, and the one sanctioned clear"

# T-10. `settle <name> reuse --clear` is the one place team.sh sends keys to an
# agent that is not a Dispatch and not an answer to an approval dialog, so the
# cases below pin what it may send — `/clear` through `agent prompt`, the
# helper `dispatch` itself uses — and what it may not. The stub's `agent prompt`
# refuses a blocked agent without recording, the way the real one does, so the
# recordings before that point are what tell "asked and refused" apart from
# "never asked".
#
# The hazard no case here can see is a filesystem one: /clear does not touch
# the worktree, so uncommitted work survives while the agent's knowledge of why
# it is there does not, and a pane cleared over a dirty tree can rediscover its
# own edits and read them as someone else's. The mitigation is the Dispatch
# prompt's `Files in scope:` line — case 80 asserts it is in the prompt, so the
# connection is checked rather than left in a comment.
mkdir -p "${TMP}/settle"
cat >"${TMP}/settle/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/settle-called"
case "\$1 \$2" in
  "agent list")
    printf '{"result":{"agents":[{"name":"exec-1","pane_id":"wS:p1","agent_status":"%s"}]}}\n' "\$(cat "${TMP}/settle-status")"
    ;;
  "agent prompt")
    printf '%s\n' "\$*" >>"${TMP}/settle-prompt"
    # herdr agent prompt <TARGET> <TEXT>: the text is the fourth word, and
    # recording it apart from the argv is what says what was sent.
    if [ "\$(cat "${TMP}/settle-status")" = "blocked" ] ||
      [ -e "${TMP}/settle-refuse" ]; then exit 1; fi
    printf '%s\n' "\$4" >>"${TMP}/settle-sent"
    ;;
  "pane report-metadata")
    printf '%s\n' "\$*" >>"${TMP}/settle-meta"
    ;;
  "pane send-keys" | "pane run")
    printf '%s\n' "\$*" >>"${TMP}/settle-keys"
    ;;
  *) exit 9 ;;
esac
SH
chmod +x "${TMP}/settle/herdr"

# settle_on <status> <want-exit> <stdout-regex> <label> [args...] — `settle`
# against that stub, with the pane's agent in <status>. An empty regex checks
# the exit code only, which is the shape a refusal takes: `die` writes to stderr
# and leaves an empty stdout. Every recording is cleared first, so a case sees
# what this call did and not what an earlier one left behind.
#
# `refuse` is an idle pane whose herdr refuses the send: an agent settle's own
# pre-check cannot see, so the refusal has to come from the helper. That is the
# case where "the record was written after the clear" is the whole difference.
settle_on() {
  local status="$1" want="$2" re="$3" label="$4" code=0
  shift 4
  if [ "$status" = "refuse" ]; then
    printf 'idle\n' >"${TMP}/settle-status"
    : >"${TMP}/settle-refuse"
  else
    printf '%s\n' "$status" >"${TMP}/settle-status"
    rm -f "${TMP}/settle-refuse"
  fi
  rm -f "${TMP}/settle-called" "${TMP}/settle-prompt" "${TMP}/settle-sent" \
    "${TMP}/settle-meta" "${TMP}/settle-keys"
  env PATH="${TMP}/settle:${PATH}" "${TEAM}" settle "$@" >"${TMP}/out" 2>"${TMP}/err" ||
    code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# recorded <which> <whole-line-regex> <label> — the call left exactly one line
# in that recording and it matches. "One line and exactly this" is the only
# shape that says *what* was sent rather than that something was.
recorded() {
  local f="${TMP}/settle-$1" label="$3"
  if [ -f "$f" ] && [ "$(wc -l <"$f" | tr -d ' ')" -eq 1 ] && grep -qE "$2" "$f"; then
    ok "$label"
  else
    no "$label" "$(if [ -f "$f" ]; then tr '\n' '|' <"$f"; else echo 'nothing recorded'; fi)"
  fi
}

# untouched <which> <label> — that recording is absent, not empty: the call
# never reached that path at all.
untouched() {
  local f="${TMP}/settle-$1" label="$2"
  if [ -e "$f" ]; then
    no "$label" "recorded: $(tr '\n' '|' <"$f")"
  else
    ok "$label"
  fi
}

# asked <whole-line-regex> <label> — every herdr call this run made matches, so
# the stub was reached for what the case allows and nothing else. Vacuously
# true when herdr was never reached; the calls that matter are pinned by the
# recordings above.
asked() {
  local label="$2"
  if [ ! -f "${TMP}/settle-called" ] ||
    ! grep -vqE "$1" "${TMP}/settle-called"; then
    ok "$label"
  else
    no "$label" "herdr called with: $(tr '\n' '|' <"${TMP}/settle-called")"
  fi
}

# 74. The whole point of the flag: /clear goes to the pane, through the one
#     helper, and the record says so.
settle_on idle 0 'settled: reuse \(wS:p1, cleared\)' \
  "74 reuse --clear settles and says the pane was cleared" exec-1 reuse --clear
recorded sent '^/clear$' "74b /clear is all that was sent"
recorded prompt '^agent prompt exec-1 /clear$' \
  "74c and it went through the helper dispatch uses, addressed by name"
untouched keys "74d no send-keys and no pane run"
recorded meta '^pane report-metadata wS:p1 --source herdr-team --token settle=reuse,cleared=1$' \
  "74e the record names the decision and the clear"

# 75. Off by default in this Task, and off means nothing leaves the shell.
settle_on idle 0 'settled: reuse \(wS:p1\)$' "75 reuse without --clear settles" \
  exec-1 reuse
untouched prompt "75b and herdr was never asked to send anything"
recorded meta '^pane report-metadata wS:p1 --source herdr-team --token settle=reuse,cleared=0$' \
  "75c the record says this pane was not cleared"

# 76. A blocked agent is holding a question that exists nowhere else, so the
#     clear is refused before herdr is asked to send it.
settle_on blocked 1 '' "76 --clear refuses a blocked agent" exec-1 reuse --clear
if grep -q 'blocked on a question' "${TMP}/err" && grep -q 'team.sh surface exec-1' "${TMP}/err"; then
  ok "76a and the refusal names the reason and the remedy"
else
  no "76a and the refusal names the reason and the remedy" "$(head -2 "${TMP}/err" | tr '\n' '|')"
fi
untouched prompt "76b nothing was sent"
untouched meta "76c and no decision was recorded for a reuse that did not happen"
asked '^agent list$' "76d the only thing asked was who the agent is"

# 77/78. Clearing belongs to the reuse decision. A retain keeps the pane to be
#     read, and a release runs the teardown guards; neither has a context left
#     to clear, and neither may be cleared by a stray flag.
settle_on idle 1 '' "77 --clear is rejected on retain" exec-1 retain --clear
if grep -q 'clear is for reuse' "${TMP}/err"; then
  ok "77a and the refusal says which decision it belongs to"
else
  no "77a and the refusal says which decision it belongs to" "$(head -2 "${TMP}/err" | tr '\n' '|')"
fi
settle_on idle 1 '' "78 --clear is rejected on release" exec-1 release --clear
untouched called "78b and not one herdr call was made for it"

# 79. The mechanical half: whatever the stub answers, the body may not hold a
#     second way to a pane beside the one /clear. A settle that grew a
#     send-keys or a pane run would pass every case above by way of the stub.
if [ "$(awk '/^cmd_settle\(\)/,/^}/' "${TEAM}" | grep -c 'send-keys\|pane run')" -eq 0 ]; then
  ok "79 cmd_settle holds no other way to a pane"
else
  no "79 cmd_settle holds no other way to a pane" "the body reaches a pane twice"
fi
if [ "$(awk '/^cmd_settle\(\)/,/^}/' "${TEAM}" | grep -c 'herdr agent prompt')" -eq 1 ]; then
  ok "79b and exactly one send to the agent it names"
else
  no "79b and exactly one send to the agent it names" \
    "$(awk '/^cmd_settle\(\)/,/^}/' "${TEAM}" | grep -n 'herdr agent prompt' | tr '\n' '|')"
fi

# 80. The mitigation the hazard leans on, asserted where the hazard is written
#     down: a pane reused after a clear gets a Dispatch that names the files it
#     may touch, which is all that separates it from its own old edits.
reset
dispatch --task T-01 --from-plan "${FIXTURES}/plan-ok.md" >"${TMP}/out"
if grep -q '^Files in scope: ai/setup.sh$' "${TMP}/out"; then
  ok "80 the Dispatch a reused pane reads names its files in scope"
else
  no "80 the Dispatch a reused pane reads names its files in scope" \
    "$(grep -n 'scope' "${TMP}/out" | tr '\n' '|')"
fi

# 81. The decisions that were already there, so a flag cannot have moved them:
#     the non-clear path still settles, and its token still says so.
settle_on idle 0 'settled: retain for inspection \(wS:p1\)$' \
  "81 retain settles without --clear" exec-1 retain
recorded meta '^pane report-metadata wS:p1 --source herdr-team --token settle=retain,cleared=0$' \
  "81b and its record carries the decision and no clear"

# 82. The refusal that has to come from herdr, which is the one an ordering
#     mistake would decorate: a clear that did not happen is not a reuse that
#     was carried out, so the record has to come after the send and not before.
settle_on refuse 1 '' "82 a send herdr refuses is not a reuse" exec-1 reuse --clear
untouched sent "82b nothing reached the pane"
untouched meta "82c and no reuse is recorded for a pane still holding it"

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
