---
name: herdr-team
description: >-
  Protocol for running coding agents in separate herdr panes, one git worktree
  each, coordinated through files on disk: one orchestrator the user talks to,
  N executors in worktrees, and ephemeral spec, research and review panes.
  Covers work identity (Run/Task/Dispatch), the completion contract, liveness,
  settlement, worktree lifecycle, memory tiers and per-stage model tiering.
  Use when the work needs real process isolation — spawning or tearing down an
  agent pane, dispatching to an agent in another worktree, collecting a
  handoff file, or choosing which provider a piece of work belongs on. Fires
  on "herdr team", "spawn an executor", "worktree agent", "dispatch", "handoff",
  "team.sh". Not for in-process fan-out inside one pane: that is OMC's `/team`
  skill, which shares the word and nothing else.
---

# herdr agent team

One pane holds the user. Everything else is dispatched work.

**Two things are called "team" here.** OMC's `/team` skill fans work out to
in-process subagents inside a single pane. This one is panes — one agent per
pane, one git worktree each, state on disk. When either would work, reach for
`/team` first: this costs more and buys process isolation. The tell is what
you invoke: `/team` is a skill, this is `ai/herdr/team.sh`.

The protocol is the artifact; herdr is an implementation detail. Read
`references/protocol.md` for the substrate-independent rules and
`references/herdr-adapter.md` for the commands that implement them.

## Roster

A role earns a pane only if it needs a different provider, a different cwd, a
long life, or visibility. Everything else is an in-process subagent.

| Role | Pane | Provider | Location |
| --- | --- | --- | --- |
| `orchestrator` | standing | `cc` | main checkout |
| `spec-<round>` | ephemeral | `cc` | main checkout |
| `res-<topic>` | ephemeral | `omp` | main checkout |
| `plan-<task>` | ephemeral | `cc` | main checkout |
| `exec-<run-suffix>-N` | 2 live, 3 by config | `ccd` | one worktree each |
| `rev-<task>` | ephemeral | `cc` | the executor's worktree |

critic, architect and verifier are in-process subagents, never panes. For
fan-out inside one pane, use OMC `/team`; do not reimplement it.

**A suffix means there can be more than one of me.** `orchestrator` is bare
because it is singular — one pane holds the user, and it is the only standing
role. There is no standing `spec`: a spec or research round is spawned for that
round, writes its artifact, and settles. A long-lived planning pane's only asset
is accumulated context, which rule 5 already says to distrust.

Pool roles match by prefix and may spawn up to the cap of **2** concurrent
executors (`HERDR_TEAM_EXEC_CAP=3`, only when all three are genuinely
independent). **The cap is the machine's, not the Run's.** `spawn` counts every
live `exec-` pane under *every* Run and refuses past the cap, naming the ones
already live, because what is contended is auth — one DeepSeek key, one Pro
login — and two orchestrator tabs share it. A per-Run count would let each tab
start two and call it discipline. Only `exec-` is capped: `spec-`, `res-` and
`rev-` panes are never blocked by a busy executor pool.

Executors are named `exec-<run-suffix>-N`, the suffix being the `hhmmss` of the
Run id. It is a readability convention, not an enforced one — `status` prints
that suffix as a `run` column, so a table spanning three orchestrators reads as
three groups rather than a flat row of `exec-1`, and a hand-named pane still
works with a dash there.

## The five rules that matter

1. **Identity comes from the Dispatch**, never from an agent name or a pane
   title. Every prompt and every handoff carries its Run, Task and Dispatch id.
2. **Report exactly once, even on failure.** A silent failure is a protocol
   defect, not an unlucky run. `outcome: succeeded` at `evidence: reported` is
   a claim, not a result.
3. **Absence is never evidence.** A timeout is a checkpoint. Read before
   retrying; only positive proof settles a Dispatch; retry is human-gated.
4. **Settle immediately, exactly once** — reuse, retain or release. "Decide
   later" is how six stale panes accumulate.
5. **State lives in files.** A transcript is never the source of truth. Write
   the handoff before compacting.

## Prohibitions

- Never auto-answer an approval dialog. `team.sh surface <name>` puts it in
  front of the human with the Run, Task and Dispatch attached; answering happens
  in that pane, by the human, and no verb here can do it.
- Never read a transcript on the success path. Results travel by file; reads
  are a diagnostic for blocked or stalled agents, capped at ~80 lines.
