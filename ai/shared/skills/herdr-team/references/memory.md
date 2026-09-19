# Memory

| Tier | Store | Lifetime | Written by |
| --- | --- | --- | --- |
| Durable | OMC wiki / `project-memory` | across sessions | orchestrator, deliberately |
| Task | `.omc/plans/<task>.md` | one Run | `spec` |
| Handoff | `.omc/handoffs/<task>-<dispatch>.md` | one Run | each dispatched agent |
| Ephemeral | pane transcript | one turn | everyone, trusted by no one |

## Rules

- **State lives in files, never in conversation.** An agent's transcript is
  never the source of truth for what happened — only the artifact it wrote is.
- Handoffs go to the **main checkout's** `.omc/handoffs/`, by absolute path.
  Load-bearing: `.omc/` is gitignored and a linked worktree's copy dies with
  the worktree.
- **Write before compacting.** An agent near its context limit writes its
  handoff first. A compaction that discards unwritten findings is the classic
  multi-agent data loss.
- **Re-assert role on every re-prompt.** A pane agent can silently lose its
  bootstrap at compaction. Never assume continuity: restate the role, the Task
  and Dispatch ids, and the handoff path every time.
- Orchestrator context holds **only** roster state, the plan path and handoff
  paths — never accumulated executor output.

## One plan, many readers

Executors read `.omc/plans/<task>.md`. They never read the planner's
transcript, and the planner never re-explains the plan in a prompt.
