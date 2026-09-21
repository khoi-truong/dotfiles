# herdr adapter

Everything herdr-specific, and every flag and exit code the verbs have. The
installed binary is authoritative for syntax; this file states intent, verified
against herdr 0.9.1.

A pane is `workspace create --cwd … --no-focus` then `pane run`; a dispatch is
`agent prompt` without `--wait`; blocking is `agent wait --until <exact
state>`. The rest is what those cost.

## Verified behaviour

Measured in a throwaway workspace:

- **`pane run` types the command but does not run it**; `pane send-keys <pane>
  enter` submits. Omit it and the spawn hangs with the command on the prompt
  line, identical to a slow start.
- **An agent launched as `zsh -ic cc` is detected in ~4 s**, so the wrapper is
  not a problem, and `agent rename` then `agent get <name>` resolves. Its
  `terminal_title` was the command line, not an identity: titles are not
  authority.
- **`workspace create --env` reaches the root pane only.** A split does **not**
  inherit it (`HERDR_ENV=1` is injected regardless, so proves nothing). Run the
  agent in the **root pane**, `result.root_pane.pane_id`, or pass `--env` again
  on `pane split`. A handoff landing in the main checkout confirmed it.
- **The provider label is on the visible screen only.** `agent read` defaults
  to `--source recent`, which is scrollback from *before* the agent started and
  reports no marker on a correct pane. Read `--source visible`, and retry: the
  status line renders a beat after detection.

## Environment

- **`HERDR_PANE_ID` is the Run key source.** `team.sh` takes the first
  non-empty of `HERDR_TEAM_RUN_KEY`, `HERDR_PANE_ID` and
  `CLAUDE_CODE_SESSION_ID`, falls back to `default`, and sanitises it to
  `[a-z0-9_-]`, since it becomes a path component under `state/`. herdr sets
  it in every pane, so "one orchestrator pane, one Run" holds with nothing to
  export — an agent's own `export` dies with its Bash call, so the pointer
  file, not env, is the primary mechanism. `HERDR_TEAM_RUN_KEY` is the
  deliberate override.
- **`HERDR_TEAM_ROOT` is what a spawn exports**, alongside `OMC_STATE_DIR`: the
  state root, never one Run's handoff directory — that would pin the pane to
  that Run for life, which `protocol.md` forbids. The dispatch prompt carries
  the absolute handoff path anyway.

`HERDR_TEAM_HANDOFFS` overrides one Run's handoff directory whole: the fixture
suite's hook, not a spawn's.

## Hazards

- `agent prompt --wait` **rejects** an already-blocked agent with
  `agent_blocked` and sends no input; with no activity in ~5 s it returns
  `agent_prompt_stalled`. Neither proves input was undelivered.
- `idle` and `done` both mean ready — `done` is awaiting mark-as-seen —
  and `unknown` means present but unclassifiable. Always wait on **exact**
  states, and always include `done`: an agent that finished a dispatch was
  observed settling there, so a wait on `idle` alone hangs on success.
- Reading a full-screen agent past the visible screen makes herdr drive the
  mouse-scroll interface: large reads are **not** passive.
- `agent start --kind claude` execs the binary directly, dropping what
  `ai/claude/providers.zsh` exports and silently billing Pro — hence every
  spawn goes through `pane run "zsh -ic <wrapper>"`.
- Metadata sources cap at **32 `source` ids per pane** for its lifetime and
  clearing releases none, so use one id per pane (`herdr-team`), never one per
  Dispatch. Values cap at **80 characters**: status tokens, not payloads.
- **`agent list` shows every herdr agent in the session**, not only a Run's:
  one started by hand reads exactly like a team pane, so match on the Run's own
  names before treating a row as a dispatch target.
- `workspace.metadata_updated` reaches API subscribers but **not plugin event
  hooks**: the status channel is invisible from inside a plugin.

## `release-agent` is not our settlement verb