- Never put two agents in one directory. The substrate gives no isolation.
- Never poll. Subscribe to `pane.agent_status_changed`, and subscribe *before*
  dispatching — subscriptions do not replay. Blocking is `team.sh wait`: one
  herdr wait per outstanding Dispatch, returning on the first settle, not a
  question asked on a timer.
- Never let a plugin start an agent or pick its provider.

## Cost

Pro (`cc`) for plan, spec, review and merge; `omp` for research, which is a
capability axis rather than a price one. DeepSeek (`ccd`) for implementation,
tests, lint and CI fixes. The orchestrator routes; it does not judge, so it is
never the most expensive thing running. Details in `references/cost.md`.

## Tooling

`ai/herdr/team.sh` — `run`, `spawn`, `dispatch`, `status`, `collect`, `wait`,
`surface`, `plan`, `settle`, `teardown`. `prefix+alt+t` shows the status table.
The script owns topology; this skill owns the protocol.

Only `team.sh` starts an agent. It is the only place that knows `cc` and `ccd`
are shell functions rather than binaries, which is what keeps work off the
wrong provider.

**Dispatch through `team.sh dispatch`, not by typing into a pane.** The
completion contract above is what the command emits, filled in from the current
Run: hand-writing it is how ids drift and handoffs go missing. It refuses a
Task/Dispatch pair whose handoff file already exists, and with no `--dispatch`
it picks the lowest unused id — which is the never-reuse rule made mechanical
rather than remembered. `--dry-run` prints the prompt instead of sending it.
`herdr agent prompt` rejects a blocked agent before sending anything, so a
dispatch can never answer an approval dialog.

Three things the table does not say for you:

- **`status` lists every herdr agent**, not only the ones this Run spawned. An
  agent you started by hand in another workspace appears in the roster exactly
  like a team pane. Match on the Run's own names before reading a row as a
  dispatch target.
- **`release` refuses a worktree holding work that exists nowhere else.** It
  delegates to `teardown`, which measures the branch against its upstream — or,
  with no upstream, against the default branch — and refuses what is ahead of
  it, correctly, since releasing would destroy it. A branch with nothing ahead
  tears down cleanly. When there is real work the order is `settle <name>
  retain`, push, then `settle <name> release`; settlement is still immediate and
  exactly once, and the retain is the recorded decision the release licenses.
- **The Run id lives in a file**, `.herdr/state/run-<key>`, not in the
  transcript, and **one orchestrator pane is one Run**. The key is the first
  non-empty of `HERDR_TEAM_RUN_KEY`, `HERDR_PANE_ID` or
  `CLAUDE_CODE_SESSION_ID`, falling back to `default`, so a second tab driving
  a second plan mints its own Run, writes into its own handoff directory, and
  gets its own `D-01` instead of colliding with the first. `run new --plan
  <plan.md>` also links the plan's absolute path to the Run, so `run resolve
  <plan.md>` recovers the id after the pointer file is gone — the plan path is
  the one identifier that survives compaction and pane death. Start a Run
  before dispatching; a compaction or a dead pane then costs nothing.

**`collect --plan <plan.md>` is how the orchestrator picks its next move.** It
prints one row per task in the plan — `done`, `review`, `failed`, `running`,
`ready`, `blocked` — and its exit code says what to do without reading the
table back: **0** dispatch something, **1** a human must look, **2** nothing
actionable and a task failed, **3** nothing to do. That is the alternative to
diffing `collect` against the plan by hand every turn, which is the pattern
`references/cost.md` calls the configuration to avoid. It reports and never
decides: nothing it does writes state or blocks a dispatch.

**The loop is dispatch → `wait` → `collect --plan` → dispatch what is `ready`,
and it needs no one watching a pane.** `team.sh wait` blocks until one
outstanding Dispatch under the Run reaches a terminal agent state, prints which
agent and Task settled, and reports nothing about the outcome — the table is
what reports that. It is scoped to **its own Run**: a Dispatch another tab has
outstanding is invisible to it and can never end its wait, and with nothing
outstanding under this Run it returns 3 rather than blocking on someone else's
work. Then `collect --plan` says what the next move is. The exit
codes are stated once, in `references/herdr-adapter.md`; the two that shape the
loop are that a `--timeout` expiry is not the same answer as "nothing to wait
for", and that an agent which went `blocked` is a different move again — no
table to read, so `surface` it instead.

The format it reads is the `dispatchable-plan` skill's, and `team.sh plan lint
<plan.md>` checks a plan against it before anything is spawned.
