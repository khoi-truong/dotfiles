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

- **`HERDR_TEAM_REPO` is the transport for a Run bound to a project repo.**
  `run new --repo <path>` writes the resolved path once, to `runs/<id>/repo`;
  `team.sh` reads that file and exports `HERDR_TEAM_REPO` from it on every
  later call against that Run. `--repo <path>` on a single `config`/`config
  trust` call is a plain argument to `config.py`, naming the repo for that one
  call without touching the environment or any Run's file. Never inferred
  from `$PWD` — omit it and every verb reads the dotfiles checkout, which is
  the default. Layers 3–4
  (`<repo>/.config/herdr/team*.toml`) stay untrusted until `config trust`
  records the repo's path and the sha256 of both files; that record is not a
  security boundary against an agent that already has a shell, since anything
  with a shell can edit the trust file directly. `teardown` on a project repo
  only removes the worktree (`worktree remove` or, on the checkout's own
  cleanup path, `worktree prune`) and never runs `git tidy`, which is a
  dotfiles-only alias the project repo has no reason to define.

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

`provider` is a tier, and the script checks it against the row's own shape
rather than against a live pane — the count of panes is under The two caps. A
row with a `verify` is `ccd`; a `cc` row carries a `tier_reason` string saying
which of the three things no command settles it is, and `plan lint` warns about
one that does not. `spawn --provider cc` refuses without `--tier-reason
"<why>"`: nothing there can tell a review from a row that was mislabelled.

Body precedence is argv, then `--from-plan`, then stdin — stdin only when it
is not a terminal, since reading a terminal hangs with no prompt, looking like
a slow dispatch.

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

`dispatch` picks the next id from that journal **and** the handoff files, since
they are the same claim made twice and they disagree in exactly one case: a
Dispatch torn down before it could write a handoff is in the journal and in no
file, so a reader of files alone hands out `D-01` a second time. An `--dispatch
<id>` naming one already in the journal is refused for the same reason — the id
is spent whether or not a handoff followed it, and the matcher is `next_dispatch`'s,
so the two cannot drift apart. `teardown`
appends the pane's outstanding lines to `.abandoned` beside the journal, in the
same shape, because destroying the pane is what makes them unanswerable — the
Dispatch happened, the handoff is not coming. `wait` and `collect --plan` skip
those lines rather than blocking on an agent herdr no longer knows, or reading
the Task as `running` for as long as anyone cares to look.

A second journal, `.providers`, is keyed `(task, dispatch)` and holds the tier a
Dispatch was sent to and the one it fell back from, because `state/panes/<name>`
does not survive `release` — and `report` has to answer for a Run after every
pane in it is gone. It is written by the same `dispatch` that writes
`.dispatched`, at the last moment the pane record certainly exists.

`teardown` marks a pane it no longer knows only with `--abandon-only`: herdr
cannot close a pane that is not there, but the Run can still abandon what that
pane left outstanding, which is what stops those Tasks reading `running`
forever. Plain `teardown` refuses — `--force` and `--abandon-only` are the two
ways to say which you meant.

`plan lint <plan.md>` prints `depth D  width W  tasks N`, warning above depth 4
or below width 2 once a plan has 3 Tasks: depth is the Dispatches the Run must
take one at a time, width the most it can ever have out at once. It also warns
about a `cc` row that has a `verify` and no `tier_reason` — a command settles
that row, so it is a `ccd` row unless the plan says which of the three
exceptions it is. Warnings go to stderr behind a `lint:` prefix and change no
exit code: the tier reading is legitimate for a review, and only the plan's
author knows which it is.

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
| 6 | — | — | a Task is ready and no pane took it |

A bad journal or a missing Run is a 1 everywhere.

