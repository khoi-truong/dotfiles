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

## Dispatching from a plan

`team.sh dispatch <name> --task T-nn --from-plan <plan.md>` builds the body
from the plan instead of from something the orchestrator retypes. The plan
carries a `## Tasks` heading followed by one fenced `json` block:

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "cc", "files": ["README.md"],
   "verify": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1",
   "blocks": ["T-01"]}
]
```

**A `verify` that contains a pipe must lead with `set -o pipefail`.** A
pipeline's exit status is the last command's, so `cmd | tail -1` exits 0
however `cmd` exited. The executor observes 0, claims `evidence: verified`, and
the blocker gate unblocks the next task — turning the top of the evidence
ordering into a rubber stamp.

JSON rather than a markdown table because a `verify` command contains pipes,
and rather than YAML because `python3` has no YAML in its standard library and
this script takes no new runtime dependency. Every row needs a matching
`### T-nn` prose section; the parser refuses a plan where the two disagree in
either direction.

**The body is a pointer.** It tells the executor to read that section out of
the plan file at an absolute path, names the files in scope, and names the
`verify` command as the thing that must run before it may claim
`evidence: verified`. Nothing is copied. The plan lives in the main checkout,
which outlives any worktree, so the path stays readable from every pane —
which is also why `--from-plan` is resolved by the orchestrator and not by the
agent.

`blocks` is enforced at dispatch: exit **3** and the unmet ids on stderr unless
every one of them has a `succeeded` + `verified` handoff **under the current
Run**. `--force` overrides with a warning, because retry is human-gated and a
gate with no key is a trap.

`provider` is advisory metadata for whoever chooses the target agent. The
script does not check it: an agent's provider is fixed when it spawns, the
only live evidence of it is on the pane's visible screen, and reading a pane
is not passive.

Body precedence is argv, then `--from-plan`, then stdin — and stdin only when
it is not a terminal. Reading a terminal here would hang with no prompt and
look exactly like a slow dispatch.

`ai/herdr/fixtures/run-tests.sh` covers all of this. `shellcheck` and `bash -n`
do not see inside the embedded python, so it is the only check the parser has.

## Naming

Agent names match `[a-z][a-z0-9_-]{0,31}` and must be unique among live agents.
`team.sh` enforces both before it creates anything.
