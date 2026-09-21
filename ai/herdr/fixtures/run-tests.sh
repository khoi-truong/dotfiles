#!/usr/bin/env bash
# run-tests.sh — the acceptance checks for `team.sh dispatch --from-plan`,
# `collect --plan`, `wait`, `report` and `teardown`.
#
# Static checks do not see inside team.sh's embedded python, and this
# repo has no test suite, so this script is the only thing that exercises the
# plan parser. Run it by hand after touching `plan_body`, `plan_rows`,
# `dispatched`, `journal_lines`, `unproven`, `cmd_wait`, `cmd_report` or the
# teardown guard:
#
#   bash ai/herdr/fixtures/run-tests.sh
#
# Every case points HERDR_TEAM_ROOT at a throwaway directory, so nothing here
# reads or writes the live .herdr/ — which would also shift the next-dispatch
# ids of a real Run. The `wait` cases drive herdr itself through stubs on PATH:
# a fixture run has no herdr session, and a case that cannot run is a skip, not
# a pass. The `teardown` cases go further and register a real throwaway worktree
# under ${TMP}: the guard is a `git` question, so a fixture that answered it
# would be testing the fixture.
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
OTHER="R-fixture-9999"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# The state root, and the key standing in for the tab driving it. Every case
# reads and writes ${HERDR_TEAM_ROOT} and nothing else, so a fixture run never
# touches the live .herdr/ — and the layout under test is the one `run new`
# writes: a directory per Run, and a pointer per key naming the Run a shell is
# in. The isolation cases at the end switch keys, the way a second tab would.
export HERDR_TEAM_ROOT="${TMP}/herdr"
# Cleared rather than merely overridden: a pane team.sh spawned carries an
# override of its own in the environment, so a case that inherited one would
# read the developer's handoff directory while reporting on a fixture Run. The
# case that is about the override sets it itself.
unset HERDR_TEAM_HANDOFFS
export HERDR_TEAM_RUN_KEY="tab-a"

# handoff_dir <run> — that Run's handoffs, which is where every fixture in this
# file is written and read from. team.sh answers the same question from its own
# root; this is the same path spelled out, so a case can place a file without
# asking the thing under test to agree with it.
handoff_dir() { printf '%s\n' "${HERDR_TEAM_ROOT}/runs/${1}/handoffs"; }

# run_dir <run> — that Run's own directory, which is where `report` leaves
# `report.json` and where `run new --plan` writes the plan down.
run_dir() { printf '%s\n' "${HERDR_TEAM_ROOT}/runs/${1}"; }

# pointer <key> — the file naming the Run that key's shell is in.
pointer() { printf '%s\n' "${HERDR_TEAM_ROOT}/state/run-${1:-tab-a}"; }

# use_run <run> [key] — the state `run new` leaves behind: that Run's handoff
# directory, and the pointer putting <key>'s shell in it. A fixed id rather
# than a minted timestamp, so a case can name the Run it wrote to; the cases
# about the verb itself ask the verb for theirs.
use_run() {
  mkdir -p "$(handoff_dir "$1")" "${HERDR_TEAM_ROOT}/state"
  printf '%s\n' "$1" >"$(pointer "${2:-tab-a}")"
}
use_run "${RUN}"
# The fixture Run's handoff directory, exported for the one stub that writes
# into it (case 44). A stub is a real process: it reads the environment the way
# team.sh does, and a variable known only to the suite's own shell would never
# reach it.
HERDR_FIXTURE_HANDOFFS="$(handoff_dir "${RUN}")"
export HERDR_FIXTURE_HANDOFFS

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

# handoff <task> <run> <outcome> <evidence> [dispatch] [commands] [artifacts] —
# one fixture handoff, in the directory that names its Run. `commands` is
# written verbatim after the colon: the default proves that task's plan-ok
# verify, `none` writes no commands line at all (absence is never evidence), and
# the wrong-command, non-zero-exit and pre-contract shapes are what the cases
# pass in. `artifacts` is the receipt line, absent unless a case asks for it.
handoff() {
  local task="$1" dir d="${5:-D-01}" cmds="" arts="${7:-}"
  if [ $# -ge 6 ]; then cmds="$6"; else cmds="$(proven "$task")"; fi
  dir="$(handoff_dir "$2")"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'run: %s\ntask: %s\ndispatch: %s\n' "$2" "$task" "$d"
    printf 'outcome: %s\nevidence: %s\n' "$3" "$4"
    [ "$cmds" = "none" ] || printf 'commands: %s\n' "$cmds"
    [ -z "$arts" ] || printf 'artifacts: %s\n' "$arts"
    printf -- '---\n\n## What was done\n\nFixture.\n'
  } >"${dir}/${task}-${d}.md"
}

# sent <run> <task> <dispatch> [agent] — one line in that Run's dispatch
# journal, standing in for a real `dispatch` that has not been answered yet. The
# agent is the fourth column `dispatch` writes; leaving it off writes the
# three-column shape an older journal still has on disk, which both verbs have
# to read.
sent() {
  local dir
  dir="$(handoff_dir "$1")"
  mkdir -p "$dir"
  if [ $# -ge 4 ]; then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${dir}/.dispatched"
  else
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"${dir}/.dispatched"
  fi
}

# plan_for <run> <plan-file> — the line `run new --plan` writes down, so a case
# can put a Run in front of `report` with the plan it was cut from and nothing
# in the case has to hand the plan over twice. The path is written as the
# fixture spells it; `report` opens what it reads, and its own copy of the
# resolved path is `run new`'s business, not this suite's.
plan_for() { printf '%s\n' "${FIXTURES}/${2}" >"$(run_dir "$1")/plan"; }

# long_handoff <task> <run> <dispatch> [pad] — a handoff with the frontmatter a
# case needs and a body padded past the 150-line cap protocol.md states. Its own
# helper rather than a flag on `handoff`, whose body is a fixed shape and whose
# whole point is that every case writes the same one.
long_handoff() {
  local task="$1" run="$2" d="${3:-D-01}" pad="${4:-160}" dir i=0
  dir="$(handoff_dir "$run")"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'run: %s\ntask: %s\ndispatch: %s\n' "$run" "$task" "$d"
    printf 'outcome: succeeded\nevidence: reported\n'
    printf 'commands: []\n'
    printf -- '---\n\n## What was done\n\n'
    while [ "$i" -lt "$pad" ]; do
      printf 'Padding, line %d.\n' "$i"
      i=$((i + 1))
    done
  } >"${dir}/${task}-${d}.md"
}

# reset — every Run gone, and the key back in the fixture one. The by-plan links
# go with them: a link left behind would silently answer `--plan` for a Run this
# case is not about, which is the one way a hand-built fixture can change what a
# later case is looking at.
reset() {
  rm -rf "${HERDR_TEAM_ROOT}/runs" "${HERDR_TEAM_ROOT}/state/panes"
  use_run "${RUN}"
}

