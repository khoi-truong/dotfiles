# The protocol

Substrate-independent. No herdr commands appear here; see `herdr-adapter.md`.

## Object model

| Object | Meaning | Lifetime |
| --- | --- | --- |
| **Run** | one user objective; durable namespace and orchestrator inbox, one per orchestrator | one task, survives pane death |
| **Task** | one unit of work within the Run | until settled |
| **Dispatch** | one *authoritative attempt* at a Task | until settled; never reused |

Ids are `R-<yyyymmdd-hhmmss>`, `T-<nn>`, `D-<nn>`. `T-03/D-02` reads as the
second attempt at task three.

- Authority derives from the **active Dispatch**, never from an agent name, a
  pane id, or a pane title. Two panes may be called `exec-a` over a Run's life;
  only one Dispatch is ever current for a Task.
- Task and Dispatch ids are **immutable within a Run**, and a settled id is
  never reused. This is what stops a stale retry completing the wrong work.
  The id is unique *within its Run*, which is what makes the uniqueness
  affordable: what scopes a handoff name is the **Run's own directory**, not a
  filter over one shared namespace, so `T-01/D-01` in two concurrent Runs is
  two files that never meet.
- Every message and every handoff file carries **both** ids.
- A Run is **namespaced per orchestrator**: one orchestrator pane holds one
  Run. Two orchestrators driving two objectives in one checkout are two Runs
  with two id sequences, two handoff directories and no shared state — not two
  views of one Run taking turns.
- A **pane belongs to no Run; only a Dispatch does.** A pane retained after one
  Run's Task settles may be dispatched by another Run, and the handoff it then
  writes belongs to the Run that dispatched it, never to the one that spawned
  it. Nothing handed to a pane at spawn may pin it to a Run for its lifetime.

## Dispatch

There is no capability scoring — no shipped system implements one. The whole
algorithm is:

1. Enumerate agents with their live status.
2. Classify the task **judgment** or **volume**; that selects the role.
3. Resolve by cardinality. The one singular role (`orchestrator`) matches its
   name **exactly**; if busy, queue. A pool role (`exec-`, `spec-`, `res-`,
   `plan-`, `rev-`) matches by **prefix** and may spawn up to the cap.
4. Rank: ready first, busy last, **blocked never**.
5. At the cap, queue. Never spawn past it.
6. A status that cannot be classified confidently is **not** proof of
   readiness. Treat it as unavailable.

Shape the work **wide, not deep**: prefer parallel waves to dependency chains
deeper than three or four steps. Depth is where these systems fail; width is
cheap. Planning and implementation parallelize; **merge is always serialized**.

### Ordering is a predicate, not a memory

When a plan declares which Tasks block which, "blocked never" stops being
something the orchestrator remembers and becomes something the dispatcher
refuses. A Task is dispatchable only when **every** Task it blocks on has a
handoff that is `succeeded` **and** `verified` — a `reported` success does not
settle it, by the rule below — **and** that handoff belongs to the current Run.

The Run clause is not pedantry. Task ids restart at `T-01` every Run, so a
handoff left by an earlier Run answers to the same Task id and will unblock
work it never did, silently, unless the predicate is scoped to the Run.

The scoping is **structural first**: the dispatcher reads only the current
Run's handoff directory, so another Run's `T-01-D-01.md` is not filtered out —
it is not there to be read. The `run:` field in the frontmatter stays and is
now redundant, which is the point: a file hand-placed in the right directory
with the wrong Run still cannot unblock work.

A refusal is not a retry decision. Retry stays human-gated, so the dispatcher
must offer an explicit override rather than leaving a human with no way past
its own gate.

## Completion contract

Every dispatched agent is told, verbatim and never reconstructed: its Task and
Dispatch id, the absolute path of the handoff file it must write, and that it
must report **exactly once, even on failure**.

```markdown
---
run: R-20260919-141530
task: T-03
dispatch: D-01
outcome: succeeded | failed | blocked
cause: null | timeout | blocked_on_approval | tool_error | precondition_failed
evidence: verified | reported | heuristic | asserted
files_changed: [path, ...]
artifacts: [path, ...]
commands: [{cmd: "...", exit: 0}, ...]
---

## What was done
## What was found
## What remains
```

Write atomically — `<name>.md.tmp` then `mv` — so the orchestrator never reads
a half-written file. **Over 150 lines is a defect**; summarize rather than
paste. Findings and verdicts are fielded; narrative is prose.

`evidence` is ordered: `verified` (a command ran and its exit code was
observed) outranks `reported` (the agent says so) outranks `heuristic` outranks
`asserted`. A Task does not settle on a `reported` success — it waits for a
`rev-` pass to raise it to `verified`.

`cause` is typed so the retry decision reads a field instead of prose.

`artifacts` is for documents, where `files_changed` is for edits: the absolute
path of anything a workflow the agent invoked wrote in that workflow's own
place. It is a **receipt, not a copy** — the orchestrator is handed a path and
does not open it, and the path is never moved into the coordination store.

## Liveness

The likeliest failure mode. A timeout or a stalled prompt **does not prove no
input was sent**, and contact loss is not process death.

- **Read before retrying.** Always. A blind retry can double-submit a prompt.
- A timeout or empty wait is a **checkpoint, not a failure**. It authorizes
  nothing: not stopping, not retrying, not releasing, not relaunching.
- Only **positive proof** settles a Dispatch — an observed process exit, or the
  agent's own completion message.
- After **three consecutive empty waits**, enumerate the roster and inspect
  state rather than continuing to block.
- **Retry is human-gated.** On a spawn failure, read what failed and what
  leaked; do not relaunch.

Recorded as fields, so the rules are evaluated against data:

```yaml
liveness:
  prompt_acknowledged: true | false
  last_output_at: <iso8601 | null>
  queued_input: true | false
```

`queued_input: true` is what makes "read before retrying" mechanical: it
records that input may already be in flight, which is exactly what a timeout
cannot tell you.

## Settlement

When a Dispatch settles, do **exactly one** of these, immediately:

- **reuse** — hand the same pane follow-up work under a new Task/Dispatch;
- **retain** — keep the pane for inspection, recorded as a deliberate choice;
- **release** — tear the pane and its worktree down.

There is no fourth option and no "later". Settling is automatic on a valid
completion message; status is never edited by hand.

## Ambiguity

Locked at the start of a Run so unattended work resolves ambiguity
deterministically instead of inventing scope:

- `prefer-smaller-scope` (**default**) — on doubt, do less and say so under
  `## What remains`.
- `prefer-complete` — on doubt, do the fuller thing.

Anything needing a human decision surfaces to the user. Approval dialogs are
never auto-answered.
