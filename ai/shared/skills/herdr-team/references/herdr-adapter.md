# herdr adapter

Everything herdr-specific. The installed binary is authoritative for syntax;
this file states intent. Verified against herdr 0.9.1.

## Mapping

| Protocol operation | herdr |
| --- | --- |
| create a worker terminal | `workspace create --cwd … --no-focus` then `pane run` |
| submit the command | `pane send-keys <pane> enter` — **`pane run` does not submit** |
| dispatch | `agent prompt` (no `--wait`) |
| block on one agent | `agent wait <agent> --until <exact state>` |
| block on a Run | one `agent wait` per outstanding agent, first exit wins |
| settlement notification | `events.subscribe` on `pane.agent_status_changed` |
| one-shot wait | `events.wait` |
| status / progress bus | `pane report-metadata --source <id> --token NAME=VALUE` |
| diagnostic read | `agent read --source recent-unwrapped --lines 80` |
| read what is on screen now | `agent read --source visible` |
| unblock | `agent wait --until blocked` → read → `agent send-keys esc` |
| roster | `agent list` |
| worktree | `git wta` (not `herdr worktree create`) |

## Verified behaviour

Measured in a throwaway workspace, herdr 0.9.1:

- **`pane run` types the command but does not run it.** A separate
  `pane send-keys <pane> enter` submits. A spawn that omits it hangs forever
  with the command sitting on the prompt line — and looks identical to a slow
  start.
- **An agent launched as `zsh -ic cc` is detected in ~4 s.** Detection works
  through a shell function; the wrapper is not a problem.
- `agent rename <pane-id> <name>` works, and `agent get <name>` then resolves.
  `agent read <name> --source detection` shows the detection screen.
- The pane's `terminal_title` was `zsh -ic cc` — the command line, not the
  agent's identity. Confirms that titles are not authority.
- **`workspace create --env` reaches the root pane only.** A pane split later
  in that workspace does **not** inherit it (`HERDR_ENV=1` is injected by herdr
  regardless, so its presence proves nothing). Consequence: run the agent in
  the workspace's **root pane**, or pass `--env` again on `pane split`. An
  executor spawned this way did read the env the spawn exported and write its
  handoff into the main checkout, so the propagation is confirmed end to end.
- `workspace create` already returns the root pane: `result.workspace_id` is
  under `result.workspace`, and the pane under `result.root_pane.pane_id`.
  There is no need to look the pane up again with `pane list`.
- **The provider label is on the visible screen only.** `agent read` defaults
  to `--source recent`, which returns scrollback from *before* the agent
  started — it will happily report no marker on a correctly configured pane.
  Read `--source visible`, and retry: the status line
  (`DS·deepseek-flash | … | [░░░░░░░░░░]0%`) renders a beat after detection.

## Environment

Two variables, and the difference between them is the whole isolation story.

- **`HERDR_PANE_ID` is the Run key source.** `team.sh` takes the first
  non-empty of `HERDR_TEAM_RUN_KEY`, `HERDR_PANE_ID` and
  `CLAUDE_CODE_SESSION_ID`, falling back to `default`, and sanitises it to
  `[a-z0-9_-]` because it becomes a path component under `state/`. herdr sets
  `HERDR_PANE_ID` in every pane, which is what makes "one orchestrator pane,
  one Run" hold with nothing to export: an agent's own `export` does not
  survive to its next Bash call, so env can never be the *primary* mechanism —
  the pointer file is. `HERDR_TEAM_RUN_KEY` is the deliberate override, and the
  way one shell drives two Runs or a test drives three.
- **`HERDR_TEAM_ROOT` is what a spawn exports**, alongside `OMC_STATE_DIR`: the
  state root, never one Run's handoff directory. A pane outlives the Dispatch
  that spawned it, so handing it a Run's directory at spawn pins it to that Run
  for life and sends a reused pane's handoff to the wrong place. The dispatch
  prompt carries the absolute handoff path every time, which makes the export
  belt-and-braces on the success path and is why it must be the root.

`HERDR_TEAM_HANDOFFS` still overrides one Run's handoff directory whole,
ignoring the Run. It is the fixture suite's hook, not a spawn's.

