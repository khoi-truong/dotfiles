---
name: herdr-team
description: >-
  Protocol for running coding agents in separate herdr panes, one git worktree
  each, coordinated through files on disk: one orchestrator the user talks to,
  N executors in worktrees, and ephemeral spec, research and review panes.
  Use when the work needs real process isolation — spawning or tearing down an
  agent pane, dispatching to an agent in another worktree, or collecting a
  handoff file. Fires
  on "herdr team", "spawn an executor", "worktree agent", "dispatch", "handoff",
  "team.sh". Not for in-process fan-out inside one pane: that is OMC's `/team`
  skill, which shares the word and nothing else.
---

# herdr agent team

One pane holds the user. Everything else is dispatched work.

**Two things are called "team" here.** OMC's `/team` skill fans out to
in-process subagents inside one pane; this one is panes — one agent per pane,
one git worktree each, state on disk. When either would work, reach for `/team`
first: this costs more and buys process isolation. The tell: `/team` is a
skill, this is `ai/herdr/team.sh`.

The protocol is the artifact; herdr is an implementation detail.
`references/protocol.md` holds the substrate-independent rules,
`references/herdr-adapter.md` the commands that implement them.

## Roster

A role earns a pane only if it needs a different provider, a different cwd, a
long life, or visibility. Everything else is an in-process subagent — critic,
architect and verifier always are; for fan-out inside one pane use OMC `/team`.

| Role | Pane | Provider | Location |
| --- | --- | --- | --- |
| `orchestrator` | standing | `cc` | main checkout |
| `spec-<round>` | ephemeral | `cc` | main checkout |
| `res-<topic>` | ephemeral | `omp` | main checkout |
| `plan-<task>` | ephemeral | `cc` | main checkout |
| `exec-<run-suffix>-N` | 2 live, 3 by config | `ccd` | one worktree each |
| `rev-<task>` | ephemeral | `cc` | the executor's worktree |

**A suffix means there can be more than one of me.** `orchestrator` is bare
because it is singular, and the only standing role. There is no standing
`spec`: a spec or research round is spawned for that round, writes its
artifact, and settles. A long-lived planning pane's only asset is accumulated
context, which rule 5 already says to distrust.

Pool roles match by prefix and may spawn up to the cap of **2** concurrent
executors (`HERDR_TEAM_EXEC_CAP=3`, only when all three are genuinely
independent). **The cap is the machine's, not the Run's:** `spawn` counts every
live `exec-` pane under *every* Run, because what is contended is auth — one
DeepSeek key, one Pro login — and two orchestrator tabs share it. A per-Run
count would let each tab start two and call it discipline. Only `exec-` is
capped.

Executor names carry the Run's `hhmmss` as their suffix — a readability
convention, not an enforced one, so a status table spanning three orchestrators
reads as three groups.

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
  front of the human; answering happens in that pane, by them.
- Never read a transcript on the success path. Results travel by file; a read
  is a diagnostic for a blocked or stalled agent, capped at ~80 lines.
- Never put two agents in one directory. The substrate gives no isolation.
- Never poll. Blocking is `team.sh wait`, not a question asked on a timer; a
  subscription must be opened *before* dispatching, since they do not replay.
- Never let a plugin start an agent or pick its provider.

## Cost

Tiering is per stage, and the discriminator is verifiability, not price: the
cheap tier is safe wherever a command catches a wrong answer. The orchestrator
routes rather than judges, so it is never the most expensive thing running.
Table in `references/cost.md`.

## Tooling

`ai/herdr/team.sh` — `run`, `spawn`, `dispatch`, `status`, `collect`, `wait`,
`surface`, `plan`, `settle`, `teardown`; `prefix+alt+t` shows the status table.
The script owns topology, this skill owns the protocol, and the flags and exit
codes are stated once, in `references/herdr-adapter.md`.

Only `team.sh` starts an agent: it is the only place that knows `cc` and `ccd`
are shell functions rather than binaries, which is what keeps work off the
wrong provider.

**Dispatch through it too, never by typing into a pane.** `dispatch` emits the
completion contract filled in from the current Run — hand-writing it is how ids
drift and handoffs go missing — and picks the lowest unused Dispatch id, the
never-reuse rule made mechanical rather than remembered. herdr rejects a
blocked agent before sending, so a dispatch can never answer an approval
dialog.

Two things the verb list does not say:

- **`release` refuses a worktree holding work that exists nowhere else**, since
  releasing would destroy it. The order is then `settle <name> retain`, push,
  `settle <name> release` — the retain being the recorded decision the release
  licenses.
- **The Run id lives in a file**, not in the transcript, and **one orchestrator
  pane is one Run** — a second tab driving a second plan mints its own Run and
  its own `D-01`. `run new --plan <plan.md>` links the plan's absolute path to
  the Run, so `run resolve <plan.md>` recovers the id once that file is gone:
  the plan path is the one identifier that survives compaction and pane death.
  Start a Run before dispatching, and a dead pane costs nothing.

**The loop is dispatch → `wait` → `collect --plan` → dispatch what is `ready`,
and it needs no one watching a pane.** `wait` blocks until one outstanding
Dispatch under the Run settles and reports nothing about the outcome;
`collect --plan <plan.md>` reports it, one row per task in the plan, with an
exit code saying what to do without reading the table back. Both are scoped to
**their own Run**, so another tab's outstanding Dispatch can never end this
Run's wait. That is the alternative to diffing `collect` against the plan by
hand every turn. Neither decides anything: nothing they do writes state or
blocks a dispatch.

The plan format is the `dispatchable-plan` skill's, and `team.sh plan lint
<plan.md>` checks a plan against it before anything is spawned.