# record <name> <provider> [run] [worktree] — one pane record, the shape `spawn`
# writes under state/panes/. A case places the records it wants counted rather
# than spawning the panes they describe: the ceiling is about how many panes
# hold one credential, and a case that had to spawn four real panes to stage
# that would be testing the spawn's worktrees instead.
record() {
  local dir="${HERDR_TEAM_ROOT}/state/panes"
  mkdir -p "$dir"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${3:--}" "${4:-${TMP}/wt-${1}}" \
    "2026-01-01T00:00:00Z" >"${dir}/${1}"
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
#    command. Normalised against a golden file: the plan path and the state root
#    are absolute and machine-specific — the root's, not the handoff
#    directory's, because the Run is named inside it and the golden should show
#    which Run the prompt is addressed to.
rm -f "$(handoff_dir "${RUN}")"/*.md
dispatch --task T-01 --from-plan "${FIXTURES}/plan-ok.md" >"${TMP}/out"
sed -e "s#${FIXTURES}#<FIXTURES>#g" -e "s#${HERDR_TEAM_ROOT}#<ROOT>#g" \
  "${TMP}/out" >"${TMP}/norm"
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
  cp "${TMP}/norm" "${FIXTURES}/golden/T-01-dispatch.prompt"
  ok "1b the golden prompt was rewritten from this run"
elif diff -u "${FIXTURES}/golden/T-01-dispatch.prompt" "${TMP}/norm" >"${TMP}/diff"; then
  ok "1 unblocked dispatch matches the golden prompt"
else
  no "1 unblocked dispatch matches the golden prompt" "$(head -20 "${TMP}/diff")"
fi

# 2. A blocker with no handoff at all.
reset
expect_exit 3 "2 blocked when the blocker has no handoff" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 3. The Run-scoping case: a verified handoff for T-01 under a *different* Run.
#    The filename carries only the Task and the Dispatch — both of which restart
#    every Run — so this is the case that silently unblocks if the gate reads
#    the wrong directory, or trusts the name it found there. Case 100 is the
#    same claim with the file *inside* this Run's directory.
reset
handoff T-01 "R-fixture-9999" succeeded verified
expect_exit 3 "3 blocked when the only verified handoff is another Run's" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 4. succeeded but only reported: a claim, not a result.
reset
handoff T-01 "${RUN}" succeeded reported
expect_exit 3 "4 blocked when the blocker is succeeded/reported" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 5. succeeded and verified, this Run.
reset
handoff T-01 "${RUN}" succeeded verified
expect_exit 0 "5 ready when the blocker is verified under this Run" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 6. --force is the human-gated escape.
reset
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
reset
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

# 12. No Run at all is a precondition failure, not an empty report. The key's
#     pointer is the only thing that names one here: this plan started no Run of
#     its own, so there is no by-plan link to fall back on either.
reset
mv "$(pointer)" "${TMP}/run.away"
expect_collect 1 "" "12 --plan with no Run exits 1" --plan "${FIXTURES}/plan-ok.md"
mv "${TMP}/run.away" "$(pointer)"

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

# 27b. Two rows under one id. Everything else about the plan is well-formed —
#      the section exists, nothing dangles — so nothing but this check stands
#      between the plan and two panes on one section.
expect_lint 1 'has two rows for T-01: one Task, one row' \
  "27b two rows under one task id" plan-dupe.md

# 28. The passing case. plan-ok's piped verify leads with `set -o pipefail`,
#     which is exactly the shape the check is meant to allow.
expect_lint 0 ': ok$' "28 a well-formed plan passes" plan-ok.md

# 29. Every finding in one run — the whole reason plan_rows returns them
#     rather than raising on the first. The plan-shape line every lint now ends
#     with is counted out rather than expected: this case is about the findings,
#     and the shape line has cases of its own below.
"${TEAM}" plan lint "${FIXTURES}/plan-many.md" >"${TMP}/out" 2>/dev/null
if [ "$(grep -vcE '^depth [0-9]+  width [0-9]+  tasks [0-9]+$' "${TMP}/out")" -eq 3 ]; then
  ok "29 a plan with three problems reports all three"
else
  no "29 a plan with three problems reports all three" \
    "got $(tr '\n' '|' <"${TMP}/out")"
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
mkdir -p "${TMP}/poison" "${TMP}/idle" "${TMP}/stuck" "${TMP}/error" \
  "${TMP}/ghost" "${TMP}/vanish"
# Fails and records the call, so a `wait` that reaches herdr when it must not
# fails loudly instead of quietly passing.
cat >"${TMP}/poison/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/herdr-called"
exit 1
SH
# `wait` looks every outstanding agent up before it blocks on one (T-01), so a
# stub that does not answer the listing is a precondition failure rather than
# the behaviour its case is named for. idle, stuck and error therefore share
# this answer — the journal's two agents, both live — and differ only in what
# `agent wait` does, which is the axis those cases are about.
LIVE='{"result":{"agents":[{"name":"exec-1","pane_id":"wM:p1","agent_status":"idle"},{"name":"exec-2","pane_id":"wM:p2","agent_status":"idle"}]}}'
# Returns at once, the way a pane that just reached a terminal state does.
cat >"${TMP}/idle/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list") printf '%s\n' '$LIVE' ;;
  *) exit 0 ;;
esac
SH
# Never returns: an agent that has not settled while the caller is watching.
# The listing still answers, so the case measures the clock and not the lookup.
cat >"${TMP}/stuck/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list") printf '%s\n' '$LIVE' ;;
  *) exec sleep 300 ;;
esac
SH
# Fails at once without matching, and the agent is live all the same: herdr's
# exit code is not a report on the pane's state, which is why `wait` asks the
# agent rather than reading the settle out of the wait. Case 41 is the point of
# the split — non-zero wait, readable status, settled.
cat >"${TMP}/error/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list") printf '%s\n' '$LIVE' ;;
  *) exit 3 ;;
esac
SH
# The precondition, from the other side: a journal naming an agent herdr has
# never heard of. exec-7 is not in the listing, so the outstanding Dispatch
# cannot be watched at all — and `agent wait` records the call, so a `wait`
# that blocks on the agent anyway is a failure here rather than a hang.
cat >"${TMP}/ghost/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list") printf '%s\n' '$LIVE' ;;
  "agent wait") printf '%s\n' "\$*" >>"${TMP}/ghost-waited"; exit 1 ;;
  *) exit 9 ;;
esac
SH
# The race the empty-status check exists for: the agent resolves when `wait`
# looks the outstanding Dispatch up, and is gone by the time the winner is
# asked how it ended. Staged off the wait rather than by counting listings, so
# the marker lands after the precondition however many times that reads.
cat >"${TMP}/vanish/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list")
    if [ -e "${TMP}/vanish-seen" ]; then
      printf '{"result":{"agents":[]}}\n'
    else
      printf '%s\n' '$LIVE'
    fi
    ;;
  "agent wait")
    : >"${TMP}/vanish-seen"
    exit 1
    ;;
  *) exit 9 ;;
esac
SH
chmod +x "${TMP}/poison/herdr" "${TMP}/idle/herdr" "${TMP}/stuck/herdr" \
  "${TMP}/error/herdr" "${TMP}/ghost/herdr" "${TMP}/vanish/herdr"

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
  >"${HERDR_FIXTURE_HANDOFFS}/T-01-D-01.md"
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

# 38. No Run and no pointer: a precondition failure, like every other verb.
reset
mv "$(pointer)" "${TMP}/run.away"
wait_on poison 1 "" "38 wait with no Run exits 1"
mv "${TMP}/run.away" "$(pointer)"

# 39. A journal line this code cannot read is a Dispatch it cannot watch.
#     Skipping it would let a wait outlive the work it was started for.
reset
printf '%s\tT-01\n' "${RUN}" >>"$(handoff_dir "${RUN}")/.dispatched"
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
#     on a match and on an expiry are not documented as distinguishable. The
#     stub's listing names the agent and says idle, so this is also T-01's
#     decision pinned rather than its bug: a failing wait over a readable
#     `idle` status is exit 0 and a settle, because the status is what decides
#     and the exit code is not.
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
#      idle is 0 and says settled. A stub that answers *no* status is a third
#      shape, and since T-01 it is a third answer too: 45f and 45i cover it as
#      an exit 1, so the empty answer no longer stands in for a settle here —
#      every stub in this section answers a listing now.
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

# 45f. A journal naming an agent herdr has never heard of: the Dispatch cannot
#      be watched at all, and that is a precondition failure, not a settle and
#      not a quiet 3. `collect --plan` counts the row because the journal says
#      so, so the two verbs would disagree about what is out until someone read
#      the table — which is why the refusal names that reader.
reset
sent "${RUN}" T-01 D-01 exec-7
rm -f "${TMP}/ghost-waited"
wait_on ghost 1 "" "45f an agent herdr does not know exits 1" --timeout 5000
if grep -qE 'exec-7' "${TMP}/err" && grep -q 'collect --plan' "${TMP}/err"; then
  ok "45g the refusal names the agent and the reader that still reports it"
else
  no "45g the refusal names the agent and the reader that still reports it" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi
if [ ! -e "${TMP}/ghost-waited" ]; then
  ok "45h herdr was never blocked on the unresolved agent"
else
  no "45h herdr was never blocked on the unresolved agent" \
    "agent wait called with: $(tr '\n' '|' <"${TMP}/ghost-waited")"
fi

# 45i. The race the empty-status check exists for: the agent resolves when the
#      outstanding Dispatch is looked up and is gone by the time the winner is
#      asked how it ended. Nothing on disk says how the Dispatch ended, so the
#      honest answer is 1 — the settle this used to print is the defect.
reset
sent "${RUN}" T-01 D-01 exec-1
wait_on vanish 1 "" "45i an agent that is gone when it is asked exits 1, not 0" --timeout 5000
if grep -q 'undecided' "${TMP}/err" && [ "$(grep -c 'settled' "${TMP}/out")" -eq 0 ]; then
  ok "45j the undecided Dispatch says so and prints no settle"
else
  no "45j the undecided Dispatch says so and prints no settle" \
    "err: $(tr '\n' '|' <"${TMP}/err") out: $(tr '\n' '|' <"${TMP}/out")"
fi

echo
echo "verify ↔ commands:"

# One `commands:` shape per case. Each is the string a handoff puts after
# `commands: ` — the default, which proves plan-ok's verify, is case 46 — or,
# for the block-list shapes, what it puts under it: the value `handoff` writes
# verbatim, leading newline and all.
BAD_EXIT='[{"cmd": "shellcheck -x ai/setup.sh", "exit": 1}]'
OTHER_CMD='[{"cmd": "shellcheck -x README.md", "exit": 0}]'
PRE_CONTRACT='[{cmd: "shellcheck -x ai/setup.sh", exit: 0}]'
BLOCK_CMDS='
  - cmd: "shellcheck -x ai/setup.sh"
    exit: 0'
FLUSH_CMDS='
- cmd: "shellcheck -x ai/setup.sh"
  exit: 0'
NO_EXIT_CMDS='
  - cmd: "shellcheck -x ai/setup.sh"'
STRAY_CMDS='
  - shellcheck -x ai/setup.sh'
ROOTED_CMDS='
  - cmd: "set -o pipefail; npx markdownlint-cli2 /opt/checkout/README.md | tail -1"
    exit: 0'
OTHER_PATH_CMDS='
  - cmd: "set -o pipefail; npx markdownlint-cli2 /opt/checkout/OTHER.md | tail -1"
    exit: 0'

# 46. The contract holding: the handoff names the row's verify at exit 0.
reset
handoff T-01 "${RUN}" succeeded verified D-01
expect_collect 0 '^T-01 +done +D-01' "46 a proved verify is done" \
  --plan "${FIXTURES}/plan-ok.md"

# 46b. The same claim in the other shape. The frontmatter is a YAML document
#      and a list in one is written as a block list, which is what the agent
#      that found this wrote: a `cc` pane's handoff carrying valid YAML, the
#      same data, and — before this — UNPARSED, downgrading a Task whose verify
#      demonstrably passed to `review`.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "${BLOCK_CMDS}"
expect_collect 0 '^T-01 +done +D-01' "46b a block-list commands: proves the verify too" \
  --plan "${FIXTURES}/plan-ok.md"

# 46c. The same block list at the key's own column. YAML allows both and an
#      agent writing by hand produces either, so both read the same here.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "${FLUSH_CMDS}"
expect_collect 0 '^T-01 +done +D-01' \
  "46c a block list at the key's own column reads the same" --plan "${FIXTURES}/plan-ok.md"

# 46d. An entry with no exit: code. Widening the contract to a second shape is
#      not weakening it — the pair of fields is still what proves a claim, so
#      this is UNVERIFIED rather than done, exactly as case 47 is.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "${NO_EXIT_CMDS}"
expect_collect 0 '^T-01 +review +D-01 +UNVERIFIED' \
  "46d a block-list entry with no exit: reads UNVERIFIED" --plan "${FIXTURES}/plan-ok.md"

# 46e. The one argument spelled from the root. plan-ok's T-02 verify names
#      `README.md`; T-05's handoff — the real one this task was found in — ran
#      the same command with the plan's path absolute, because `.omc/` is not in
#      the worktree the executor was standing in. The check cannot know the two
#      spellings name one file; it accepts a token that extends the verify's
#      token, which is the loosest reading that still has to match every word.
reset
handoff T-01 "${RUN}" succeeded verified
handoff T-02 "${RUN}" succeeded verified D-01 "${ROOTED_CMDS}"
expect_collect 3 '^T-02 +done +D-01' \
  "46e a path spelled from the root still names the verify" --plan "${FIXTURES}/plan-ok.md"

# 46f. The limit of 46e: a path that does not end in the file the verify names
#      is a different command, and proves nothing. Without this the widening
#      would be "any command with a path in it".
reset
handoff T-01 "${RUN}" succeeded verified
handoff T-02 "${RUN}" succeeded verified D-01 "${OTHER_PATH_CMDS}"
expect_collect 0 '^T-02 +review +D-01 +UNVERIFIED' \
  "46f a different path is not the verify" --plan "${FIXTURES}/plan-ok.md"

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

# 50b. A block list, but of strings rather than of the objects the contract
#      names: a shape this reader does not know. Accepting a second shape that
#      is spelled out is not accepting a third that is not — the agent that
#      wrote this meant something, and a human has to look at it.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "${STRAY_CMDS}"
expect_collect 0 '^T-01 +review +D-01 +UNPARSED' "50b a block list of strings is UNPARSED" \
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
#     one line, and a value json.loads accepts. The one-line shape is a choice,
#     not a limit of the reader — 46b is the same claim carried as a block list,
#     and 53b is the prompt telling the agent it may write either.
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

# 53b. The other half of the fix. A reader that accepts the shape an agent
#      writes is only half a contract; the prompt has to say the shape is
#      accepted, where the agent writing the handoff will read it. Case 1 diffs
#      the emitted prompt against this file, so what is asserted here is what
#      the next pane is handed.
GOLDEN="${FIXTURES}/golden/T-01-dispatch.prompt"
if grep -q '^  commands:$' "${GOLDEN}" &&
  grep -q '^    - cmd: "\.\.\."$' "${GOLDEN}" &&
  grep -q '^      exit: 0$' "${GOLDEN}" &&
  grep -q '^  files_changed:$' "${GOLDEN}" &&
  grep -q 'The list fields' "${GOLDEN}"; then
  ok "53b the prompt states the block list beside the inline shape"
else
  no "53b the prompt states the block list beside the inline shape" \
    "$(grep -c 'block list' "${GOLDEN}") mention(s) of a block list"
fi

# 53c. Every list field at once, as T-05's handoff has them: the frontmatter a
#      `cc` agent actually wrote, read without a rewrite, `files_changed:`
#      included — no reader prints that field, and the point is that carrying
#      it does not cost the row its done.
reset
{
  printf -- '---\n'
  printf 'run: %s\ntask: T-01\ndispatch: D-01\n' "${RUN}"
  printf 'outcome: succeeded\nevidence: verified\n'
  printf 'files_changed:\n  - ai/setup.sh\n  - README.md\n'
  printf 'artifacts:\n  - .omc/research/one.md\n'
  printf 'commands:\n  - cmd: "shellcheck -x ai/setup.sh"\n    exit: 0\n'
  printf -- '---\n\n## What was done\n\nFixture.\n'
} >"$(handoff_dir "${RUN}")/T-01-D-01.md"
expect_collect 0 '^T-01 +done +D-01 .*artifacts: \.omc/research/one\.md' \
  "53c every list field as a block list reads done" --plan "${FIXTURES}/plan-ok.md"

echo
echo "one handoff, one verdict"

# 53d-53j. The block-list shape, and the verdict both readers have to reach.
# `commands:` and `artifacts:` empty on their own line, one `- ` item per value:
# what an agent writes once a value stops fitting on one line. The parser
# normalises it into the inline form every reader below already takes, so the
# two spellings are one handoff — and the gate and `collect --plan`, which read
# one file, cannot answer differently about it.
INLINE_CMDS='[{"cmd": "shellcheck -x ai/setup.sh", "exit": 0}, {"cmd": "git status --short", "exit": 0}]'
BLOCK_CMDS=$'\n  - {"cmd": "shellcheck -x ai/setup.sh", "exit": 0}\n  - {"cmd": "git status --short", "exit": 0}'
BLOCK_ARTS=$'\n  - /abs/path.md'

# 53i. The block list proves the row's verify, and its receipt prints.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$BLOCK_CMDS" "$BLOCK_ARTS"
expect_collect 0 '^T-01 +done +D-01 .*artifacts: /abs/path\.md' \
  "53i a block-list commands: proves the verify to collect --plan" \
  --plan "${FIXTURES}/plan-ok.md"

# 53j. And the same handoff releases the dependent, through the gate.
expect_exit 0 "53j and the same handoff releases the dependent in dispatch" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 53d. Same two commands, written inline, read the same — the normalisation
#      joins the items in order, so a second item is a second entry and not a
#      lost one.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$INLINE_CMDS"
expect_collect 0 '^T-01 +done +D-01' "53d and the inline spelling of the same list agrees" \
  --plan "${FIXTURES}/plan-ok.md"

# 53e. Leniency, because the line arrives through an agent: a deeper indent and
#      a quoted item are the same list. A parser holding to the template's exact
#      shape would read this as UNVERIFIED and hold a Task that did its check.
reset
handoff T-01 "${RUN}" succeeded verified D-01 \
  "$(printf '\n    -  %s' "'{\"cmd\": \"shellcheck -x ai/setup.sh\", \"exit\": 0}'")"
expect_collect 0 '^T-01 +done +D-01' "53e an indented, quoted block list reads the same" \
  --plan "${FIXTURES}/plan-ok.md"

# 53f. The defect this section exists for: a handoff whose commands do not carry
#      the row's verify. The table has always called that `review`; the gate asked
#      only for `succeeded`/`verified` and released the dependent on the agent's
#      word — two readers, one file, opposite verdicts.
reset
handoff T-01 "${RUN}" succeeded verified D-01 "$OTHER_CMD"
expect_collect 0 '^T-01 +review +D-01 +UNVERIFIED' \
  "53f an unproven handoff reads review in collect --plan" \
  --plan "${FIXTURES}/plan-ok.md"
expect_exit 3 "53g and the gate refuses the dependent too" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

# 53h. The escape hatch survives the stricter gate: --force is still the
#      human-gated way past a blocker the table will not call done.
expect_exit 0 "53h --force still dispatches over an unproven blocker" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md" --force

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
    # A pane that lost its name is not in the list at all: that is what
    # agent_field reads as empty, and what the settle-lose-name marker arms. The
    # resolve of the pane happens before any rename, so a case that arms it
    # still gets a pane to clear.
    if [ -e "${TMP}/settle-nameless" ]; then
      printf '{"result":{"agents":[]}}\n'
    else
      printf '{"result":{"agents":[{"name":"exec-1","pane_id":"wS:p1","agent_status":"%s"}]}}\n' "\$(cat "${TMP}/settle-status")"
    fi
    ;;
  "agent prompt")
    printf '%s\n' "\$*" >>"${TMP}/settle-prompt"
    # herdr agent prompt <TARGET> <TEXT>: the text is the fourth word, and
    # recording it apart from the argv is what says what was sent.
    if [ "\$(cat "${TMP}/settle-status")" = "blocked" ] ||
      [ -e "${TMP}/settle-refuse" ]; then exit 1; fi
    printf '%s\n' "\$4" >>"${TMP}/settle-sent"
    ;;
  "agent rename")
    # The stub has no terminal title, so it cannot lose a name the way a real
    # pane does. What it can do is record the call — which is the only thing a
    # case can assert about a fix whose defect is invisible here — and refuse
    # one when the case asks it to.
    printf '%s\n' "\$*" >>"${TMP}/settle-rename"
    [ ! -e "${TMP}/settle-rename-fail" ] || exit 1
    # The settle-lose-name marker is the race itself: the rename is accepted,
    # and the title reset it is racing lands right after it, so the pane drops
    # out of agent list and stays out however many times it is renamed.
    if [ -e "${TMP}/settle-lose-name" ]; then : >"${TMP}/settle-nameless"; fi
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
# `norename` is its counterpart one call later — the send lands and the name
# will not come back. `lose` is the race itself: the rename is taken and the
# title reset undoes it, so the pane goes nameless and stays that way.
#
# A case may shorten the confirmation's deadline for its own run by prefixing
# the call — `HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT=2 settle_on lose ...` — the way
# case 96 raises the executor cap. The default is 15s, so the one case that
# reaches it would otherwise spend that long failing on purpose.
settle_on() {
  local status="$1" want="$2" re="$3" label="$4" code=0
  shift 4
  rm -f "${TMP}/settle-refuse" "${TMP}/settle-rename-fail" \
    "${TMP}/settle-lose-name" "${TMP}/settle-nameless"
  case "$status" in
    refuse)
      printf 'idle\n' >"${TMP}/settle-status"
      : >"${TMP}/settle-refuse"
      ;;
    norename)
      printf 'idle\n' >"${TMP}/settle-status"
      : >"${TMP}/settle-rename-fail"
      ;;
    lose)
      printf 'idle\n' >"${TMP}/settle-status"
      : >"${TMP}/settle-lose-name"
      ;;
    *)
      printf '%s\n' "$status" >"${TMP}/settle-status"
      ;;
  esac
  rm -f "${TMP}/settle-called" "${TMP}/settle-prompt" "${TMP}/settle-sent" \
    "${TMP}/settle-meta" "${TMP}/settle-keys" "${TMP}/settle-rename"
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

# T-11. /clear resets the pane's terminal title, and the title is what carries
# the `agent rename` `spawn` bound — so the clear unbound it, the pane stayed
# alive and idle with no name, and the next `dispatch exec-1` died with "no live
# agent named exec-1" until the rename was typed by hand. The stub has no title
# to lose, which is exactly why nothing here caught it: the case below asserts
# the *call*, the same shape T-09's provider check uses for a fact no fixture
# can observe. Order is asserted too, because a rename issued before the send
# would be undone by the very thing it is meant to survive.

# 83. The fix, and the only property a fixture can hold on to.
settle_on idle 0 'settled: reuse \(wS:p1, cleared\)' \
  "83 reuse --clear settles with the name put back" exec-1 reuse --clear
recorded rename '^agent rename wS:p1 exec-1$' "83b the name is re-asserted on the pane"
if [ "$(awk '/^agent prompt exec-1 \/clear$/ { p=NR } /^agent rename wS:p1 exec-1$/ { r=NR }
              END { print (p && r && p < r) ? "after" : "wrong" }' "${TMP}/settle-called")" = "after" ]; then
  ok "83c and it follows the clear rather than preceding it"
else
  no "83c and it follows the clear rather than preceding it" \
    "$(tr '\n' '|' <"${TMP}/settle-called")"
fi
asked '^(agent list|agent prompt exec-1 /clear|agent rename wS:p1 exec-1|pane report-metadata wS:p1 --source herdr-team --token settle=reuse,cleared=1)$' \
  "83d and the clear, the rename and the record are all it did"
# 83e. The confirmation, which is the half of 83 the recordings cannot see: the
#      pane is read back twice *after* the rename. A settle that assumed the
#      binding — or confirmed it before renaming — leaves four reads without
#      that ordering, and the count is what separates the exit code, which is 0
#      either way, from the work. Four is the two reads a clear already makes
#      (who the agent is, whether it is blocked) plus the confirming pair.
if [ "$(grep -c '^agent list$' "${TMP}/settle-called")" -eq 4 ] &&
  [ "$(awk '/^agent rename wS:p1 exec-1$/ { r=NR } /^agent list$/ { l=NR }
              END { print (r && l > r) ? "after" : "wrong" }' "${TMP}/settle-called")" = "after" ]; then
  ok "83e and the pane is read back twice after the rename"
else
  no "83e and the pane is read back twice after the rename" \
    "$(tr '\n' '|' <"${TMP}/settle-called")"
fi

# 84. The rename belongs to the clear and not to reuse: a pane whose transcript
#     is intact keeps the name it already has, untouched.
settle_on idle 0 'settled: reuse \(wS:p1\)$' "84 reuse without --clear still settles" exec-1 reuse
untouched rename "84b and asks herdr to rename nothing"

# 85. The state T-11 is about, reached the other way: the pane was cleared and
#     the name did not come back. Nothing is recorded — not `cleared=1`, which
#     would say a nameless pane is ready for the next Dispatch, and not the
#     decision either, because the reuse was not carried out.
settle_on norename 1 '' "85 a rename herdr refuses is not a reuse" exec-1 reuse --clear
if grep -q 'take the name back' "${TMP}/err" &&
  grep -q 'agent rename wS:p1 exec-1' "${TMP}/err"; then
  ok "85b and the refusal says which pane, and the command that fixes it"
else
  no "85b and the refusal says which pane, and the command that fixes it" \
    "$(head -2 "${TMP}/err" | tr '\n' '|')"
fi
if grep -q 'cleared=1' "${TMP}/settle-meta" 2>/dev/null; then
  no "85c no cleared=1 is recorded" "$(tr '\n' '|' <"${TMP}/settle-meta")"
else
  ok "85c no cleared=1 is recorded"
fi
untouched meta "85d and no decision at all, for a pane that lost its name"
recorded sent '^/clear$' "85e the clear itself did go out first"

# T-02. The race 85 cannot reach, because 85's stub refuses the rename: here
# herdr *takes* it and the title reset the clear already put in flight undoes it
# a beat later. That is the shape the live failure had — the rename returned 0,
# the pane went nameless, and the next `dispatch` died on the name. Nothing
# orders the two processes, so the answer is to read the binding back, and the
# only interesting question is what happens when the read says no.
#
# The deadline is shortened for the case: reaching it is the point, and 15s of
# waiting to reach a failure whose shape is known buys nothing. What the case
# asserts is the shape — non-zero, nothing recorded, a remedy named — not how
# long the pane was given to prove itself.

# 85f. The name does not hold, so the reuse did not happen.
HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT=2 settle_on lose 1 '' \
  "85f a name that does not hold is not a reuse" exec-1 reuse --clear
if grep -q 'would not hold' "${TMP}/err" &&
  grep -q 'agent rename wS:p1 exec-1' "${TMP}/err"; then
  ok "85g and the refusal says which pane, and the command that fixes it"
else
  no "85g and the refusal says which pane, and the command that fixes it" \
    "$(head -2 "${TMP}/err" | tr '\n' '|')"
fi
if grep -q 'settled' "${TMP}/out"; then
  no "85h no settle is printed for a pane it could not bind" "$(tr '\n' '|' <"${TMP}/out")"
else
  ok "85h no settle is printed for a pane it could not bind"
fi
untouched meta "85i and no decision, and no cleared=1, is recorded for it"
# 85j. The retry, which is what separates a confirmed binding from a rename that
#      happened to return 0: a failed pair re-renames and re-reads rather than
#      giving up on the first read.
if [ -f "${TMP}/settle-rename" ] &&
  [ "$(grep -c '^agent rename wS:p1 exec-1$' "${TMP}/settle-rename")" -ge 2 ]; then
  ok "85j and the rename goes out again when a pair fails"
else
  no "85j and the rename goes out again when a pair fails" \
    "$(if [ -f "${TMP}/settle-rename" ]; then tr '\n' '|' <"${TMP}/settle-rename"; else echo 'nothing recorded'; fi)"
fi
# 85k. And the deadline is the source's to set, which is what lets this case run
#      at all: the constant is the default, the environment is the override. Two
#      greps rather than one pattern, so the dollar sign of the expansion never
#      has to sit inside a single-quoted string where shellcheck reads it as a
#      mistake rather than as the literal being matched.
if grep -q '^CLEAR_CONFIRM_TIMEOUT=' "${TEAM}" &&
  grep -q 'HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT:-15' "${TEAM}"; then
  ok "85k the confirmation deadline defaults to 15s and is overridable"
else
  no "85k the confirmation deadline defaults to 15s and is overridable" \
    "$(grep -n 'CLEAR_CONFIRM_TIMEOUT=' "${TEAM}" | tr '\n' '|')"
fi

echo
echo "the state root: one Run per key"

# T-01's isolation, from the outside. Three tabs in one checkout used to share
# one Run pointer and one flat handoff namespace: two of them dispatching `T-01`
# wrote one filename between them, and the second was refused as already
# settled. What separates them now is the key — one pointer per shell, one
# directory per Run — and this section is those three tabs, driven by key from
# one shell because a fixture run has no panes.
rm -rf "${HERDR_TEAM_ROOT}/runs"

# new_run <key> [args...] — the real `run new` under that key, printing the id
# it minted. Every case above builds the layout by hand; these ask the verb that
# defines it, and the ids are timestamps because that is what the verb mints.
new_run() {
  local key="$1"
  shift
  HERDR_TEAM_RUN_KEY="$key" "${TEAM}" run new "$@" 2>"${TMP}/err" |
    sed -n 's/.*run \(R-[0-9]\{8\}-[0-9]\{6\}\)$/\1/p'
}

# dispatch_as <key> <file> <args...> — a dry-run Dispatch under that key's Run,
# its prompt going to <file>. No `--run`: which Run the Dispatch lands in is the
# question these cases are asking, so the key and the plan have to answer it.
dispatch_as() {
  local key="$1" file="$2"
  shift 2
  HERDR_TEAM_RUN_KEY="$key" "${TEAM}" dispatch exec-1 --dry-run "$@" 2>"${TMP}/err" >"$file"
}

# 86. Two keys, two Runs. The pointer is per key, so a second tab starting a Run
#     cannot take the first one's — and each key reads back its own.
RA="$(new_run tab-a)"
RB="$(new_run tab-b)"
if [ -n "$RA" ] && [ -n "$RB" ] && [ "$RA" != "$RB" ]; then
  ok "86 two keys mint two Runs"
else
  no "86 two keys mint two Runs" "tab-a: ${RA:-<none>} tab-b: ${RB:-<none>}"
fi
if [ "$(HERDR_TEAM_RUN_KEY=tab-a "${TEAM}" run show 2>/dev/null)" = "$RA" ] &&
  [ "$(HERDR_TEAM_RUN_KEY=tab-b "${TEAM}" run show 2>/dev/null)" = "$RB" ] &&
  [ -d "$(handoff_dir "$RA")" ] && [ -d "$(handoff_dir "$RB")" ]; then
  ok "86b run show answers each key with its own, and both have a handoff directory"
else
  no "86b run show answers each key with its own, and both have a handoff directory" \
    "a: ${RA:-<none>} b: ${RB:-<none>}"
fi

# 87. Both tabs dispatch T-01 as D-01. Task and Dispatch ids restart every Run,
#     so the same pair in two Runs is not a collision — and each prompt has to
#     name its own Run's handoff path, or a reused pane reads its neighbour's.
for key in tab-a tab-b; do
  case "$key" in tab-a) want="$RA" ;; *) want="$RB" ;; esac
  code=0
  dispatch_as "$key" "${TMP}/${key}.prompt" --task T-01 --from-plan "${FIXTURES}/plan-ok.md" ||
    code=$?
  if [ "$code" -ne 0 ]; then
    no "87 ${key} dispatches T-01/D-01 into its own Run" \
      "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif grep -q "^You are exec-1, working Task T-01 under Run ${want}\.$" "${TMP}/${key}.prompt" &&
    grep -q '^This is Dispatch D-01\.' "${TMP}/${key}.prompt" &&
    grep -q "${want}/handoffs/T-01-D-01\.md$" "${TMP}/${key}.prompt"; then
    ok "87 ${key} dispatches T-01/D-01 into its own Run"
  else
    no "87 ${key} dispatches T-01/D-01 into its own Run" \
      "$(grep -n 'Run \|Dispatch \|handoffs/' "${TMP}/${key}.prompt" | tr '\n' '|')"
  fi
done

# 88. The same Task and Dispatch id, settled in one Run and not in the other.
#     The handoff filename carries neither Run, so a Dispatch that only stat'd
#     the path would refuse the second tab; the Run's own directory decides,
#     and the id has to be named for the guard to be reached at all — an
#     unnamed id is minted free (88c).
handoff T-01 "$RB" succeeded verified
code=0
dispatch_as tab-b "${TMP}/b.prompt" --task T-01 --dispatch D-01 \
  --from-plan "${FIXTURES}/plan-ok.md" || code=$?
if [ "$code" -eq 1 ] && grep -q 'already settled' "${TMP}/err"; then
  ok "88 a Dispatch already settled under this Run is refused"
else
  no "88 a Dispatch already settled under this Run is refused" \
    "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi
code=0
dispatch_as tab-a "${TMP}/a.prompt" --task T-01 --dispatch D-01 \
  --from-plan "${FIXTURES}/plan-ok.md" || code=$?
if [ "$code" -eq 0 ] && grep -q '^This is Dispatch D-01\.' "${TMP}/a.prompt"; then
  ok "88b and the other Run's T-01/D-01 is not"
else
  no "88b and the other Run's T-01/D-01 is not" \
    "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi
# 88c. And an unnamed id is not refused: the next Dispatch of a Task is minted
#      from what this Run's own directory holds, so a settled D-01 makes D-02
#      rather than a collision.
code=0
dispatch_as tab-b "${TMP}/c.prompt" --task T-01 --from-plan "${FIXTURES}/plan-ok.md" || code=$?
if [ "$code" -eq 0 ] && grep -q '^This is Dispatch D-02\.' "${TMP}/c.prompt" &&
  grep -q "${RB}/handoffs/T-01-D-02\.md$" "${TMP}/c.prompt"; then
  ok "88c a settled D-01 makes the next Dispatch D-02, not a refusal"
else
  no "88c a settled D-01 makes the next Dispatch D-02, not a refusal" \
    "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi

# 89. A Run recovers from the plan path alone: the pointer can be gone — a
#     compacted context, a dead pane, a fresh shell — and the plan still names
#     the Run it started.
PLAN="${TMP}/iso-plan.md"
cp "${FIXTURES}/plan-ok.md" "$PLAN"
RC="$(new_run tab-c --plan "$PLAN")"
rm -f "$(pointer tab-c)"
if [ -n "$RC" ] && [ "$("${TEAM}" run resolve "$PLAN" 2>"${TMP}/err")" = "$RC" ]; then
  ok "89 run resolve recovers the Run from the plan after the pointer is gone"
else
  no "89 run resolve recovers the Run from the plan after the pointer is gone" \
    "want ${RC:-<none>}, got: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi

# 89b. A single answer, not the newest of several: a plan that already has a Run
#      is refused a second one, the id it has goes to stdout, and the key that
#      asked is left where it was.
code=0
out="$(HERDR_TEAM_RUN_KEY=tab-a "${TEAM}" run new --plan "$PLAN" 2>"${TMP}/err")" || code=$?
if [ "$code" -ne 0 ] && [ "$out" = "$RC" ] && grep -q 'already Run' "${TMP}/err" &&
  [ "$(cat "$(pointer tab-a)")" = "$RA" ]; then
  ok "89b a plan that already has a Run is refused a second, naming the one it has"
else
  no "89b a plan that already has a Run is refused a second, naming the one it has" \
    "exit ${code}, stdout ${out:-<none>}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi

# 90-94. `collect --plan` resolves its Run through by-plan — the caller named a
#      plan, so the plan names the Run — and every exit code it documents
#      survives that route. The key's pointer is left on Run A, which has
#      nothing under it: a table that is not empty is the proof the link won.
handoff T-01 "$RC" succeeded verified
expect_collect 0 '^T-01 +done +D-01' \
  "90 collect --plan reads the Run the plan started, not the key's" --plan "$PLAN"

handoff T-01 "$RC" succeeded verified D-02 "$(proven T-01)" '[/abs/path.md]'
expect_collect 0 '^T-01 +done +D-02 .*artifacts: /abs/path\.md' \
  "91 artifacts: is accepted, and the path is printed" --plan "$PLAN"
"${TEAM}" collect "$RC" >"${TMP}/out" 2>"${TMP}/err"
if grep -q 'artifacts: /abs/path\.md' "${TMP}/out"; then
  ok "91b and plain collect prints it too"
else
  no "91b and plain collect prints it too" "$(tr '\n' '|' <"${TMP}/out")"
fi

handoff T-02 "$RC" succeeded verified
expect_collect 3 '^T-02 +done' "92 and it still exits 3 when every Task is done" --plan "$PLAN"

handoff T-02 "$RC" failed tool_error
expect_collect 2 '^T-02 +failed' \
  "93 and still exits 2 when nothing is actionable and one failed" --plan "$PLAN"

printf 'not a handoff\n' >"$(handoff_dir "$RC")/broken.md"
expect_collect 1 '' "94 and still exits 1 on a handoff it cannot read" --plan "$PLAN"
rm -f "$(handoff_dir "$RC")/broken.md"

# 95. `wait` is scoped to its own Run. Run B has a Dispatch out and Run A has
#     nothing, so a wait under A returns 3 rather than blocking on B's work —
#     which is what lets two tabs each watch their own and neither stall on a
#     neighbour that never settles.
sent "$RB" T-01 D-02 exec-1
HERDR_TEAM_RUN_KEY=tab-a wait_on poison 3 "" \
  "95 wait under a Run with nothing out returns 3 while another Run works"
HERDR_TEAM_RUN_KEY=tab-b wait_on idle 0 '^exec-1 T-01 settled$' \
  "95b and the other key's wait watches its own Dispatch"

echo
echo "the two caps: one per Run, one per provider"

# 96. The per-Run cap, and the Run is the unit it counts. Two executors that
#     this Run dispatched are two worktrees it is carrying, so a third is
#     refused and the refusal names the panes to settle. Counted over the
#     journal — the record of what this Run sent out — so a pane belonging to
#     another tab is not this Run's to settle and not this Run's to be stopped
#     by. The stub is the whole environment: the refusal is reached before a
#     worktree or a pane exists, so the `worktree open` answer below is empty on
#     purpose — a regression that got this far would be rolled back rather than
#     left in the developer's repo.
mkdir -p "${TMP}/execap"
cat >"${TMP}/execap/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/herdr-called"
case "\$1 \$2" in
  "agent list")
    printf '{"result":{"agents":['
    printf '{"name":"exec-1","pane_id":"wX:p1","agent_status":"working"},'
    printf '{"name":"exec-2","pane_id":"wX:p2","agent_status":"working"}]}}\n'
    ;;
  "worktree open") printf '{"result":{}}\n' ;;
  *) exit 9 ;;
esac
SH
chmod +x "${TMP}/execap/herdr"

use_run "${RUN}"
sent "${RUN}" T-01 D-01 exec-1
sent "${RUN}" T-02 D-02 exec-2
HERDR_TEAM_EXEC_CAP=2 spawn_on "${TMP}/execap" 1 \
  "96 a third executor is refused while this Run holds two" \
  exec-3 --branch fixture-cap --provider ccd
if grep -q 'this Run already holds 2 executors (exec-1 exec-2)' "${TMP}/err" &&
  grep -q 'cap is 2 executors per Run' "${TMP}/err"; then
  ok "96b and the refusal names the Run's own executors, and the cap"
else
  no "96b and the refusal names the Run's own executors, and the cap" \
    "$(head -3 "${TMP}/err" | tr '\n' '|')"
fi
if grep -qE 'worktree open|pane run|agent rename' "${TMP}/herdr-called" 2>/dev/null; then
  no "96c nothing was created for a refused spawn" "$(tr '\n' '|' <"${TMP}/herdr-called")"
else
  ok "96c nothing was created for a refused spawn"
fi

# 97. A pane is not pinned to the Run that spawned it: `spawn` types the state
#     root into the pane's shell and no Run at all (98 asserts that), so the
#     Dispatch decides where a handoff goes. The same pane, dispatched under Run
#     B, writes into Run B's directory — and Run A gets nothing.
mkdir -p "${TMP}/dispatchable"
cat >"${TMP}/dispatchable/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "agent list")
    printf '{"result":{"agents":[{"name":"exec-1","pane_id":"wD:p1","agent_status":"idle"}]}}\n'
    ;;
  "agent prompt") printf '%s\n' "\$*" >>"${TMP}/prompted" ;;
  *) exit 9 ;;
esac
exit 0
SH
chmod +x "${TMP}/dispatchable/herdr"
rm -f "${TMP}/prompted"
code=0
env PATH="${TMP}/dispatchable:${PATH}" HERDR_TEAM_RUN_KEY=tab-b "${TEAM}" dispatch exec-1 \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md" >/dev/null 2>"${TMP}/err" || code=$?
row="$(printf '%s\t%s\t%s\t%s' "$RB" T-02 D-01 exec-1)"
if [ "$code" -eq 0 ] && grep -q "${RB}/handoffs/T-02-D-01\.md" "${TMP}/prompted" &&
  grep -qxF "$row" "$(handoff_dir "$RB")/.dispatched"; then
  ok "97 a Dispatch under Run B writes into Run B's directory"
else
  no "97 a Dispatch under Run B writes into Run B's directory" \
    "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ') $(tr '\n' '|' <"${TMP}/prompted" 2>/dev/null)"
fi
if [ -e "$(handoff_dir "$RA")/.dispatched" ]; then
  no "97b and nothing was written under the Run the pane was opened in" \
    "$(tr '\n' '|' <"$(handoff_dir "$RA")/.dispatched")"
else
  ok "97b and nothing was written under the Run the pane was opened in"
fi

# 98. The same property where a fixture cannot see it: what `spawn` types into a
#     pane's shell. A pane carrying one Run's handoff directory would write into
#     it for the rest of its life, which is the wrong Run the moment a retained
#     executor is reused — so the root goes in and a Run never does.
if [ "$(awk '/^cmd_spawn\(\)/,/^}/' "${TEAM}" | grep -c 'HERDR_TEAM_HANDOFFS')" -eq 0 ] &&
  [ "$(awk '/^cmd_spawn\(\)/,/^}/' "${TEAM}" | grep -c 'HERDR_TEAM_ROOT=')" -eq 1 ]; then
  ok "98 cmd_spawn exports the state root and no Run"
else
  no "98 cmd_spawn exports the state root and no Run" \
    "$(awk '/^cmd_spawn\(\)/,/^}/' "${TEAM}" |
      grep -n 'HERDR_TEAM_ROOT\|HERDR_TEAM_HANDOFFS' | tr '\n' '|')"
fi

# 99. The escape hatch this suite itself used to rest on, kept honest now that
#     nothing here needs it: HERDR_TEAM_HANDOFFS still answers for one Run, so a
#     test run can point a single Run at a throwaway directory.
mkdir -p "${TMP}/override"
code=0
out="$(HERDR_TEAM_HANDOFFS="${TMP}/override" "${TEAM}" dispatch exec-1 --run "$RA" --dry-run \
  --task T-01 --from-plan "${FIXTURES}/plan-ok.md" 2>"${TMP}/err")" || code=$?
if [ "$code" -eq 0 ] && printf '%s' "$out" | grep -q "${TMP}/override/T-01-D-01\.md"; then
  ok "99 HERDR_TEAM_HANDOFFS still overrides one Run's handoff directory"
else
  no "99 HERDR_TEAM_HANDOFFS still overrides one Run's handoff directory" \
    "exit ${code}: $(printf '%s' "$out" | grep -n 'handoffs/' | tr '\n' '|')"
fi

# 100. The redundant half of the scoping, and the reason it stays. A handoff
#      *placed* in this Run's directory that names another Run — a file moved by
#      hand, a directory copied, a migration gone wrong — must not unblock
#      anything: the directory says where a handoff is, and the frontmatter is
#      the only thing that says which Run it is about.
mkdir -p "$(handoff_dir "${RUN}")"
printf -- '---\nrun: %s\ntask: T-01\ndispatch: D-01\noutcome: succeeded\nevidence: verified\n---\n\n## What was done\n\nFixture.\n' \
  "${OTHER}" >"$(handoff_dir "${RUN}")/T-01-D-01.md"
expect_exit 3 "100 a handoff naming another Run does not unblock, wherever it sits" \
  --task T-02 --from-plan "${FIXTURES}/plan-ok.md"

echo
echo "plan lint: depth, width and Dispatch granularity"

# The linter's second job. Depth and width are properties of the whole
# document — no row can state either — so they come out of the same walk that
# detects cycles, and they are *reported* and *warned about*, never failed on:
# a deep plan is sometimes correct, and a linter that refuses correct plans
# stops being run. The granularity checks are the two proxies a plan file
# carries for "is this row worth a Dispatch", and they warn for the same
# reason — a proxy that fails a correct plan is worse than no proxy at all.
#
# A warning lands on stderr and a measurement on stdout, so every case below
# reads both: expect_lint holds exit code and stdout, and the greps after it
# hold what stderr said.

# 101. Five Tasks in a chain: depth is the longest path through `blocks`, width
#      is the most any one level holds, and neither is a failure.
expect_lint 0 '^depth 5  width 1  tasks 5$' \
  "101 a chain of five reports depth 5 and width 1" plan-deep.md
if grep -q 'wide, not deep' "${TMP}/err" &&
  grep -q 'Longest chain: T-01 -> T-02 -> T-03 -> T-04 -> T-05' "${TMP}/err"; then
  ok "101b the depth warning quotes the rule and names the chain"
else
  no "101b the depth warning quotes the rule and names the chain" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi
if grep -q 'no two of them can run at once' "${TMP}/err"; then
  ok "101c and it says the plan cannot use a second executor"
else
  no "101c and it says the plan cannot use a second executor" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 102. Five rows that block nothing: the shape protocol.md asks for. Neither
#      plan-level warning fires and no granularity one does either — the empty
#      stderr is the assertion, so a check that began warning about every clean
#      plan fails here rather than being noticed by whoever reads the output.
expect_lint 0 '^depth 1  width 5  tasks 5$' \
  "102 five independent rows report width 5" plan-wide.md
if [ ! -s "${TMP}/err" ]; then
  ok "102b and nothing at all is warned about it"
else
  no "102b and nothing at all is warned about it" "$(tr '\n' '|' <"${TMP}/err")"
fi

# 103. The granularity proxies, all three shapes in one plan.
expect_lint 0 '^depth 2  width 3  tasks 4$' \
  "103 thin and fat rows still lint clean, on the shape a clean plan has" plan-thin.md
# The singular is deliberate in the fixture, and this is the line a plural
# would have hidden: `1 non-blank lines` is the kind of thing nobody reads
# past, in the one message whose job is to be read.
if grep -q 'T-01 is 1 non-blank line and shares ai/herdr/team.sh with T-02' "${TMP}/err"; then
  ok "103b the thin row is named with the path it shares, and the remedy"
else
  no "103b the thin row is named with the path it shares, and the remedy" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi
# Both ends of that chain are thin by the same measure. One merge, one warning:
# naming the same pair twice reads as two problems.
if [ "$(grep -c 'merge them' "${TMP}/err")" -eq 1 ]; then
  ok "103c the chained pair is reported once, not once per end"
else
  no "103c the chained pair is reported once, not once per end" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi
if grep -q 'T-03 names ai/herdr/, a directory' "${TMP}/err"; then
  ok "103d a row naming a tree is warned about"
else
  no "103d a row naming a tree is warned about" "$(tr '\n' '|' <"${TMP}/err")"
fi
if grep -q 'T-04 names 9 paths' "${TMP}/err"; then
  ok "103e and so is a row too broad for its verify to localize"
else
  no "103e and so is a row too broad for its verify to localize" \
    "$(tr '\n' '|' <"${TMP}/err")"
fi

# 104. The parsers are still one parser. `--from-plan` runs the same walk that
#      now measures the plan, so a document the linter warns about has to
#      dispatch exactly as it did — and none of the new text may reach the
#      prompt an executor reads, which is why the shape line goes to stderr
#      from `plan lint` alone and never out of plan_rows.
reset
code=0
dispatch --task T-01 --from-plan "${FIXTURES}/plan-deep.md" >"${TMP}/out" || code=$?
if [ "$code" -eq 0 ] &&
  grep -q 'plan-deep\.md, section "### T-01"\.' "${TMP}/out" &&
  grep -q 'shellcheck -x ai/herdr/team.sh' "${TMP}/out"; then
  ok "104 a plan the linter warns about still dispatches"
else
  no "104 a plan the linter warns about still dispatches" \
    "exit ${code}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
fi
if ! grep -qE '^depth [0-9]+  width [0-9]+  tasks [0-9]+$' "${TMP}/out" &&
  ! grep -q 'wide, not deep' "${TMP}/err"; then
  ok "104b and neither the shape line nor a warning reaches the Dispatch"
else
  no "104b and neither the shape line nor a warning reaches the Dispatch" \
    "$(grep -n 'depth\|wide, not deep' "${TMP}/out" "${TMP}/err" | tr '\n' '|')"
fi

# 104c. The other caller of the same parser, which reads `rows` and `findings`
#       and has no opinion about shape at all.
reset
expect_collect 0 '^T-01 +ready' "104c collect --plan reads a warned plan unchanged" \
  --plan "${FIXTURES}/plan-wide.md"

# 105. No shape line for a plan that never parsed. There are no Tasks to
#      measure, and `depth 0  width 0  tasks 0` would be a report about a
#      document this code could not read.
"${TEAM}" plan lint "${FIXTURES}/plan-no-block.md" >"${TMP}/out" 2>/dev/null
if ! grep -q '^depth ' "${TMP}/out"; then
  ok "105 a plan with no task block reports no shape"
else
  no "105 a plan with no task block reports no shape" "$(tr '\n' '|' <"${TMP}/out")"
fi

echo
echo "report: the table, and the two files it leaves behind"

# The one verb here that writes, so these cases are as much about where the
# writing lands as about what it says: a report printed into a pane dies with
# the pane, which is the data a "better day by day" loop is supposed to have.
#
# Their own Run ids rather than ${RUN}: the series is one line per Run, so a
# case reporting a Run another case already reported would exercise the dedupe
# rule instead of the append and pass for the wrong reason. That is also why
# the ids are fixed and not minted — the dedupe has to be asked for, never
# stumbled into.
RPT="R-fixture-0100"
RPT_NOPLAN="R-fixture-0101"
METRICS="${HERDR_TEAM_ROOT}/metrics.jsonl"

# metrics_lines — how many rows the series has. A missing file is zero, which is
# also how "this Run was never reported" reads through this.
metrics_lines() {
  local n=0
  [ -s "${METRICS}" ] && n="$(wc -l <"${METRICS}" | tr -d ' ')"
  printf '%s' "${n:-0}"
}

# 106. One Run with the three things a report exists to make visible: a Task
#      that took two Dispatches, a handoff claiming a check it cannot show, and
#      a handoff past the line cap. The winning Dispatch is D-02 — the same fold
#      `collect --plan` reads a Task through — and `sends` is 2, which is the
#      retry itself rather than a column nobody can act on.
reset
use_run "${RPT}"
plan_for "${RPT}" plan-ok.md
sent "${RPT}" T-01 D-01 exec-1
sent "${RPT}" T-01 D-02 exec-1
handoff T-01 "${RPT}" failed tool_error D-01
handoff T-01 "${RPT}" succeeded verified D-02
sent "${RPT}" T-02 D-01 exec-2
long_handoff T-02 "${RPT}" D-01

code=0
"${TEAM}" report "${RPT}" >"${TMP}/out" 2>"${TMP}/err" || code=$?
if [ "$code" -eq 0 ] &&
  grep -qE '^T-01 +D-02 +succeeded +verified +\S+ +2 +[0-9]+ +ok$' "${TMP}/out"; then
  ok "106 a retried Task shows its winning Dispatch and both attempts"
else
  no "106 a retried Task shows its winning Dispatch and both attempts" \
    "exit ${code}: $(tr '\n' '|' <"${TMP}/out")"
fi
if grep -qE '^T-02 +D-01 +succeeded +reported +\S+ +1 +[0-9]+ +UNVERIFIED$' "${TMP}/out"; then
  ok "106b a claim the handoff cannot show reads UNVERIFIED"
else
  no "106b a claim the handoff cannot show reads UNVERIFIED" \
    "$(tr '\n' '|' <"${TMP}/out")"
fi
# The line count is read out of the row rather than inferred from the footer
# that summarises it: the cap is about the handoff, and the row is where the
# handoff's own number is.
row="$(grep -E '^T-02 ' "${TMP}/out" | head -1)"
lines="$(printf '%s' "$row" | awk '{print $(NF - 1)}')"
if [ "${lines:-0}" -gt 150 ] && grep -q '(T-02/D-01)' "${TMP}/out"; then
  ok "106c an over-long handoff is flagged and counted, not refused"
else
  no "106c an over-long handoff is flagged and counted, not refused" \
    "lines=${lines:-?}: $(printf '%s' "$row") $(tr '\n' '|' <"${TMP}/out")"
fi

# 107. `report.json` is the same report, fielded — and the same numbers, not a
#      second reading of the Run that could drift from the table printed beside
#      it. Read through python because it has to parse as JSON at all, which is
#      what a later session opening it will assume.
rjson="$(run_dir "${RPT}")/report.json"
code=0
msg="$(
  python3 - "$rjson" "${TMP}/out" <<'PY' 2>&1
import json, sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
table = open(sys.argv[2], encoding="utf-8").read()
tot = d["totals"]
rows = {r["task"]: r for r in d["tasks"]}

assert tot["tasks"] == 2, tot
assert tot["dispatches"] == 3, tot
assert tot["retried_tasks"] == 1, tot
assert tot["retry_rate"] == 0.5, tot
assert tot["verify_rated"] == 2 and tot["verify_proven"] == 1, tot
assert tot["verify_pass_rate"] == 0.5, tot
assert tot["over_long_handoffs"] == 1, tot
assert rows["T-01"]["dispatch"] == "D-02" and rows["T-01"]["dispatches"] == 2, rows["T-01"]
assert rows["T-01"]["verify"] == "ok", rows["T-01"]
assert rows["T-02"]["verify"] == "UNVERIFIED", rows["T-02"]
assert rows["T-02"]["handoff_lines"] > 150, rows["T-02"]
# The plan the Run was cut from, measured the way `plan lint` measures it.
assert d["shape"]["depth"] == 2 and d["shape"]["width"] == 1, d["shape"]
# And the table beside it says the same two rates.
assert "retry rate 50%" in table, table
assert "verify pass rate 50%" in table, table
print("ok")
PY
)" || code=$?
if [ "$code" -eq 0 ] && [ "$msg" = "ok" ]; then
  ok "107 report.json parses and carries the same numbers as the table"
else
  no "107 report.json parses and carries the same numbers as the table" \
    "exit ${code}: $(printf '%s' "$msg" | tr '\n' ' ')"
fi

# 108. The series is one line per Run and the snapshot is not. A second `report`
#      has to rewrite report.json — "always current" means exactly that —
#      without putting a second row in the series, which would measure how often
#      somebody looked rather than how the Run went.
before="$(metrics_lines)"
rm -f "$rjson"
"${TEAM}" report "${RPT}" >"${TMP}/out" 2>"${TMP}/err"
after="$(metrics_lines)"
if [ -s "$rjson" ] && [ "$before" = "$after" ] &&
  [ "$(grep -c "\"run\": \"${RPT}\"" "${METRICS}")" -eq 1 ]; then
  ok "108 a second report rewrites report.json and appends no second line"
else
  no "108 a second report rewrites report.json and appends no second line" \
    "json $([ -s "$rjson" ] && echo back || echo missing), series ${before}->${after}: $(tr '\n' '|' <"${METRICS}")"
fi

# 109. `--no-write` is how a Run someone else owns is read. The table still
#      prints — a flag whose read printed nothing would be indistinguishable
#      from a broken verb — and neither file moves, which is the difference
#      between looking at another tab's Run and joining its series.
cp "$rjson" "${TMP}/report.json.before"
before="$(metrics_lines)"
code=0
"${TEAM}" report "${RPT}" --no-write >"${TMP}/out" 2>"${TMP}/err" || code=$?
after="$(metrics_lines)"
if [ "$code" -eq 0 ] && grep -qE '^T-01 +D-02' "${TMP}/out" &&
  cmp -s "$rjson" "${TMP}/report.json.before" && [ "$before" = "$after" ]; then
  ok "109 --no-write prints the table and touches neither file"
else
  no "109 --no-write prints the table and touches neither file" \
    "exit ${code}, series ${before}->${after}, json $([ -s "$rjson" ] && echo there || echo missing)"
fi

# 110. The append is gated on a Run whose plan resolves, which is what keeps a
#      smoke test out of the real series: a Run with no plan has no depth and no
#      width, so its line would be a row nothing else in the series could be
#      compared against. `report.json` is still written, because the Run
#      happened whether or not a document describes it.
use_run "${RPT_NOPLAN}"
handoff T-01 "${RPT_NOPLAN}" succeeded verified
before="$(metrics_lines)"
"${TEAM}" report "${RPT_NOPLAN}" >"${TMP}/out" 2>"${TMP}/err"
after="$(metrics_lines)"
if [ "$before" = "$after" ] && [ -s "$(run_dir "${RPT_NOPLAN}")/report.json" ] &&
  grep -qE '^T-01 +D-01 +succeeded +verified' "${TMP}/out"; then
  ok "110 a Run with no plan reports without joining the series"
else
  no "110 a Run with no plan reports without joining the series" \
    "series ${before}->${after}: $(tr '\n' '|' <"${TMP}/out")"
fi

# 111. No Run at all is the only thing this verb exits non-zero for, and it is
#      not the planless case above: a Run with no plan is a Run, and a question
#      about no Run is not a report with no rows.
reset
mv "$(pointer)" "${TMP}/run.away"
code=0
"${TEAM}" report >"${TMP}/out" 2>"${TMP}/err" || code=$?
mv "${TMP}/run.away" "$(pointer)"
if [ "$code" -eq 1 ]; then
  ok "111 report with no Run exits 1"
else
  no "111 report with no Run exits 1" "exit ${code}: $(head -1 "${TMP}/err")"
fi

# 112. And a Run id with nothing under it, which is a typo rather than a Run: an
#      empty table at exit 0 would answer it as though it were real.
code=0
"${TEAM}" report R-fixture-nope >"${TMP}/out" 2>"${TMP}/err" || code=$?
if [ "$code" -eq 1 ]; then
  ok "112 report on a Run that is not there exits 1"
else
  no "112 report on a Run that is not there exits 1" "exit ${code}: $(head -1 "${TMP}/err")"
fi

echo
echo "loop: one invocation, and the gates it stops at"

# The loop's own herdr: its panes a file the case writes, its prompts recorded,
# and every argv line appended to ${TMP}/loop-called — the three prohibitions
# this verb states are properties of no output, and that record is the only
# place they can be asserted from.
#
# The executor behind `agent prompt` runs nothing. It reads the Run, the Task,
# the Dispatch, the handoff path and the verify out of its own prompt — the same
# parse a real executor does — writes the handoff its prompt asked for, and
# records that verify at exit 0, which is what an honest handoff carries.
# Whether a verify really passes is `wait`'s question (cases 45-52); whether a
# Run advances is this section's.
mkdir -p "${TMP}/loop"
cat >"${TMP}/loop/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/loop-called"

# The status herdr reports, unless the case staged one that only appears after a
# prompt has gone out: an agent that answers its first Dispatch and then blocks
# on the next question.
pane_state() {
  if [ -f "${TMP}/loop-status-after-prompt" ] && [ -e "${TMP}/loop-prompted" ]; then
    cat "${TMP}/loop-status-after-prompt"
  else
    printf '%s' "\$1"
  fi
}

case "\$1 \$2" in
  "agent list")
    printf '{"result":{"agents":['
    sep=""
    while IFS=\$'\t' read -r n s p; do
      [ -n "\$n" ] || continue
      if [ "\$n" = "-" ]; then nj=null; else nj="\"\$n\""; fi
      printf '%s{"name":%s,"pane_id":"%s","agent_status":"%s","workspace_id":"wL:w%s"}' \
        "\$sep" "\$nj" "\$p" "\$(pane_state "\$s")" "\${p#wL:p}"
      sep=","
    done <"${TMP}/loop-panes"
    printf ']}}\n'
    ;;
  "worktree open")
    # A new pane, unnamed and working — what a real herdr reports between
    # \`pane run\` and the \`agent rename\` that names it.
    seq="\$(cat "${TMP}/loop-seq" 2>/dev/null || echo 0)"
    seq=\$((seq + 1))
    printf '%s\n' "\$seq" >"${TMP}/loop-seq"
    printf -- '-\tworking\twL:p%s\n' "\$seq" >>"${TMP}/loop-panes"
    printf '{"result":{"workspace":{"workspace_id":"wL:w%s","active_tab_id":"wL:t%s"},"root_pane":{"pane_id":"wL:p%s"},"already_open":false}}\n' \
      "\$seq" "\$seq" "\$seq"
    ;;
  "tab rename" | "pane run" | "pane send-keys" | "pane report-metadata" | "workspace close") ;;
  "agent rename")
    # Naming a pane herdr already had: unnamed and working becomes named and
    # idle, which is the state \`spawn\` polls for and the state the loop seats
    # a Dispatch on.
    awk -F'\t' -v p="\$3" -v n="\$4" 'BEGIN{OFS="\t"} \$3==p{\$1=n; \$2="idle"} {print}' \
      "${TMP}/loop-panes" >"${TMP}/loop-panes.new"
    mv "${TMP}/loop-panes.new" "${TMP}/loop-panes"
    ;;
  "agent prompt")
    : >"${TMP}/loop-prompted"
    [ -e "${TMP}/loop-no-write" ] && exit 0
    run="\$(printf '%s\n' "\$4" | sed -n 's/^run: //p' | tail -1)"
    task="\$(printf '%s\n' "\$4" | sed -n 's/^task: //p' | tail -1)"
    disp="\$(printf '%s\n' "\$4" | sed -n 's/^dispatch: //p' | tail -1)"
    path="\$(printf '%s\n' "\$4" | awk '/^  .*\/handoffs\/.*\.md\$/ {p=\$0; sub(/^[ \t]+/, "", p)} END{print p}')"
    cmd="\$(printf '%s\n' "\$4" | awk '/^Your verification command is:\$/ {getline; getline; sub(/^[ \t]+/, ""); print; exit}')"
    {
      printf -- '---\n'
      printf 'run: %s\ntask: %s\ndispatch: %s\n' "\$run" "\$task" "\$disp"
      printf 'outcome: succeeded\nevidence: verified\nfiles_changed: []\nartifacts: []\n'
      if [ -e "${TMP}/loop-unproven" ]; then
        printf 'commands: []\n'
      else
        printf 'commands: [{"cmd": "%s", "exit": 0}]\n' "\$cmd"
      fi
      printf -- '---\n\n## What was done\n\nFixture.\n\n## What was found\n\nNothing.\n\n## What remains\n\nNothing.\n'
    } >"\$path"
    ;;
  "agent wait")
    [ -e "${TMP}/loop-slow-wait" ] && exec sleep 300
    ;;
  *) exit 9 ;;
esac
exit 0
SH
chmod +x "${TMP}/loop/herdr"

# spawn's git, in the shape the `--spawn` path asks its questions: a worktree
# list that reports what `wta` created, and nothing else. The worktree itself is
# the real one the spawn cases use (67-78) — this case is about which pane the
# loop draws a Dispatch from, so the stub answers the path question and no more.
cat >"${TMP}/loop/git" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${TMP}/loop-git-called"
case "\$*" in
  *"worktree list --porcelain"*)
    printf 'worktree %s\nHEAD x\nbranch refs/heads/main\n' "${DOTFILES}"
    if [ -f "${TMP}/loop-branches" ]; then
      while read -r b; do
        [ -n "\$b" ] || continue
        printf 'worktree %s/%s\nHEAD x\nbranch refs/heads/%s\n' "${TMP}/loop-wt" "\$b" "\$b"
      done <"${TMP}/loop-branches"
    fi
    ;;
  *wta*)
    # \`git wta <branch>\`, which is the shape the loop's spawn uses; the
    # branch is the last argument whether or not the call carries a -C.
    last=""
    for arg in "\$@"; do last="\$arg"; done
    printf '%s\n' "\$last" >>"${TMP}/loop-branches"
    ;;
esac
exit 0
SH
chmod +x "${TMP}/loop/git"

# And the login shell the provider check asks, wrapped the same way the spawn
# section wraps it: a real zsh with the fixture's provider appended last, so
# whichever `ccd` row the loop spawns is checked against the check that would
# really run rather than against a stub's opinion of it.
cat >"${TMP}/loop/zsh" <<SH
#!/usr/bin/env bash
[ "\$1" = "-ic" ] || exec "${REAL_ZSH}" "\$@"
exec "${REAL_ZSH}" -ic "_cc_prov_names+=(herdr-fixture); _cc_prov[herdr-fixture:short]=ccd; _cc_prov[herdr-fixture:key]=\$FIXTURE_REF; \$2" "\${@:3}"
SH
chmod +x "${TMP}/loop/zsh"

# loop_fresh <"name status"...> — every recording and knob cleared, the live
# panes set, the Run back to the fixture one. A knob left set by an earlier case
# would stage the next case's loop without saying so.
loop_fresh() {
  local line name st n=1
  rm -f "${TMP}/loop-called" "${TMP}/loop-prompted" \
    "${TMP}/loop-seq" "${TMP}/loop-branches" "${TMP}/loop-git-called" \
    "${TMP}/loop-status-after-prompt" "${TMP}/loop-slow-wait" \
    "${TMP}/loop-no-write" "${TMP}/loop-unproven"
  : >"${TMP}/loop-panes"
  reset
  for line in "$@"; do
    name="${line%% *}"
    st="${line##* }"
    [ -n "$name" ] || continue
    printf '%s\t%s\twL:p%s\n' "$name" "$st" "$n" >>"${TMP}/loop-panes"
    n=$((n + 1))
  done
}

# loop_on <want-exit> <stdout-regex> <label> [args...] — one `loop` against the
# stubs. An empty regex checks the exit code only.
loop_on() {
  local want="$1" re="$2" label="$3" code=0
  shift 3
  env PATH="${TMP}/loop:${PATH}" "${TEAM}" loop "$@" >"${TMP}/out" 2>"${TMP}/err" || code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  elif [ -n "$re" ] && ! grep -qE "$re" "${TMP}/out"; then
    no "$label" "no /${re}/ in: $(tr '\n' '|' <"${TMP}/out")"
  else
    ok "$label"
  fi
}

# loop_refuse <stderr-regex> <label> [args...] — a `loop` that has to die before
# it calls herdr at all: a precondition is answered at the door or not at all.
loop_refuse() {
  local re="$1" label="$2" code=0
  shift 2
  env PATH="${TMP}/loop:${PATH}" "${TEAM}" loop "$@" >"${TMP}/out" 2>"${TMP}/err" || code=$?
  if [ "$code" -eq 1 ] && grep -qE "$re" "${TMP}/err"; then
    ok "$label"
  else
    no "$label" "exit ${code}: $(head -1 "${TMP}/err")"
  fi
}

# called <n> <argv-regex> <label> — how many recorded herdr calls matched. The
# record is per case, so a case that counts calls counts its own.
called() {
  local want="$1" re="$2" label="$3" got=0 calls=""
  [ -f "${TMP}/loop-called" ] && got="$(grep -cE "$re" "${TMP}/loop-called")"
  if [ "${got:-0}" -eq "$want" ]; then
    ok "$label"
  else
    [ -f "${TMP}/loop-called" ] && calls="$(tr '\n' '|' <"${TMP}/loop-called")"
    no "$label" "${got:-0} matched /${re}/: ${calls:-<nothing called>}"
  fi
}

# loop_tail <regex> <label> — the last line of the Run's trace, which is the gate
# the loop returned on: why a stopped Run stopped, kept where a reader of that
# Run will look rather than only in a pane that has since closed.
loop_tail() {
  local re="$1" label="$2" line="" log=""
  [ -f "$(run_dir "${RUN}")/loop.log" ] && log="$(cat "$(run_dir "${RUN}")/loop.log")"
  line="$(printf '%s\n' "$log" | tail -1)"
  if grep -qE "$re" <<<"$line"; then
    ok "$label"
  else
    no "$label" "last line: ${line:-<no loop.log>}"
  fi
}

# loop_says <regex> <label> — any line of the Run's trace. The last line is the
# gate and `loop_tail` reads that; the wave lines above it are what the loop did
# on the way to the gate, which is what says a gate was reached the long way.
loop_says() {
  local re="$1" label="$2" log=""
  [ -f "$(run_dir "${RUN}")/loop.log" ] && log="$(cat "$(run_dir "${RUN}")/loop.log")"
  if grep -qE "$re" <<<"$log"; then
    ok "$label"
  else
    no "$label" "no /${re}/ in: $(printf '%s' "$log" | tr '\n' '|')"
  fi
}

# loop_err <regex> <label> — a line of what the last `loop` wrote to stderr.
# Every refusal this verb hands out goes there: stdout is the table a human
# reads, and a refusal mixed into it would be read as a row.
loop_err() {
  local re="$1" label="$2"
  if grep -qE "$re" "${TMP}/err"; then
    ok "$label"
  else
    no "$label" "no /${re}/ in: $(head -3 "${TMP}/err" | tr '\n' '|')"
  fi
}

# 113. The whole of what this verb is for: one invocation drives a plan to the
#      end of its chain — dispatch, wait, collect, dispatch — and the
#      orchestrator's turn is spent once instead of once per settle. The chain
#      here is five Tasks rather than the three the Task was written around,
#      because `plan-deep.md` is the fixture that already has one and a longer
#      chain is the stronger claim: a loop that stopped at the first settle ends
#      this case with one handoff and no wave line for T-02.
loop_fresh "exec-0001-1 idle"
plan_for "${RUN}" plan-deep.md
metrics_before="$(metrics_lines)"
loop_on 0 '^wave 5: dispatched T-05, waiting$' \
  "113 one invocation drives a five-Task chain to its end" \
  --plan "${FIXTURES}/plan-deep.md"

# Every Task's handoff is on disk, where that Task's own prompt said to write
# it: the stub reads the path out of the prompt, so this checks the prompt's
# claim against the Run's handoff directory rather than the fixture's memory of
# where it put things.
missing=""
for n in 01 02 03 04 05; do
  [ -f "$(handoff_dir "${RUN}")/T-${n}-D-01.md" ] || missing="${missing} T-${n}"
done
if [ -z "$missing" ]; then
  ok "113b every Task in the chain has its handoff under the Run"
else
  no "113b every Task in the chain has its handoff under the Run" "missing:${missing}"
fi

# The journal is the dispatcher's, four columns a line: the loop writes no line
# of its own there, and a Task that settled in wave 1 is not dispatched again in
# wave 3.
journal="$(handoff_dir "${RUN}")/.dispatched"
entries="$(wc -l <"${journal}" 2>/dev/null | tr -d ' ')"
bad_rows="$(awk -F'\t' 'NF != 4' "${journal}" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${entries:-0}" -eq 5 ] && [ "${bad_rows:-1}" -eq 0 ]; then
  ok "113c five journal lines, one per Task, four columns each"
else
  no "113c five journal lines, one per Task, four columns each" \
    "lines=${entries:-0} malformed=${bad_rows:-?}"
fi
called 5 '^agent prompt exec-0001-1 ' "113d every Dispatch went to the one live pane"

# The trace: a line per wave, and the last line says why it stopped. One pane
# drives the whole chain — reuse within a lane is the sanctioned kind, and it is
# what makes a single executor enough for a plan.
waves="$(grep -c ' dispatched T-0[0-9], waiting$' "$(run_dir "${RUN}")/loop.log")"
if [ "${waves:-0}" -eq 5 ]; then
  ok "113e the trace has one line per wave"
else
  no "113e the trace has one line per wave" \
    "${waves:-0} wave lines: $(tr '\n' '|' <"$(run_dir "${RUN}")/loop.log")"
fi
loop_tail 'wave 6: nothing ready and nothing running — the Run is complete$' \
  "113f the trace's last line says the Run is complete"

# `report` ran once on the way out. A Run that ran unattended is exactly the Run
# whose numbers nobody asked for, so the file and its series line have to be
# there without being requested.
if [ -s "$(run_dir "${RUN}")/report.json" ]; then
  ok "113g the loop wrote report.json on the way out"
else
  no "113g the loop wrote report.json on the way out" "no report.json"
fi
metrics_after="$(metrics_lines)"
if [ "$metrics_after" -eq $((metrics_before + 1)) ]; then
  ok "113h the Run joined the metrics series exactly once"
else
  no "113h the Run joined the metrics series exactly once" \
    "series ${metrics_before}->${metrics_after}"
fi

# Asked again about the finished Run, the loop stops at the top of the first
# wave and dispatches nothing: this is `collect`'s 3 read as "complete", which
# it can only be because nothing was running. The prompt count is the assertion
# — a second Dispatch at a settled Task is what that would look like.
loop_on 0 '' "113i a finished Run dispatches nothing when it is asked again" \
  --plan "${FIXTURES}/plan-deep.md"
called 5 '^agent prompt ' "113j five Dispatches in total — no Task was dispatched twice"
expect_collect 3 '^T-05 +done' \
  "113k collect --plan reads the finished Run as done, exit 3" \
  --plan "${FIXTURES}/plan-deep.md"

# 114. Exit 3 from `collect` is not "finished". A Run whose only remaining Task
#      is running reports nothing ready and exits 3, and a loop that read that as
#      the end would abandon the executor that is still working — the manual step
#      this verb exists to remove. Staged directly: a Dispatch the journal knows
#      about with no handoff for it, and a wait the stub never answers, because
#      exit 4 is reachable at no other point in this verb.
loop_fresh "exec-0001-1 working"
sent "${RUN}" T-01 D-01 exec-0001-1
: >"${TMP}/loop-slow-wait"
loop_on 4 '' "114 collect exit 3 with a Task still running goes on to the wait" \
  --plan "${FIXTURES}/plan-deep.md" --timeout 1000
loop_says 'nothing ready, a Dispatch is still out — waiting' \
  "114b a running Task with nothing ready takes the wait, not the end"
loop_err 'wait: --timeout 1000ms expired with nothing settled' \
  "114c the timeout reached the wait, which is the only place it expires"
called 1 '^agent wait exec-0001-1 ' "114d the running Task's own agent was waited on"

# 115. A ready row with no pane to put it on. Two executors are up and both are
#      working, so nothing can move this wave — and the decision the loop hands
#      back is the one it must not make for itself: spawn a pane, or settle one.
#      The refusal names the rows and the live panes, because "no pane free"
#      without them is a message nobody can act on. It names no cap: the cap is
#      how many worktrees one Run may carry, not how many panes may be live, and
#      a number here would be a number the reader cannot act on.
loop_fresh "exec-0001-1 working" "exec-0001-2 working"
loop_on 6 'no pane free for them' "115 a ready row with no free pane stops at 6" \
  --plan "${FIXTURES}/plan-wide.md"
if grep -qE '^loop: T-01 T-02 T-03 T-04 T-05 ready and no pane free for them — exec-0001-1 exec-0001-2 live; --spawn <branch-prefix>, or settle one$' \
  "${TMP}/out"; then
  ok "115b the refusal names the rows and the live panes"
else
  no "115b the refusal names the rows and the live panes" \
    "$(grep -E '^loop: ' "${TMP}/out" | tr '\n' '|')"
fi
called 0 '^agent prompt' "115c nothing was dispatched into a pool with no room"
loop_tail 'gate: exit 6 — a Task is ready and no pane is free — spawn one, or settle one$' \
  "115d the trace ends at gate 6"

# 116. The other way to 3: a Dispatch is out, and the journal line for it is one
#      nobody can wait on — the three-column shape an older journal still has,
#      with no agent in it. `wait` says so and refuses rather than waiting out
#      the readable half of the journal, and the loop carries that refusal out:
#      nothing was dispatched this wave, so there is nothing to go round again
#      for.
loop_fresh "exec-0001-1 working"
sent "${RUN}" T-01 D-01
loop_on 3 '' "116 a Dispatch nobody can wait on stops at 3" \
  --plan "${FIXTURES}/plan-deep.md"
called 0 '^agent wait' "116b a journal line with no agent is not waited on"
loop_err 'nothing waitable' "116c the refusal is the wait's, and says why"
loop_says 'nothing outstanding to wait for — done or wedged' \
  "116d the trace says which 3 this is"
loop_tail 'gate: exit 3 — nothing the loop can dispatch and nothing running' \
  "116e and ends at the gate that names it"

# 116f. The third way to 3, and the one a reader is most likely to meet: a
#       handoff that claims success without the row's own verify in it. That
#       Task is `review` — work for a reviewer no plan row names — and the
#       dependent behind it stays blocked, so there is nothing to dispatch and
#       nothing to wait for. The table is printed, because the reviewer's
#       business is in its cause column.
loop_fresh "exec-0001-1 idle"
: >"${TMP}/loop-unproven"
loop_on 3 'UNVERIFIED' "116f a handoff that cannot prove its verify stops at 3" \
  --plan "${FIXTURES}/plan-deep.md"
called 0 '^agent wait' "116g nothing is waited on when nothing was dispatched"
loop_says 'need a reviewer no plan row names' "116h the trace names what is missing"
loop_tail 'gate: exit 3 — nothing the loop can dispatch and nothing running' \
  "116i and ends at the gate that names it"

# 117. A Task that failed. Retry is human-gated — a script that retried a
#      failure would re-run a verify that has already said no, forever — so the
#      loop stops at 2 and hands the decision back. The three prohibitions are
#      asserted here rather than assumed: `settle` is an
#      `agent prompt <name> /clear` and `teardown` is a `workspace close`, so
#      both would appear in the same record as the Dispatches, and a second
#      Dispatch at a failed Task would be a second prompt for T-01.
loop_fresh "exec-0001-1 idle"
handoff T-01 "${RUN}" failed tool_error
loop_on 2 '^T-01 +failed' "117 a failed Task stops the loop at 2" \
  --plan "${FIXTURES}/plan-ok.md"
called 0 '^agent prompt' "117b a failed Task is not retried, and nothing is settled"
called 0 'workspace close' "117c nothing is torn down"
if [ ! -f "${TMP}/loop-called" ]; then
  ok "117d the failure was read off the table already in hand, herdr never called"
else
  no "117d the failure was read off the table already in hand, herdr never called" \
    "$(tr '\n' '|' <"${TMP}/loop-called")"
fi
if [ ! -f "$(handoff_dir "${RUN}")/T-01-D-02.md" ]; then
  ok "117e no second Dispatch was journaled for the failed Task"
else
  no "117e no second Dispatch was journaled for the failed Task" \
    "$(tr '\n' '|' <"$(handoff_dir "${RUN}")/.dispatched" 2>/dev/null)"
fi
# And read off the source, where a stub cannot help: the day the stub above
# stopped recording, a body that called settle would still pass every case in
# this section. The words appear in the section's own comments and in gate 6's
# message; what is asserted is that neither verb is ever *called*.
if [ "$(awk '/^loop_wave\(\)/,/^}/' "${TEAM}" | grep -cE '(^|[^_a-z])cmd_(settle|teardown)\b')" -eq 0 ]; then
  ok "117f the wave's body calls neither settle nor teardown"
else
  no "117f the wave's body calls neither settle nor teardown" \
    "the body names one of them as a call"
fi

# 118. A precondition failed: the plan cannot be read, so there is nothing to
#      drive and no Dispatch to make. Exit 1 with herdr never called — the
#      refusal is `collect`'s, and the loop's job is to carry it out rather than
#      to work around it.
loop_fresh "exec-0001-1 idle"
loop_on 1 '' "118 an unreadable plan stops the loop at 1" --plan "${FIXTURES}/plan-cycle.md"
if [ ! -f "${TMP}/loop-called" ] && grep -qE '^collect: ' "${TMP}/err"; then
  ok "118b the refusal is collect's, carried out before anything was called"
else
  no "118b the refusal is collect's, carried out before anything was called" \
    "called=$(tr '\n' '|' <"${TMP}/loop-called" 2>/dev/null) err=$(head -1 "${TMP}/err")"
fi

# 118c. The same gate by the other route: a journal line nobody can read. The
#       wave dispatches first, because `dispatch` is what journals — so this is
#       also the shape of the one case where a malformed journal is met after a
#       Dispatch rather than before it.
loop_fresh "exec-0001-1 idle"
printf '%s\t%s\n' "${RUN}" T-01 >>"$(handoff_dir "${RUN}")/.dispatched"
loop_on 1 '' "118c an unreadable journal stops the loop at 1" \
  --plan "${FIXTURES}/plan-ok.md"
called 1 '^agent prompt ' "118d the wave's Dispatch was made, and then reported"
loop_err 'not 3 or 4 columns' "118e the refusal is the wait's, and quotes the line"
loop_says 'wait exit 1' "118f the trace says which refusal stopped it"

# 119. --max-waves bounds a Run that would not end on its own. Two waves of the
#      chain, then 4 — the same answer as a timeout, because the fact is the
#      same one: the Run did not stop, the loop did.
loop_fresh "exec-0001-1 idle"
loop_on 4 '^wave limit 2 reached' "119 --max-waves stops a Run that is still going" \
  --plan "${FIXTURES}/plan-deep.md" --max-waves 2
called 2 '^agent prompt ' "119b exactly the two waves were dispatched"
loop_tail 'wave limit 2 reached — stopping$' \
  "119c the trace says the loop stopped, not the Run"

# 120. An agent that goes blocked is holding a question nobody in the Run may
#      answer. The next move is a human reading that pane, so the loop stops at 5
#      and names it: a loop that guessed 0 here is what leaves the question
#      invisible until somebody happens to look at the pane.
loop_fresh "exec-0001-1 idle"
: >"${TMP}/loop-no-write"
printf '%s\n' blocked >"${TMP}/loop-status-after-prompt"
loop_on 5 '^exec-0001-1 T-01 blocked$' \
  "120 a blocked agent stops the loop at 5 and is named" --plan "${FIXTURES}/plan-deep.md"
loop_says 'team\.sh surface exec-0001-1$' "120b the trace names the pane to surface"
loop_tail 'gate: exit 5 — an agent is blocked on a question' "120c and ends at gate 5"

# 121. A review row draws from the `rev-` pool. `plan-ok.md`'s T-02 is `cc` and
#      names T-01 in `blocks` — `dispatchable-plan`: "a review is work, so it
#      gets a row like anything else, with `blocks` naming what it reviews" — so
#      with T-01 settled it goes to the reviewer while both executors sit idle.
#      A loop that sent it to an exec pane would be queueing a review behind the
#      pool it exists to check.
loop_fresh "exec-0001-1 idle" "exec-0001-2 idle" "rev-t-02 idle"
handoff T-01 "${RUN}" succeeded verified
loop_on 0 '^wave 1: dispatched T-02, waiting$' "121 a review row goes to the reviewer" \
  --plan "${FIXTURES}/plan-ok.md"
called 1 '^agent prompt rev-t-02 ' "121b the review went to the rev- pane"
called 0 '^agent prompt exec-0001-1 ' "121c and no executor was used for it"
called 0 '^agent prompt exec-0001-2 ' "121d nor the other one"
if awk -F'\t' -v r="${RUN}" \
  '$1==r && $2=="T-02" && $4=="rev-t-02"{f=1} END{exit !f}' \
  "$(handoff_dir "${RUN}")/.dispatched"; then
  ok "121e the journal records which pane holds the review"
else
  no "121e the journal records which pane holds the review" \
    "$(tr '\n' '|' <"$(handoff_dir "${RUN}")/.dispatched")"
fi

# 122. `--spawn` is opt-in because it creates a worktree. With a ready row and
#      no pane at all it draws panes from the pool's own name space, spawns the
#      cap's worth and no more, and then dispatches into them and carries on in
#      the same invocation — the executor it started is one it waits on, not one
#      it hands back. `plan-wide.md`'s five rows are independent, so this is
#      also where the loop reuses a pane it spawned for the next Task in line.
loop_fresh
FIXTURE_REF=env:HERDR_FIXTURE_KEY
HERDR_FIXTURE_KEY=fixture
export FIXTURE_REF HERDR_FIXTURE_KEY
loop_on 0 '^wave 3: dispatched T-05, waiting$' \
  "122 --spawn draws panes, dispatches into them and carries on" \
  --plan "${FIXTURES}/plan-wide.md" --spawn feat/loop
unset FIXTURE_REF HERDR_FIXTURE_KEY
called 2 '^worktree open' "122b two panes were spawned, which is the cap"
branches="$(sort "${TMP}/loop-branches" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
if [ "$branches" = "feat/loop-t-01 feat/loop-t-02" ]; then
  ok "122c the branches are named for the Tasks they carry, to the cap"
else
  no "122c the branches are named for the Tasks they carry, to the cap" \
    "branches: ${branches:-<none>}"
fi
called 5 '^agent prompt ' "122d all five rows were dispatched, three onto reused panes"
# Five Dispatches through two panes is the reuse; the panes file is the loop's
# own record of the pool, so it is also where a third pane would have shown up.
if [ "$(wc -l <"${TMP}/loop-panes" | tr -d ' ')" -eq 2 ] &&
  grep -qE '^exec-0001-1[[:space:]]' "${TMP}/loop-panes" &&
  grep -qE '^exec-0001-2[[:space:]]' "${TMP}/loop-panes"; then
  ok "122e both panes stayed in the pool's name space, and there were only two"
else
  no "122e both panes stayed in the pool's name space, and there were only two" \
    "$(tr '\n' '|' <"${TMP}/loop-panes")"
fi

# 123. The preconditions, answered before anything is read. `--timeout` is
#      milliseconds — the unit `wait` takes — and a bare `999` is a
#      plausible-looking second, which is why the floor exists and why the
#      refusal names the unit rather than the number.
loop_fresh "exec-0001-1 idle"
loop_refuse 'milliseconds' "123 --timeout 999 is refused, and the refusal names the unit" \
  --plan "${FIXTURES}/plan-deep.md" --timeout 999
loop_refuse 'plan is required' "123b a loop with no plan is refused" --max-waves 1
loop_refuse 'branch prefix' "123c --spawn with nothing to name the branch is refused" \
  --plan "${FIXTURES}/plan-deep.md" --spawn
if [ ! -f "${TMP}/loop-called" ]; then
  ok "123d no precondition was answered by calling herdr first"
else
  no "123d no precondition was answered by calling herdr first" \
    "$(tr '\n' '|' <"${TMP}/loop-called")"
fi

echo
echo "the two caps: one Run's executors, one provider's panes"

# loop_cmd <want-exit> <label> <args...> — another team.sh verb against the loop
# stubs, so a case about the record a pane leaves behind drives the verbs that
# write it and remove it against the same panes the loop is looking at.
loop_cmd() {
  local want="$1" label="$2" code=0
  shift 2
  env PATH="${TMP}/loop:${PATH}" "${TEAM}" "$@" >"${TMP}/out" 2>"${TMP}/err" || code=$?
  if [ "$code" -ne "$want" ]; then
    no "$label" "exit ${code}, want ${want}: $(head -2 "${TMP}/err" | tr '\n' ' ')"
  else
    ok "$label"
  fi
}

# pane_field <name> <field> — one field of that pane's record, or nothing when
# there is no record. Read here rather than through team.sh so a case asserts
# the file `spawn` wrote rather than what the verb that wrote it can say about
# it.
pane_field() {
  local f="${HERDR_TEAM_ROOT}/state/panes/${1}" i
  case "${2:-}" in
    provider) i=2 ;;
    run) i=3 ;;
    worktree) i=4 ;;
    spawned) i=5 ;;
    *) i=1 ;;
  esac
  [ -f "$f" ] || return 0
  awk -F'\t' -v n="$i" 'NR==1{print $n}' "$f"
}

# 124. The per-Run cap counts panes this Run is answerable for, and a spawn makes
#      one before any Dispatch does: a pane this Run spawned and has not sent
#      work to is still a worktree it is carrying. That is why the count reads
#      two records and not one — the pane exists before the Dispatch that gives
#      it work, so a journal alone would miss the window between them.
loop_fresh "exec-0001-1 working" "exec-0001-2 working"
record exec-0001-1 ccd "${RUN}"
sent "${RUN}" T-01 D-01 exec-0001-2
spawn_on "${TMP}/loop" 1 "124 a pane this Run spawned but has not dispatched still counts" \
  exec-0001-3 --branch feat/cap-3 --provider ccd
if grep -q 'this Run already holds 2 executors (exec-0001-1 exec-0001-2)' "${TMP}/err"; then
  ok "124b and the refusal names both: the spawned pane and the dispatched one"
else
  no "124b and the refusal names both: the spawned pane and the dispatched one" \
    "$(head -3 "${TMP}/err" | tr '\n' '|')"
fi
called 0 '^worktree open' "124c nothing was created for the refused spawn"

# 124d. The cap is on executors. A `rev-` pane is how a blocked executor gets
#       unblocked, so a full pool of executors must not be what stops one — and
#       it does not, with the Run holding its two while this one is drawn.
spawn_on "${TMP}/loop" 0 "124d a rev- pane is drawn while the Run's cap is full" \
  rev-t-09 --branch feat/cap-rev --provider cc
called 1 '^worktree open' "124e and it is the spawn that drew it"

# 125. Criterion 10, and the difference between the two caps in one case. Run A
#      holds two `ccd` executors; the shell is then in Run B, which holds none,
#      and a `cc` executor is drawn there with no override — a different
#      provider, so nothing of Run A's is in its way, and a different Run, so
#      neither of Run A's worktrees is either. Under the machine-wide cap T-07
#      replaced, the second executor in the pool was the thing that refused this.
loop_fresh "exec-a1 working" "exec-a2 working"
record exec-a1 ccd "${RA}"
record exec-a2 ccd "${RA}"
use_run "${RB}" tab-a
spawn_on "${TMP}/loop" 0 "125 a cc executor spawns under Run B while Run A holds two ccd executors" \
  exec-b1 --branch feat/cap-b --provider cc
called 1 '^worktree open' "125b and Run A's two executors did not refuse it"
if [ "$(pane_field exec-b1 provider)" = cc ] && [ "$(pane_field exec-b1 run)" = "${RB}" ]; then
  ok "125c the pane was recorded with its provider and the Run that drew it"
else
  no "125c the pane was recorded with its provider and the Run that drew it" \
    "record: $(tr '\t' ':' < "${HERDR_TEAM_ROOT}/state/panes/exec-b1" 2>/dev/null)"
fi

# 126. The record's other end. It is written where the pane is made, because the
#      two caps count panes rather than worktrees and a pane that has not been
#      dispatched to yet is exactly the one a count has to get right; and it goes
#      where the pane stops holding its provider — `settle … release` and
#      `teardown` being the same line, so the two ways a pane ends both forget
#      it. What must not happen is a released pane going on counting, which is
#      how a pool refuses a spawn it has room for.
if [ "$(pane_field exec-b1 worktree)" = "${TMP}/loop-wt/feat/cap-b" ] &&
  [ -n "$(pane_field exec-b1 spawned)" ]; then
  ok "126 the record carries the worktree the pane was opened on, and a stamp"
else
  no "126 the record carries the worktree the pane was opened on, and a stamp" \
    "record: $(tr '\t' ':' < "${HERDR_TEAM_ROOT}/state/panes/exec-b1" 2>/dev/null)"
fi
loop_cmd 0 "126b settle retain keeps the record" settle exec-b1 retain
if [ -f "${HERDR_TEAM_ROOT}/state/panes/exec-b1" ]; then
  ok "126c a retained pane still holds its provider"
else
  no "126c a retained pane still holds its provider" "the record is gone"
fi
: >"${TMP}/loop-called"
loop_cmd 0 "126d settle release drops it" settle exec-b1 release
if [ ! -f "${HERDR_TEAM_ROOT}/state/panes/exec-b1" ] &&
  [ -f "${HERDR_TEAM_ROOT}/state/panes/exec-a1" ]; then
  ok "126e and drops nothing else: the other pane is still counted"
else
  no "126e and drops nothing else: the other pane is still counted" \
    "records left: $(find "${HERDR_TEAM_ROOT}/state/panes" -type f 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')"
fi
called 1 'workspace close' "126f releasing is the workspace close teardown is"

# 127. The provider ceiling, which is not the Run's cap: one DeepSeek key, one
#      Pro login, one machine. Four panes on one provider across three Runs, and
#      the fifth is refused by whichever Run asked — because the fourth Run holds
#      none of them, so a per-Run count would have let it through.
loop_fresh "exec-a1 working" "exec-a2 working" "exec-a3 working" "exec-b1 working"
record exec-a1 ccd "${RA}"
record exec-a2 ccd "${RA}"
record exec-a3 ccd "${RB}"
record exec-b1 ccd "${RPT}"
use_run "${RPT_NOPLAN}" tab-a
spawn_on "${TMP}/loop" 1 "127 a fifth pane on one provider is refused across Runs" \
  exec-c1 --branch feat/cap-c --provider ccd
if grep -q "4 panes count against ccd's ceiling (exec-a1 exec-a2 exec-a3 exec-b1)" "${TMP}/err" &&
  grep -q 'ceiling is 4 panes on one provider across every Run' "${TMP}/err"; then
  ok "127b and the refusal names the panes and the ceiling"
else
  no "127b and the refusal names the panes and the ceiling" \
    "$(head -3 "${TMP}/err" | tr '\n' '|')"
fi
if grep -q 'executors per Run' "${TMP}/err"; then
  no "127c and it is the ceiling's refusal, not the Run's cap" "$(grep 'per Run' "${TMP}/err")"
else
  ok "127c and it is the ceiling's refusal, not the Run's cap"
fi
called 0 '^worktree open' "127d nothing was created for it"
# 127e. The ceiling counts panes, not executors: a `rev-` pane holds the same
#       credential, so the same four panes refuse it. The Run's cap would not
#       have — that is the difference between the two, in one refusal.
spawn_on "${TMP}/loop" 1 "127e a rev- pane is refused by the same ceiling" \
  rev-t-09 --branch feat/cap-d --provider ccd
if grep -q "ceiling is 4 panes" "${TMP}/err"; then
  ok "127f for the same reason, and the refusal says so"
else
  no "127f for the same reason, and the refusal says so" \
    "$(head -3 "${TMP}/err" | tr '\n' '|')"
fi

# 128. A pane with no record is `unknown`, and unknown is counted. It is the
#      direction the ceiling has to fail in: a pane spawning while its record is
#      being written, or one hand-started, is still a pane holding a credential,
#      so the count is over panes seen rather than records read, and a missing
#      record cannot be what makes room for a fifth.
loop_fresh "exec-a1 working" "exec-a2 working" "exec-a3 working" "exec-b1 working"
use_run "${RPT}" tab-a
spawn_on "${TMP}/loop" 1 "128 four unrecorded panes still refuse the fifth" \
  exec-c1 --branch feat/cap-e --provider ccd
if grep -q "4 panes count against ccd's ceiling (none and exec-a1 exec-a2 exec-a3 exec-b1 with no provider record)" \
  "${TMP}/err"; then
  ok "128b and the refusal says they have no provider record"
else
  no "128b and the refusal says they have no provider record" \
    "$(head -3 "${TMP}/err" | tr '\n' '|')"
fi

# 128c. The same bucket is what `status` shows, because a reader counting a
#       provider's panes by hand is the person the ceiling exists for. Recorded
#       providers are named; a pane with no record, or a record this file cannot
#       read, is `unknown` rather than absent.
loop_fresh "exec-161936-1 idle" "exec-161936-2 idle" "rev-t-09 idle"
record exec-161936-1 ccd "${RUN}"
record exec-161936-2 omp "${RUN}"
loop_cmd 0 "128d status prints a provider for every pane" status
if grep -qE '^exec-161936-1 +161936 +ccd' "${TMP}/out" &&
  grep -qE '^exec-161936-2 +161936 +omp' "${TMP}/out" &&
  grep -qE '^rev-t-09 +- +unknown' "${TMP}/out"; then
  ok "128e a record is named, and no record is unknown"
else
  no "128e a record is named, and no record is unknown" \
    "$(tr '\n' '|' <"${TMP}/out")"
fi
printf 'not a record\n' >"${HERDR_TEAM_ROOT}/state/panes/exec-161936-1"
loop_cmd 0 "128f status survives a record it cannot read" status
if grep -qE '^exec-161936-1 +161936 +unknown' "${TMP}/out"; then
  ok "128g and calls that pane unknown rather than crashing on it"
else
  no "128g and calls that pane unknown rather than crashing on it" \
    "$(tr '\n' '|' <"${TMP}/out")"
fi

# 129. The loop never takes a provider's last seat. Three `ccd` panes are live
#       under another Run, so the ceiling of 4 has one left; a `--spawn` wave
#       with a ready `ccd` row stops at 6 rather than spending it. The Run's own
#       cap is not what refuses this — it holds no executor at all — which is
#       what makes the case about the ceiling. A loop that spent it would hold
#       it for the Run's life, since it never settles, and a second tab would
#       find the credential exhausted with nobody at a keyboard to free it.
loop_fresh "exec-a1 working" "exec-a2 working" "exec-a3 working"
record exec-a1 ccd "${RA}"
record exec-a2 ccd "${RA}"
record exec-a3 ccd "${RA}"
loop_on 6 '^loop: T-01 ready and no pane free for them — ccd is one pane below its ceiling of 4' \
  "129 a --spawn wave leaves the provider's last seat alone" \
  --plan "${FIXTURES}/plan-ok.md" --spawn feat/loop
called 0 '^worktree open' "129b and nothing was created for the row it left"

# 129c. The seat is reserved, not forbidden: raise the ceiling by one and the
#       same wave draws the pane it refused above. A guard that refused either
#       way would read the same in 129 and be a cap of three wearing a four.
loop_fresh "exec-a1 working" "exec-a2 working" "exec-a3 working"
record exec-a1 ccd "${RA}"
record exec-a2 ccd "${RA}"
record exec-a3 ccd "${RA}"
FIXTURE_REF=env:HERDR_FIXTURE_KEY
HERDR_FIXTURE_KEY=fixture
HERDR_TEAM_PROVIDER_CAP=5
export FIXTURE_REF HERDR_FIXTURE_KEY HERDR_TEAM_PROVIDER_CAP
loop_on 0 '' "129c one more seat and the same wave spawns" \
  --plan "${FIXTURES}/plan-ok.md" --spawn feat/loop
unset FIXTURE_REF HERDR_FIXTURE_KEY HERDR_TEAM_PROVIDER_CAP
called 1 '^worktree open .* --label exec-0001-1 ' \
  "129d the executor it refused above was drawn"

echo
echo "the ids"

# case_ids — every id this file labels a case with, as the id and the whole
# description it is spent on. An id is the leading token of a description handed
# to one of this file's own helpers, and the helper names are read from the
# file's function definitions rather than listed here: a helper added later is
# covered the moment it is written, and a `grep` pattern — an argument to
# `grep`, which is not a helper — is never read as a description. Continuations
# are joined first, because a label sits on the line after its call as often as
# on it, and an environment prefix is stepped over, because `VAR=1 helper` is
# still a call to `helper`.
case_ids() {
  local helpers
  helpers="$(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$0" | sed 's/()$//' | tr '\n' ' ')"
  awk -v HELPERS="${helpers}" '
    BEGIN { n = split(HELPERS, h, " "); for (i = 1; i <= n; i++) helper[h[i]] = 1 }
    {
      joined = (joined == "" ? $0 : joined " " $0)
      if ($0 ~ /\\$/) { sub(/\\$/, "", joined); next }
      cmd = joined
      sub(/^[ \t]+/, "", cmd)
      while (match(cmd, /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/)) cmd = substr(cmd, RLENGTH + 1)
      sub(/[ \t].*$/, "", cmd)
      if (cmd in helper)
        while (match(joined, /"[0-9]+[a-z]? [^"]*"/)) {
          print substr(joined, RSTART, RLENGTH)
          joined = substr(joined, RSTART + RLENGTH)
        }
      joined = ""
    }
  ' "$0"
}

# 130. The ids themselves, which is the one property no case can assert about
#      its own file. #74 merged two branches that had each spent 53b and 53c, so
#      each of those named two cases apiece and the collision showed up only in
#      the label of a line that failed — the second case invisible in the one
#      place a reader looks when something is wrong. The count floor is here
#      because the failure this case is most likely to suffer is its own: an
#      extraction that reads no ids would report a tidy, empty agreement.
all_ids="$(case_ids | sort -u)"
n_ids="$(printf '%s\n' "${all_ids}" | wc -l | tr -d ' ')"
dup_ids="$(printf '%s\n' "${all_ids}" | sed -E 's/^"([0-9]+[a-z]?) .*/\1/' | sort | uniq -d)"
if [ "${n_ids}" -lt 100 ]; then
  no "130 every case id is unique" \
    "${n_ids} ids read from ${0} — the extraction failed, not the file"
elif [ -n "${dup_ids}" ]; then
  no "130 every case id is unique" "spent twice: $(printf '%s' "${dup_ids}" | tr '\n' ' ')"
else
  ok "130 every case id is unique"
fi

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
