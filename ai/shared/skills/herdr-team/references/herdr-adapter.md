# herdr adapter

Everything herdr-specific. The installed binary is authoritative for syntax;
this file states intent. Verified against herdr 0.9.1.

## Mapping

| Protocol operation | herdr |
| --- | --- |
| create a worker terminal | `workspace create --cwd … --no-focus` then `pane run` |
| submit the command | `pane send-keys <pane> enter` — **`pane run` does not submit** |
| dispatch | `agent prompt` (no `--wait`) |
| block on settlement | `agent wait --until <exact state>` |
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
  executor spawned this way did read `$HERDR_TEAM_HANDOFFS` and write its
  handoff into the main checkout, so the propagation is confirmed end to end.
- `workspace create` already returns the root pane: `result.workspace_id` is
  under `result.workspace`, and the pane under `result.root_pane.pane_id`.
  There is no need to look the pane up again with `pane list`.
- **The provider label is on the visible screen only.** `agent read` defaults
  to `--source recent`, which returns scrollback from *before* the agent
  started — it will happily report no marker on a correctly configured pane.
  Read `--source visible`, and retry: the status line
  (`DS·deepseek-flash | … | [░░░░░░░░░░]0%`) renders a beat after detection.

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
dispatch to `.omc/handoffs/.dispatched`, one `run<TAB>task<TAB>dispatch` line,
written only once `herdr agent prompt` has accepted it.

`ai/herdr/fixtures/run-tests.sh` covers all of this. `shellcheck` and `bash -n`
do not see inside the embedded python, so it is the only check the parser has.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live agents.
`team.sh` enforces both before it creates anything.
