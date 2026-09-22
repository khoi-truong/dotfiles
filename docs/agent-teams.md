# Agent teams

A *team* is several agents in [herdr](herdr.md) panes, one git worktree each,
coordinated through files on disk. `ai/herdr/team.sh` drives it.

> [!NOTE]
> Not OMC's `/team` skill, which fans work out to in-process subagents inside
> one pane. Reach for `/team` first: a herdr team costs more and buys process
> isolation.

- [Why a script](#why-a-script)
- [Quick reference](#quick-reference)
- [The loop](#the-loop)
- [Dispatching from a plan](#dispatching-from-a-plan)
- [Reading results](#reading-results)
- [Configuration](#configuration)
- [Testing](#testing)

The protocol the agents follow is the `herdr-team` skill
(`ai/shared/skills/herdr-team/`); the plan format is the `dispatchable-plan`
skill.

## Why a script

`herdr agent start` execs the agent binary directly and drops what
`ai/claude/providers.zsh` exports, so Claude Code silently falls back to the Pro
login. `team.sh` is the only thing that starts a team agent: every spawn goes
through `zsh -ic <wrapper>`, and the provider is asserted afterwards.

## Quick reference

```sh
ai/herdr/team.sh run new [--plan <plan.md>] [--repo <path>]   # mint a Run id
ai/herdr/team.sh spawn exec-1 --branch feat/x      # worktree + workspace + agent
ai/herdr/team.sh dispatch exec-1 --task T-01 "…"   # hand over the contract
ai/herdr/team.sh dispatch exec-1 --task T-01 --from-plan .omc/plans/x.md
ai/herdr/team.sh status                            # roster and pending handoffs
ai/herdr/team.sh wait [--timeout <ms>]             # block until one dispatch settles
ai/herdr/team.sh collect --plan .omc/plans/x.md    # per-task state; exit code says what next
ai/herdr/team.sh loop --plan .omc/plans/x.md       # dispatch → wait → collect, in waves
ai/herdr/team.sh report [--plan <plan.md>]         # Run summary → report.json, metrics.jsonl
ai/herdr/team.sh surface exec-1                    # what a blocked agent is asking
ai/herdr/team.sh plan lint .omc/plans/x.md         # check a plan before dispatching
ai/herdr/team.sh settle <name> reuse|retain|release
ai/herdr/team.sh teardown <name> [--force]
ai/herdr/team.sh config show --sources             # resolved settings, and their layers
```

`prefix+alt+t` opens `status` in a popup. Run `team.sh` with no arguments for
the full usage.

## The loop

```text
dispatch ──▶ wait ──▶ collect --plan ──▶ dispatch what is `ready`
                │
                └─ agent blocked ──▶ surface <name> ──▶ human answers in the pane
```

- **Handoffs.** Agents report by writing `.omc/handoffs/<task>-<dispatch>.md`
  in the **main** checkout, never by leaving results in a transcript.
- **Run id.** Kept in `.omc/state/team-run`, so it survives a compaction.
- **`dispatch`** hands over the completion contract — Run, Task and Dispatch
  ids, the absolute handoff path, the frontmatter template — verbatim instead
  of retyped. With no `--dispatch` it picks the lowest id with no handoff yet,
  so a settled id is never reused. `--dry-run` prints the prompt.
- **`wait`** blocks until one outstanding dispatch under the Run settles and
  prints which. It says nothing about the outcome; `collect --plan` does. Exit
  codes are in `ai/shared/skills/herdr-team/references/herdr-adapter.md`.
- **`surface`** prints a blocked agent's screen. The answer is always typed by
  a human in the pane, never by the script.
- **`loop`** runs the cycle for a plan, routing each `ready` row to a pane
  by the `[[route]]` table, for up to `--max-waves` waves.

`spawn` opens the worktree with `herdr worktree open`, so the space is grouped
under the repo's row and `Open worktree…` finds it later. That command takes
no `--env`, so `OMC_STATE_DIR` and `HERDR_TEAM_HANDOFFS` are exported into the
pane's shell before the wrapper — they then survive the agent exiting, and a
hand-restarted `ccd` still writes its handoff to the main checkout.

## Dispatching from a plan

`--from-plan` makes the task body a pointer into the plan rather than prose.
The plan carries a `## Tasks` json block — one row per task, with its `files`,
its `verify` command and the tasks it `blocks` on. Dispatch reads the row and
hands the executor the plan path, section id and the command that must pass
before it may claim `evidence: verified`.

It refuses (exit 3) when a blocker has no `succeeded` + `verified` handoff
**under the current Run**. Task ids restart at `T-01` every Run and handoff
filenames carry no Run, so a gate that only globbed the directory would unblock
work on a previous Run's result. `--force` overrides it. A plan with no json
block dispatches as plain text.

**`plan lint`** checks a plan before anything is spawned and prints every
problem at once:

- a row with no `### T-nn` section, or a section with no row;
- `blocks` naming a task that doesn't exist, or forming a cycle;
- a `verify` whose exit code its own pipeline masks.

> [!IMPORTANT]
> `cmd | tail -1` exits 0 however `cmd` exited, so an executor would claim
> `evidence: verified` on a check that cannot fail. Lead a piped `verify` with
> `set -o pipefail`.

The format lives in its own skill, `dispatchable-plan`, because a planning
session never says "herdr", so `herdr-team`'s triggers would never fire in the
session that has to write the plan.

## Reading results

`collect --plan <plan.md>` prints one row per task — `done`, `review`,
`failed`, `running`, `ready`, `blocked` — and the exit code carries the
decision:

| Exit | Meaning |
| --- | --- |
| 0 | Something is ready: dispatch it |
| 1 | A human must look |
| 2 | Nothing actionable, and a task failed |
| 3 | Nothing to do |

Where a task has several handoffs the highest `D-nn` wins, so a retried task
stops reading `failed`. `running` (dispatched, unanswered) comes from the
journal `dispatch` keeps in `.omc/handoffs/.dispatched`. Plain `collect` lists
handoffs; naming no Run means every Run.

## Configuration

What a role launches is configuration, not a `team.sh` edit.

| File | Holds |
| --- | --- |
| `ai/herdr/team.toml` | Harnesses, `[profile.*]` entries a role may launch, the `[role.*]` roster (prefix, lifetime, cwd, `max_per_run`), `[[route]]` rules that place a plan row, fallback chains, presets |
| `ai/providers.toml` | Credentials behind the profiles: url, key, protocol, launcher, and the `ceiling` on panes spending one key |
| `ai/herdr/team.local.toml` | This machine's overrides (gitignored) |
| `<repo>/.config/herdr/team*.toml` | A project's own layer, for a Run bound to it with `run new --repo`; applied only after `config trust` |

| Command | Does |
| --- | --- |
| `config lint` | Check the merged result |
| `config doctor` | Report differences that aren't errors (e.g. this shell's provider vs the orchestrator's role) |
| `config show [--sources]` | Resolved keys, and the layer each came from |
| `config get <key>` | One resolved value |
| `config trust [--revoke]` | Allow or revoke a project repo's layers |

`HERDR_TEAM_CONFIG=<file>` replaces every layer — the way back from a local
file that won't parse. A new provider is a `[profile.*]` plus a `[[route]]`;
nothing in `team.sh` names it.

## Testing

```sh
ai/herdr/tests/run.sh
```

It is the only check the embedded parsers get (`shellcheck` can't see inside a
heredoc), so run it after touching `ai/herdr/`. CI runs it with
`HERDR_TESTS_STRICT=1`, which turns an avoidable skip into a failure. It adds a
provider with a stub launcher to prove nothing in `team.sh` is
provider-specific.
