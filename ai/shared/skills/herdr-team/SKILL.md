---
name: herdr-team
description: >-
  Protocol for driving a team of coding agents from a single herdr pane: one
  orchestrator the user talks to, a singular spec agent, N executors in git
  worktrees, and ephemeral reviewers. Covers work identity (Run/Task/Dispatch),
  the completion contract, liveness, settlement, worktree lifecycle, memory
  tiers and per-stage model tiering. Use whenever coordinating more than one
  agent, spawning or tearing down an agent pane, dispatching work to another
  agent, or deciding which provider a piece of work belongs on. Fires on
  "agent team", "herdr team", "spawn an executor", "dispatch", "handoff",
  "worktree agent", "parallel agents", even when herdr is not named.
---

# herdr agent team

One pane holds the user. Everything else is dispatched work.

The protocol is the artifact; herdr is an implementation detail. Read
`references/protocol.md` for the substrate-independent rules and
`references/herdr-adapter.md` for the commands that implement them.

## Roster

A role earns a pane only if it needs a different provider, a different cwd, a
long life, or visibility. Everything else is an in-process subagent.

| Role | Pane | Provider | Location |
| --- | --- | --- | --- |
| `orchestrator` | standing | `cc` | main checkout |
| `spec` | standing | `cc` | main checkout |
| `plan-<task>` | ephemeral | `cc` | main checkout |
| `exec-N` | 1–3 | `ccd` | one worktree each |
| `rev-<task>` | ephemeral | `cc` | the executor's worktree |

critic, architect and verifier are in-process subagents, never panes. For
fan-out inside one pane, use OMC `/team`; do not reimplement it.

**A suffix means there can be more than one of me.** `orchestrator` and `spec`
are bare because they are singular — if one is busy, queue; never spawn a
second. Pool roles match by prefix and may spawn up to the cap of **2**
concurrent executors (3 only when all three are genuinely independent). The
cap exists because auth is contended: one DeepSeek key, one Pro login.

## The five rules that matter

1. **Identity comes from the Dispatch**, never from an agent name or a pane
   title. Every prompt and every handoff carries its Run, Task and Dispatch id.
2. **Report exactly once, even on failure.** A silent failure is a protocol
   defect, not an unlucky run. `outcome: succeeded` at `evidence: reported` is
   a claim, not a result.
3. **Absence is never evidence.** A timeout is a checkpoint. Read before
   retrying; only positive proof settles a Dispatch; retry is human-gated.
4. **Settle immediately, exactly once** — reuse, retain or release. "Decide
   later" is how six stale panes accumulate.
5. **State lives in files.** A transcript is never the source of truth. Write
   the handoff before compacting.

## Prohibitions

- Never auto-answer an approval dialog. Surface it.
- Never read a transcript on the success path. Results travel by file; reads
  are a diagnostic for blocked or stalled agents, capped at ~80 lines.
- Never put two agents in one directory. The substrate gives no isolation.
- Never poll. Subscribe to `pane.agent_status_changed`, and subscribe *before*
  dispatching — subscriptions do not replay.
- Never let a plugin start an agent or pick its provider.

## Cost

Pro (`cc`) for plan, spec, research, review and merge. DeepSeek (`ccd`) for
implementation, tests, lint and CI fixes. The orchestrator routes; it does not
judge, so it is never the most expensive thing running. Details in
`references/cost.md`.

## Tooling

`ai/herdr/team.sh` — `spawn`, `status`, `collect`, `settle`, `teardown`.
`prefix+alt+t` shows the status table. The script owns topology; this skill
owns the protocol.

Only `team.sh` starts an agent. It is the only place that knows `cc` and `ccd`
are shell functions rather than binaries, which is what keeps work off the
wrong provider.
