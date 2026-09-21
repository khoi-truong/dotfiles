---
name: dispatchable-plan
description: >-
  How to write a plan whose tasks a script can hand to agents without a human
  retyping them: a `## Tasks` json block, one row per task, naming the files in
  scope, the command that proves the task done, and the tasks it waits on. Use
  when writing or revising any multi-task implementation plan, work breakdown,
  or task list that something other than the author might execute — especially
  one destined for parallel or delegated execution. Fires on "implementation
  plan", "task breakdown", "plan file", "tasks block", "dispatchable plan",
  "plan lint", even when nothing mentions agents or herdr.
---

# Dispatchable plans

A plan is dispatchable when a script can build an executor's prompt from it
with no human in the middle. That takes one machine-readable block; the rest of
the plan stays prose for humans.

Emit this block whenever a plan has more than one task and someone other than
you might run them. It costs four lines per task and removes the step where an
orchestrator retypes the work — which is where task ids drift and scope leaks.

## The block

A `## Tasks` heading, then exactly one fenced `json` block, then a `### T-nn`
prose section per row:

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "cc", "files": ["README.md"], "verify": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1", "blocks": ["T-01"]}
]
```

| Field | Meaning |
| --- | --- |
| `task` | `T-nn`. Unique in this plan, and matching a `### T-nn` section. |
| `provider` | Advisory: who should run it. Nothing enforces it. |
| `files` | The paths in scope. Named in the prompt, so scope is stated, not inferred. |
| `verify` | The command that proves the task done. It must be able to fail. |
| `blocks` | Task ids that must be verified before this one may start. `[]` for none. |

JSON rather than a markdown table because `verify` commands contain pipes and
commas; JSON rather than YAML because the parser is stdlib `python3`, which has
no YAML, and this takes no new dependency.

## The rules the parser enforces

Run `ai/herdr/team.sh plan lint <plan.md>` on your own output. It prints every
problem at once and exits 1 if there are any, so a plan can carry
`evidence: verified` for its own shape rather than `heuristic`.

- **Every row needs a `### T-nn` section, and every section needs a row.** A
  row with no section dispatches someone to read nothing; a section with no row
  is work nobody will be sent to do.
- **`blocks` may only name task ids that exist.** A blocker with no row never
  settles, so the task waits forever — which reads like "not yet" and means
  "never".
- **`blocks` may not form a cycle.** Two tasks each waiting on the other is
  undispatchable, and no per-task check can see it: the row for T-01 only knows
  it waits on T-02.
- **A `verify` containing a pipe must lead with `set -o pipefail`.** This one
  is worth the paragraph below.

## `verify` must be able to fail

A pipeline exits with its *last* stage's status. `npx markdownlint-cli2 README.md
| tail -1` exits 0 however markdownlint exited, so an executor runs it, observes
0, and claims `evidence: verified` on a check with no power to fail. That turns
the top of the evidence ordering into a rubber stamp and unblocks everything
downstream of it.

Lead with `set -o pipefail`, which is correct regardless. The check is narrow —
an unquoted `|` with no `set -o pipefail` — and will flag a deliberate pipeline;
the remedy is the same either way.

The same reasoning rules out `verify` commands that cannot fail for other
reasons: `... || true`, a `grep` whose absence of output is the pass condition,
or a bare `echo done`. The parser cannot catch those. You can.

A `verify` must also cover what CI will check on the files the task touches,
not only the task's own tests. A task that edits a shell script and verifies
with `bash ai/herdr/fixtures/run-tests.sh` reads `done`, then fails CI on
shellcheck or editorconfig — `verified` claimed more than the command proved.
Chain the lint in: `bash scripts/ci/lint-local.sh && bash
ai/herdr/fixtures/run-tests.sh` runs the checks CI runs, locally, before the
tests.

**This rule is checked now, not just stated.** A task reaches `done` only when
its winning handoff's `commands:` names the row's own `verify` at `exit: 0` —
the executor records what it ran, and the table compares. If it does not, the
row reads `review` with `UNVERIFIED` in the cause column (`UNPARSED` for a value
nothing can read as JSON, which is what a handoff written before that contract
looks like), and every dependent of it stays `blocked`. A `verify` that never
ran therefore costs a review rather than nothing. The match is a substring,
because the command reaches the handoff through an agent and a `cd` or a quote
around it is still the same command; the exit code is required alongside it.
Mechanism: `collect --plan` in `ai/herdr/team.sh`, described in the `herdr-team`
skill's `references/herdr-adapter.md`.

## Reviewers are ordinary rows

A review is work, so it gets a row like anything else, with `blocks` naming
what it reviews:

```json
[
  {"task": "T-03", "provider": "cc", "files": ["ai/herdr/team.sh"], "verify": "bash ai/herdr/fixtures/run-tests.sh", "blocks": ["T-02"]}
]
```

There is no separate review mechanism and no implicit review step. A plan that
wants one says so in a row.

## Writing the prose sections

The `### T-nn` section is what the executor actually reads; the row is only the
pointer. Nothing is copied into the prompt, so the section must stand alone:
what to change, what "done" looks like, and any constraint that is not obvious
from the files. Acceptance criteria belong here, and each one should be a
command — a criterion satisfied by reading something is not a gate.

Keep tasks serial unless they touch genuinely disjoint files. Two tasks editing
one file concurrently means one merges onto work it never saw.

`plan lint` prints `depth D  width W  tasks N` and warns on both, because both
are costs. Depth is the Dispatches the Run must take one at a time; width is the
most it can ever have out at once, so a plan deeper than 4 or — once it has 3
tasks — narrower than 2 is a queue wearing a plan's shape. Task size is the same
argument one level down: a Dispatch has fixed overhead — a prompt, a pane, a
handoff, a collect — so a task is worth a row when it is worth a Dispatch, and
two chained rows on one file are one task written twice.

## What consumes this

`ai/herdr/team.sh` — `dispatch --from-plan` builds an executor's prompt from a
row, refusing to start a task whose blockers have no verified handoff under the
current Run; `collect --plan` reports every task's state; `plan lint` checks the
document. See the `herdr-team` skill for the protocol those commands implement.

The format is useful without any of that. A plan with a `## Tasks` block is a
plan whose scope, proof and ordering are stated rather than implied, which is
worth having even when a human runs every task by hand.
