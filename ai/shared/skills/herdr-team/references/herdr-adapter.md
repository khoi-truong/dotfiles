# herdr adapter

Everything herdr-specific, and every flag and exit code the verbs have. The
installed binary is authoritative for syntax; this file states intent, verified
against herdr 0.9.1.

## Mapping

| Protocol operation | herdr |
| --- | --- |
| start a worker pane | `workspace create --cwd … --no-focus`, `pane run`, `pane send-keys <pane> enter` |
| dispatch | `agent prompt` (no `--wait`) |
| block | `agent wait <agent> --until <exact state>` |
| settlement notification | `events.subscribe` on `pane.agent_status_changed` |
| status / progress bus | `pane report-metadata --source <id> --token NAME=VALUE` |
| diagnostic read | `agent read --source visible --lines 80` |
| roster | `agent list` |

## Verified behaviour

Measured in a throwaway workspace:

- **`pane run` types the command but does not run it**; `pane send-keys <pane>
  enter` submits. A spawn that omits it hangs forever with the command sitting
  on the prompt line, looking identical to a slow start.
- **An agent launched as `zsh -ic cc` is detected in ~4 s**, so the wrapper is
  not a problem. `agent rename` works and `agent get <name>` then resolves. The
  pane's `terminal_title` was `zsh -ic cc` — the command line, not the agent's
  identity, so titles are not authority.
- **`workspace create --env` reaches the root pane only.** A split pane does
  **not** inherit it (`HERDR_ENV=1` is injected regardless, so its presence
  proves nothing). Run the agent in the **root pane**, which `workspace create`
  returns as `result.root_pane.pane_id`, or pass `--env` again on `pane split`.
  An executor spawned this way read the env and wrote its handoff into the main
  checkout, confirming the propagation end to end.
- **The provider label is on the visible screen only.** `agent read` defaults
  to `--source recent`, which returns scrollback from *before* the agent
  started and will happily report no marker on a correct pane. Read
  `--source visible`, and retry — the status line renders a beat after
  detection.

## Environment

Two variables, and the difference between them is the whole isolation story.

- **`HERDR_PANE_ID` is the Run key source.** `team.sh` takes the first
  non-empty of `HERDR_TEAM_RUN_KEY`, `HERDR_PANE_ID` and
  `CLAUDE_CODE_SESSION_ID`, falls back to `default`, and sanitises it to
  `[a-z0-9_-]` because it becomes a path component under `state/`. herdr sets
  `HERDR_PANE_ID` in every pane, which is what makes "one orchestrator pane,
  one Run" hold with nothing to export — an agent's own `export` does not
  survive to its next Bash call, so the pointer file, not env, is the primary
  mechanism. `HERDR_TEAM_RUN_KEY` is the deliberate override.
- **`HERDR_TEAM_ROOT` is what a spawn exports**, alongside `OMC_STATE_DIR`: the
  state root, never one Run's handoff directory — handing a pane a Run's
  directory at spawn would pin it to that Run for life, which `protocol.md`
  forbids. The dispatch prompt carries the absolute handoff path every time, so
  the export is belt-and-braces and can afford to be the root.

`HERDR_TEAM_HANDOFFS` overrides one Run's handoff directory whole: the fixture
suite's hook, not a spawn's.

## Hazards

- `agent prompt --wait` **rejects** an already-blocked agent with
  `agent_blocked` and sends no input; it returns `agent_prompt_stalled` with no
  activity within ~5 s. Neither proves input was undelivered.
- `idle` and `done` both mean ready — `done` is awaiting mark-as-seen —
  and `unknown` means present but unclassifiable. Always wait on **exact**
  states, and always include `done`: an agent that finished a dispatch was
  observed settling there, so a wait on `idle` alone hangs on success.
- Reading a full-screen agent beyond the visible screen makes herdr drive the
  mouse-scroll interface: large reads are **not** passive.
- `agent start --kind claude` execs the binary directly, dropping what
  `ai/claude/providers.zsh` exports and silently billing Pro. Hence every spawn
  goes through `pane run "zsh -ic <wrapper>"`.
- Metadata sources are capped at **32 distinct `source` ids per pane** for its
  lifetime, and clearing does not release a slot: use one id per pane
  (`herdr-team`), never one per Dispatch. Values are capped at **80
  characters** — the bus carries status tokens, not payloads.
- **Event subscriptions do not replay.** Subscribe first, dispatch second.
- **`agent list` shows every herdr agent**, not only a Run's. One started by
  hand elsewhere reads exactly like a team pane, so match on the Run's own
  names before treating a row as a dispatch target.
- `workspace.metadata_updated` reaches API subscribers but **not plugin event
  hooks**, so the status channel is invisible from inside a plugin.

## `release-agent` is not our settlement verb

`pane release-agent --source <id> --agent <label>` releases the *reporter's*
lifecycle authority over a pane, and that belongs to whichever integration
reported the agent (`herdr:claude`, here), not to us. Settling a Dispatch is
our bookkeeping: label it with `report-metadata` and let teardown close the
workspace. Calling it from outside the reporting integration meddles with
state we do not own.