6 is the gate for a decision only a human can take, and `spawn` returns it for
the Pro window's two refusals above — nobody knows what the window is, or Pro
is what a full one cannot spare. Its other refusals (a provider at its ceiling,
a missing `--tier-reason`, a Run past the executor cap) are 1s. A refusal either
way names the move: fix the key, wait for the reset, settle a pane, or
`--skip-provider-check` knowing what it costs.

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
- A wave's `spawn` carries the row's `tier_reason` through as `--tier-reason`,
  always — so a `cc` row that states its reason can be spawned by the loop, and
  one that does not is refused, because the loop does not get to pick a tier
  the plan left unsaid. `spawn` says no by exiting — a `1` from `die`, a `6`
  from the Pro window's gate — and that exit is a process, so the wave runs it
  as a subshell and reads the status rather than calling it inline. Any non-zero
  is **the wave's 6**, naming the Task that could not be launched, and stops the
  wave before it dispatches anything: the refusal's own wording is on stderr,
  and retrying it every wave would be one refusal per turn forever.
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

A Task whose pane fell back to `cc` adds a `fallback(s): <task> <from>→<to>`
line below the table, a `fallback` field on its row and a count in both
`report.json` and the metrics line — the spend a plan that ran `ccd` did not
expect. The tier is read from the Run's own `.providers` note first, since the
pane it came from is gone by the time anyone reads a report: `settle … release`
and `teardown` delete the record, which is exactly when the spend is worth
knowing. A record still standing is the next source, and the plan row is the
last, so a Run from before the note existed reads as it always did.

## The two caps

`HERDR_TEAM_EXEC_CAP` (default 2) is per Run, counted over the panes this Run
holds; `HERDR_TEAM_PROVIDER_CAP` (default 4) is per provider across every Run.
A refusal names the limit it hit and, for the per-Run cap, only panes the
reader can settle.

`spawn` records each pane in `state/panes/<name>` — name, provider, Run,
worktree, spawn time, and the provider it fell back from — and `settle …
release` and `teardown` remove it. The provider count reads those files: a
provider is not passively readable off a screen, and `agent list` is per
session, so five sessions would each count only their own and spawn to the
ceiling. A pane with no record counts as `unknown`: an uncounted pane is the
one that exhausts a key. The sixth field is empty for every pane that started
where it was asked to; a five-field record predates it and reads that way.

## The tier a spawn starts on

`spawn <name> --branch <b> [--provider <profile>] [--tier-reason <text>]`
starts a pane on the tier it was asked for. Two things can move that:

- **`--provider cc` requires `--tier-reason "<why>"`.** `ccd` is the tier for
  work a command settles, so `cc` is for the work none does — the task shapes
  later work, it is a spec, or it is a review — and `spawn` cannot tell which of
  those a pane is. The missing reason is a refusal (exit 1), not a fallback: the
  other reading is a `ccd` task quietly spending Pro.
- **A `ccd` spawn whose provider check fails may fall back to `cc`**, on one
  condition: the Pro 5h window is under `HERDR_TEAM_PRO_FALLBACK_MAX` (70%)
  according to `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/pro-quota.json` — the
  cache `ai/claude/statusline.sh` writes and `ai/claude/quota-advice.sh`
  advises from — and that cache is fresh (`HERDR_TEAM_PRO_QUOTA_MAX_AGE`, 900s)
  and names a window that has not already reset. Anything else is exit **6**
  with the reason: no cache, an unreadable one, a stale one, an expired window,
  or a used percentage at or over the threshold. Unknown is not headroom, and a
  fallback decided from a cache nobody can read is the silent Pro spend
  `cost.md`'s checklist forbids — `--skip-provider-check` is the way through,
  by hand, knowing what it costs. `HERDR_TEAM_PRO_QUOTA_CACHE` points the read
  elsewhere; the tests set it so a spawn's answer never depends on this
  machine's window.
- **`omp` is never that fallback.** It is a different agent spending a DeepSeek
  key of its own (`ai/omp/models.yml`), so it relieves nothing a fallback exists
  to relieve.

A fallback that happened is a fact, not a warning: it goes into the pane
record's sixth field, `status` prints that pane as `ccd→cc`, and `report`
lists it. A fallback nobody can read back is the silent Pro spend either way —
the difference a record makes is that the next reader gets to decide.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live
agents; `team.sh` enforces both at spawn.

`git wta` names a worktree by the repo's basename under `~/.worktrees/`, not
by the repo's full path — two repos that share a basename collide there, one
more reason `--repo` on a project Run names a real, distinguishable path.