`pane release-agent` releases the *reporter's* lifecycle authority over a pane
— `herdr:claude`'s here, not ours — so calling it meddles with state we do not
own. Settling a Dispatch is our own bookkeeping: label it with
`report-metadata` and let teardown close the workspace.

`agent wait` pins the resolved occupant, so a replacement cannot satisfy the
wait: herdr enforces the identity rule itself.

Teardown's landed test without an upstream (`worktrees.md`) is `git merge-tree
--write-tree <default> HEAD` yielding `<default>`'s own tree; a git lacking
`--write-tree` falls back to the stricter count.

## Plans

The `## Tasks` block `--from-plan` reads is specified once, in the
`dispatchable-plan` skill — a skill, since a planning session never says
"herdr". Here: what the adapter does with a row.

`dispatch --from-plan`
builds the body as a **pointer**: the plan's absolute path, the section id, the
files in scope, and the `verify` command the executor must run before claiming
`evidence: verified`. Nothing is copied: the plan lives in the main checkout,
which outlives any worktree, so the orchestrator resolves
`--from-plan`, never the agent.

`blocks` is enforced at dispatch: exit **3** and the unmet ids on stderr unless
each has a `succeeded` + `verified` handoff **under the current Run**.
`--force` overrides with a warning: retry is human-gated, and a gate with no
key is a trap.

`provider` is advisory: the script does not check a row against a live pane,
for the reason under The two caps. Body precedence is argv, then `--from-plan`,
then stdin — stdin only when it is not a terminal, since reading a terminal
hangs with no prompt, looking like a slow dispatch.

`collect --plan <plan.md>` reports the other direction: one row per task in the
plan rather than one per handoff — `done`, `review`, `failed`, `running`,
`ready`, `blocked` — with an exit code (below) saying what to do next. Where a
task has several handoffs the highest `D-nn` wins, so one retried to success
stops reading `failed`.

A task dispatched and not yet answered reads `running`, which handoff files
alone cannot show, so `dispatch` journals every dispatch to `.dispatched` in
that Run's handoff directory — one
`run<TAB>task<TAB>dispatch<TAB>agent` line, written once `herdr agent prompt`
has accepted it. The fourth column is `wait`'s.

`plan lint <plan.md>` prints `depth D  width W  tasks N`, warning above depth 4
or below width 2 once a plan has 3 Tasks: depth is the Dispatches the Run must
take one at a time, width the most it can ever have out at once.

`ai/herdr/tests/run.sh` covers all of this: `shellcheck` and `bash -n`
do not see inside the embedded python, so it is the parser's only check.

## The `wait` verb

`team.sh wait` blocks until one outstanding Dispatch under the Run settles —
outstanding being the fold `running` uses above. A Run has several out and the
caller wants the first, so the verb is a **fan-in**: one backgrounded `herdr
agent wait <agent> --until idle --until done --until blocked` per agent, first to
exit wins, the rest killed. All three states are named for the reason under
Hazards.

**The journal's fourth column exists for this**: `wait` cannot resolve a pane
from a Task id, so `dispatch` writes the agent name. A three-column line
predates the column and is merely un-waitable — skipped with a warning. Any
other width is refused (exit 1): waiting out the readable half of a journal is
how a loop stalls with work outstanding.

**Replay: settled.** A target already in a requested state returns at once — on
0.9.1, 15 ms against an idle pane where the working-agent control blocked the
full 3 s — so an executor that finished before the wait started is not missed.
`agent wait` reads current state rather than consuming a buffered event, so it
escapes the gap `events.subscribe` leaves by not replaying.

**Unsettled.** What a wait does when its pinned agent *exits in place* is
stated nowhere and was not probed — probing means killing a pane in the user's
session. The code assumes it **may** block until `--timeout`, so before
blocking it stats each outstanding handoff once and returns if one appeared
since the journal was read: correct under either answer, with `tests/run.sh`
case 44 staging that window so the guard cannot go dead. An agent that dies
without writing a handoff is uncovered; `--timeout` is the only recovery.

