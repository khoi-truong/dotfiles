# The protocol

Substrate-independent; no herdr commands here.

## Object model

| Object | Meaning | Lifetime |
| --- | --- | --- |
| **Run** | one user objective; durable namespace and inbox, one per orchestrator | survives pane death |
| **Task** | one unit of work within the Run | until settled |
| **Dispatch** | one *authoritative attempt* at a Task | until settled; never reused |

Ids are `R-<yyyymmdd-hhmmss>`, `T-<nn>`, `D-<nn>`: `T-03/D-02` is the second
attempt at task three.

- Authority derives from the **active Dispatch**: two panes may be called
  `exec-a` over a Run's life, and only one Dispatch is ever current for a Task.
  Every message and every handoff carries both ids.
- Ids are **immutable within a Run** and a settled one is never reused, which
  is what stops a stale retry completing the wrong work. Uniqueness need hold
  only *within* the Run, because a handoff is scoped by the **Run's own
  directory** rather than filtered out of a shared namespace: `T-01/D-01` in
  two concurrent Runs never meet, and two orchestrators in one checkout are two
  Runs with no shared state.
- A **pane belongs to no Run; only a Dispatch does.** A pane retained after one
  Run's Task settles may be dispatched by another, and the handoff it writes
  belongs to the Run that dispatched it, not the one that spawned it. Nothing
  handed to a pane at spawn may pin it to a Run for life.

## Dispatch

There is no capability scoring — no shipped system implements one. Enumerate
agents with their live status; classify the task **judgment** or **volume**,
which selects the role; resolve by cardinality, a singular role matching its
name **exactly** and a pool role by **prefix**; rank ready first, busy last,
**blocked never**, queueing at the cap. A status that cannot be confidently
classified is **not** proof of readiness.

Shape the work **wide, not deep**: parallel waves over chains more than three
or four deep. Depth is where these systems fail and width is cheap. Planning
and implementation parallelize; **merge is serialized**.

### Ordering is a predicate, not a memory

When a plan declares which Tasks block which, "blocked never" stops being
something the orchestrator remembers and becomes something the dispatcher
refuses: a Task is dispatchable only when **every** Task it blocks on has a
`succeeded` **and** `verified` handoff — a `reported` success does not settle
it — under the current Run.

That last clause is not pedantry: Task ids restart at `T-01` every Run, so an
earlier Run's handoff answers to the same id and would silently unblock work it
never did. The scoping is **structural first** — the dispatcher reads only this
Run's handoff directory, so another Run's `T-01-D-01.md` is not filtered out,
it is not there to be read — and the redundant `run:` field stays for what that
leaves: a file hand-placed in the right directory with the wrong Run.

A refusal is not a retry decision: retry stays human-gated, so the dispatcher
offers an explicit override rather than gating a human out.

## Completion contract

Every dispatched agent is told, verbatim and never reconstructed: its Task and
Dispatch id, the handoff's absolute path, and that it reports **exactly once,
even on failure**.

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

**Commit the work before writing the handoff.** The handoff claims the Task is
done, and an uncommitted tree makes that claim unrecoverable if the pane dies.
`teardown` refuses a dirty tree, so a Run that never commits ends with every
worktree unreleasable, and a reused pane leaves two Tasks in one tree with no
boundary between them. The commit is also what makes `files_changed:`
checkable rather than taken on trust.

Write atomically — `<name>.md.tmp` then `mv` — so the orchestrator never reads
a half-written file. **Over 150 lines is a defect**: summarize, never paste.

`evidence` is ordered: `verified` (a command ran and its exit code was
observed), then `reported` (the agent says so), then `heuristic`, then
`asserted`. A Task does not settle on a `reported` success; it waits for a
`rev-` pass to raise it to `verified`. `cause` is typed so the retry decision
reads a field instead of prose.

`artifacts` is for documents where `files_changed` is for edits: the absolute
path of whatever a workflow the agent invoked wrote in that workflow's own
place. A **receipt, not a copy** — the orchestrator is handed a path, and does
not open it.

## Liveness

The likeliest failure mode. A timeout or a stalled prompt **does not prove no
input was sent**: contact loss is not process death.

- **Read before retrying.** A blind retry can double-submit a prompt, and on a
  spawn failure what leaked is only readable before relaunching.
- A checkpoint authorizes **nothing**: not stopping, retrying, releasing or
  relaunching.
- After **three consecutive empty waits**, enumerate the roster and inspect
  state instead of blocking again.

Recorded as fields — `prompt_acknowledged`, `last_output_at`, `queued_input` —
so the rules read data, not prose. `queued_input: true` makes "read before
retrying" mechanical: it records that input may already be in flight, which a
timeout cannot tell you.

## Settlement

When a Dispatch settles, do **exactly one**, immediately:

- **reuse** — the same pane takes follow-up work under a new Task/Dispatch;
- **retain** — keep the pane for inspection, as a recorded choice;
- **release** — tear the pane and its worktree down.

No fourth option, no "later". Settling is automatic on a valid completion
message; status is never edited by hand.

## Ambiguity

Locked at the start of a Run, so unattended work resolves ambiguity
deterministically rather than inventing scope: `prefer-smaller-scope`
(**default**) does less on doubt and says so under `## What remains`;
`prefer-complete` does the fuller thing. Anything needing a human decision
surfaces to the user.