What herdr does get right: `agent wait` pins the resolved pane occupant, so a
replacement cannot satisfy the wait — the substrate already enforces the
identity rule.

## Plans

The `## Tasks` block `--from-plan` reads is specified once, in the
`dispatchable-plan` skill — a skill rather than a page here because a planning
session never says "herdr", so these triggers never fire and the format would
never reach the session that has to produce it.

What belongs here is what this adapter does with a row. `dispatch --from-plan`
builds the body as a **pointer**: the plan's absolute path, the section id, the
files in scope, and the `verify` command that must run before the executor may
claim `evidence: verified`. Nothing is copied. The plan lives in the main
checkout, which outlives any worktree, so the path stays readable from every
pane — and is why `--from-plan` is resolved by the orchestrator, never by the
agent.

`blocks` is enforced at dispatch: exit **3** and the unmet ids on stderr unless
each has a `succeeded` + `verified` handoff **under the current Run**. `--force`
overrides with a warning, because retry is human-gated and a gate with no key
is a trap.

`provider` is advisory metadata for whoever chooses the target agent; the
script does not check it, since a provider is fixed at spawn, the only live
evidence of it is the pane's visible screen, and reading a pane is not passive.

Body precedence is argv, then `--from-plan`, then stdin — and stdin only when
it is not a terminal, since reading one would hang with no prompt and look like
a slow dispatch.

`collect --plan <plan.md>` reports the other direction: one row per task in the
plan rather than one per handoff — `done`, `review`, `failed`, `running`,
`ready`, `blocked` — with the exit code saying what to do next: **0** dispatch
something, **1** a human must look, **2** nothing actionable and something
failed, **3** nothing to do. Where a task has several handoffs the highest
`D-nn` wins, so one retried to success stops reading `failed`.

A task dispatched and not yet answered reads `running`, which the handoff files
alone cannot show. `dispatch` therefore journals every real dispatch to
`.dispatched` in that Run's handoff directory — one
`run<TAB>task<TAB>dispatch<TAB>agent` line, written only once `herdr agent
prompt` has accepted it. The fourth column is `wait`'s.

`ai/herdr/fixtures/run-tests.sh` covers all of this: `shellcheck` and `bash -n`
do not see inside the embedded python, so it is the only check the parser has.

## The `wait` verb

`team.sh wait` blocks until one outstanding Dispatch under the Run settles —
outstanding being the fold `running` uses above. A Run has up to three out at
once and the caller wants the first, so the verb is a **fan-in**: one
backgrounded `herdr agent wait <agent> --until idle --until done --until
blocked` per outstanding Dispatch, first to exit wins, the rest are killed. All
three states are named for the reason under Hazards.

**The journal's fourth column exists for this**: `wait` cannot resolve a pane
from a Task id, so `dispatch` writes the agent name. A three-column line
predates the column, still counts as `running`, and is merely un-waitable —
skipped with a warning. Any other width is refused (exit 1), because waiting
out the readable half of a journal is how a loop stalls with work still
outstanding. `run-tests.sh` has a case on each side.

**Replay: settled.** A target already in a requested state returns at once
rather than blocking for the next transition into it — two herdr doc pages say
so, and on 0.9.1 `--until idle` against an idle pane returned in 15 ms where
the working-agent control blocked for the full 3 s. So a fast executor that
finished before `wait` started is not missed. `events.subscribe` does *not*
replay; `agent wait` evaluates current state rather than consuming a buffered
event, so it escapes that gap.

**Unsettled.** What an outstanding wait does when its pinned agent *exits in
place* is stated nowhere and was not probed, since that means killing a pane in
the user's session. The code assumes it **may** block until `--timeout`, so
before blocking it stats each outstanding Dispatch's handoff once and returns
if one appeared since the journal was read: correct under either answer, and
`run-tests.sh` case 44 stages that window so the guard cannot become dead code.
An agent that dies without writing a handoff is not covered; the only recovery
there is the caller's own `--timeout`.

**Exit codes**, alongside `collect --plan`'s:

| Code | Meaning |
| --- | --- |
| 0 | an agent settled, or a handoff appeared — call `collect --plan` |
| 1 | no Run, a malformed journal, or a precondition failed |
| 3 | nothing outstanding to wait for — `collect`'s "nothing to do" |
| 4 | `--timeout` expired with nothing settled |
| 5 | an outstanding agent went `blocked` — `team.sh surface <name>` |

4 is not 3 because a timeout is a **checkpoint, not a result** (`SKILL.md` rule
3): "I waited and nothing happened" must be tellable apart from "there was
nothing to wait for". 5 is not 0 because a blocked agent has written nothing —
no new table to read, so the move is `surface`. Which state matched is **not**
in the exit code: one 0 covers all three, and herdr's own 1 covers a timeout
and every other server error alike, so `wait` reads the winner's `agent_status`
instead of asking the wait which condition it met.

`surface <name>` is the one read in the verb set: the Run, Task and Dispatch
from the journal, then `agent read --source visible --lines 80`. It has no flag
that sends keys and must not grow one. It is best-effort about a journal line
it cannot read, where `wait` refuses one: there the screen is the answer, and
refusing to print it withholds the one thing the human came to see.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live
agents; `team.sh` enforces both before creating anything.