**Exit codes.** One table for the three reading verbs, which agree wherever
they can:

| Code | `collect --plan` | `wait` | `loop` |
| --- | --- | --- | --- |
| 0 | dispatch something | an agent settled | the plan is complete |
| 1 | a human must look | a precondition failed | as `wait` |
| 2 | nothing actionable, something failed | — | a Task failed; retry is human-gated |
| 3 | nothing to do | nothing outstanding | nothing dispatchable, nothing running |
| 4 | — | `--timeout` expired | that, or `--max-waves` reached |
| 5 | — | an agent went `blocked` — `surface` it | as `wait` |
| 6 | — | — | a Task is ready, no pane free |

A bad journal or a missing Run is a 1 everywhere.

4 is not 3 because a timeout is a **checkpoint, not a result** (`SKILL.md` rule
3): "I waited and nothing happened" must be tellable from "there was nothing to
wait for". 5 is not 0 because a blocked agent has written nothing to read, so
the move is `surface`. `wait` reads the winner's `agent_status` for which state
matched, since herdr's own 1 covers a timeout and every other server error
alike.

`surface <name>` is the one read in the verb set: the Run, Task and Dispatch
from the journal, then `agent read --source visible --lines 80`. It has no flag
that sends keys and must not grow one. Where `wait` refuses an unreadable
journal line, `surface` is best-effort: there the screen is the answer, and
refusing to print it withholds what the human came for.

## The `loop` verb

`team.sh loop --plan <plan.md>` repeats the wave — `collect --plan`, dispatch
the `ready` rows through `--from-plan`, `wait` — and returns the first gate it
hits, writing `report` on every exit, a gate's included. `collect`'s 3 is not a
finished plan, so a wave stops on it only when nothing is outstanding.

- `--spawn <branch-prefix>` lets a wave create the panes it needs, up to the
  per-Run cap. Without it a ready row with no free pane is exit 6, handing the
  decision back: a turn saved is not worth a worktree made unasked. `rev-`
  panes are a login rather than a worktree and are uncapped: a review queued
  behind a free executor would serialize behind the thing it checks.
- `--max-waves <n>` (default 20) bounds the run. Reaching it is a 4, like a
  timeout: the Run did not stop, the loop did.
- `--timeout <ms>` is each wave's `wait` timeout, milliseconds and at least
  1000 — a bare `1` reads exactly like a real timeout and expires before any
  agent could answer.

A free pane takes the next Task **in its own lane** — the same branch and
files, which is how a chain stacks onto one pane — never across lanes, which
would carry one Task's worktree into unrelated work.

## `report`

`team.sh report [<run>] [--plan <plan.md>] [--no-write]` prints a row per Task
— `task`, `dispatch`, `outcome`, `evidence`, `provider`, `sends`, `lines`,
`verify` — writes `report.json` beside the handoffs and appends one line to
`.herdr/metrics.jsonl`, never twice for a Run. Rows are the Run's Tasks, not
the plan's: a Dispatch with no plan row is an anomaly a plan-only table hides.
Wall time is approximate: the journal keeps no timestamps, so it is the newest
handoff's mtime against the Run directory's.

## The two caps

`HERDR_TEAM_EXEC_CAP` (default 2) is per Run, counted over the panes this Run
holds; `HERDR_TEAM_PROVIDER_CAP` (default 4) is per provider across every Run.
A refusal names the limit it hit and, for the per-Run cap, only panes the
reader can settle.

`spawn` records each pane in `state/panes/<name>` — name, provider, Run,
worktree, spawn time — and `settle … release` and `teardown` remove it. The
provider count reads those files: a provider is not passively readable off a
screen, and `agent list` is per session, so five sessions would each count only
their own and spawn to the ceiling. A pane with no record counts as `unknown`:
an uncounted pane is the one that exhausts a key.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live
agents; `team.sh` enforces both at spawn.