## Hazards

- `agent prompt --wait` **rejects** an already-blocked agent with
  `agent_blocked` and sends no input; it returns `agent_prompt_stalled` if
  there is no activity within ~5 s. Neither proves input was not delivered.
- `idle` and `done` both mean ready — `done` is awaiting mark-as-seen.
  `unknown` means present but unclassifiable. Always wait on **exact** states.
  Observed: an agent that finished a dispatch settled in `done`, so
  `agent prompt --wait --until idle --until blocked` never returned. Include
  `done` or the wait hangs on success.
- Reading a full-screen agent beyond the visible screen makes herdr drive the
  mouse-scroll interface. Large reads are **not** passive.
- `agent start --kind claude` execs the binary directly, dropping everything
  `ai/claude/providers.zsh` exports, and silently bills Pro. This is why every
  spawn goes through `pane run "zsh -ic <wrapper>"`.
- Metadata sources are capped at **32 distinct `source` ids per pane** for its
  lifetime, and clearing or expiry does not release a slot. Use one source id
  per pane (`herdr-team`), never one per Dispatch.
- Presentation values are trimmed, stripped of control characters and capped at
  **80 characters**. The bus carries status tokens, not payloads.
- **Event subscriptions do not replay.** Subscribe first, dispatch second.
- `workspace.metadata_updated` reaches API subscribers but **does not invoke
  plugin event hooks**, so the status channel is invisible from inside a plugin.

## `release-agent` is not our settlement verb

`pane release-agent --source <id> --agent <label>` releases the *reporter's*
lifecycle authority over a pane — it belongs to whichever integration reported
the agent (`herdr:claude`, here), not to us. Settling a Dispatch is our
bookkeeping: label it with `report-metadata`, and let teardown close the
workspace. Calling `release-agent` from outside the reporting integration
meddles with state we do not own.

What herdr does get right for us: `agent wait` pins the resolved pane
occupant, so a replacement cannot satisfy the wait — the substrate already
enforces the identity rule.

## Plans

The `## Tasks` block `--from-plan` reads is specified once, in the
`dispatchable-plan` skill — a skill rather than a page here because a planning
session never says "herdr", so this skill's triggers never fire and the format
would never reach the session that has to produce it.

What belongs here is only what this adapter does with a row. `dispatch
--from-plan` builds the body as a **pointer**: the plan's absolute path, the
section id, the files in scope, and the `verify` command named as the thing
that must run before the executor may claim `evidence: verified`. Nothing is
copied. The plan lives in the main checkout, which outlives any worktree, so
the path stays readable from every pane — which is also why `--from-plan` is
resolved by the orchestrator and never by the agent.

`blocks` is enforced at dispatch: exit **3** and the unmet ids on stderr unless
every one of them has a `succeeded` + `verified` handoff **under the current
Run**. `--force` overrides with a warning, because retry is human-gated and a
gate with no key is a trap.

`provider` is advisory metadata for whoever chooses the target agent. The
script does not check it: an agent's provider is fixed when it spawns, the only
live evidence of it is on the pane's visible screen, and reading a pane is not
passive.

Body precedence is argv, then `--from-plan`, then stdin — and stdin only when
it is not a terminal. Reading a terminal here would hang with no prompt and
look exactly like a slow dispatch.

`collect --plan <plan.md>` reports the other direction: one row per task in the
plan rather than one per handoff, with the exit code saying what to do next —
**0** dispatch something, **1** a human must look, **2** nothing actionable and
something failed, **3** nothing to do. Where a task has several handoffs the
highest `D-nn` wins, so a task retried to success stops reading `failed`.

A task that was dispatched and has not answered reads `running`, which the
handoff files alone cannot show. `dispatch` therefore journals every real
dispatch to `.dispatched` inside that Run's handoff directory, one
`run<TAB>task<TAB>dispatch<TAB>agent` line, written only once
`herdr agent prompt` has accepted it. The fourth column is `wait`'s — see below.

`ai/herdr/fixtures/run-tests.sh` covers all of this. `shellcheck` and `bash -n`
do not see inside the embedded python, so it is the only check the parser has.

## The `wait` verb

`team.sh wait` blocks until one outstanding Dispatch under the Run settles,
where outstanding is the fold `running` already means above: the highest
Dispatch sent per Task with no handoff file yet. A Run has up to three out at
once and the caller wants the first, so the verb is a **fan-in**: one
`herdr agent wait <agent> --until idle --until done --until blocked` per
outstanding Dispatch, in the background, first to exit wins and the rest are
killed. All three states are named because `idle` and `done` both mean ready —
a wait on `idle` alone hangs on an agent that settled in `done` (see Hazards).

**The journal's fourth column exists for this.** `wait` cannot resolve a pane
from a Task id, so `dispatch` writes the agent name. `dispatched()` tolerates
both widths: a three-column line predates the column, still counts as `running`,
and is merely un-waitable — skipped with a warning, never fatal. Any other width
is refused (exit 1) rather than skipped, because waiting out the readable half
of a journal is how a loop stalls with work still outstanding. The code that
cannot be seen by `shellcheck` is covered by `run-tests.sh`; a legacy line has a
case on each side.

**Replay: settled.** If a target is *already* in one of the requested states,
`agent wait` returns at once rather than blocking for the next transition into
it. Two independent doc pages (`agent-automation.mdx`, `cli-reference.mdx`) say
so, and it was probed on 0.9.1: `--until idle` against an idle pane returned in
15 ms, while the same session's control — `--until idle` against a working agent
— blocked for the full 3 s timeout. So a fast executor that finished before
`wait` started is not missed by herdr itself. Note that `events.subscribe` does
*not* replay; `agent wait` does not inherit that gap because it evaluates
current state rather than consuming a buffered event.

**Unsettled, and what the code assumes.** What an outstanding wait does when its
pinned agent *exits in place* — no pane move, no replacement — is not stated
anywhere. The one related sentence covers a pane moved to another workspace,
which ends the wait with `agent_not_running`; a process exit is a different case
and was not probed, since closing a live agent means killing a pane in the
user's session. The code assumes it **may** block until `--timeout`, so before
blocking it looks once at each outstanding Dispatch's handoff file and returns
immediately if one has appeared since the journal was read. One `stat` per
Dispatch, correct under either answer, and `run-tests.sh` case 44 stages that
window — a `python3` that writes the handoff after reading the journal — so the
guard cannot quietly become dead code. What it does not cover is an agent that
dies without ever writing a handoff: the loop's only recovery there is the
caller's own `--timeout`.

**Exit codes**, alongside `collect --plan`'s:

| Code | Meaning |
| --- | --- |
| 0 | an agent reached a terminal state, or a handoff appeared — call `collect --plan` |
| 1 | no Run, a malformed journal, or a precondition failed |
| 3 | nothing outstanding to wait for — the same "nothing to do" as `collect` |
| 4 | `--timeout` expired with nothing settled |
| 5 | an outstanding agent went `blocked` — `team.sh surface <name>` |

4 is not 3 because a timeout is a **checkpoint, not a result** (`SKILL.md` rule
3): absence is never evidence, so "I waited and nothing happened" has to be
tellable apart from "there was nothing to wait for". 5 is not 0 because the next
move differs — a blocked agent has written nothing, so there is no new table to
read; the move is `surface`.

Which of the three states matched is **not** in the exit code. One 0 covers
`idle`, `done` and `blocked` alike, and herdr's 1 covers a timeout and every
other server error without distinguishing them — `error.code` in the stderr
payload is the only split, and the vocabulary is not enumerated anywhere. So
`wait` reads the winner's own `agent_status` rather than asking the wait which
condition it met, and reports a non-zero herdr exit on stderr instead of acting
on it.

`surface <name>` is the one read in the verb set: the Run, Task and Dispatch
from the journal, then `agent read --source visible --lines 80`. It has no flag
that sends keys and must not grow one — an approval dialog is surfaced to the
human, who answers it in the pane. It is deliberately best-effort about a
journal line it cannot read, where `wait` refuses one: there the screen is the
answer, and refusing to print it withholds the one thing the human came to see.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live agents.
`team.sh` enforces both before it creates anything.
