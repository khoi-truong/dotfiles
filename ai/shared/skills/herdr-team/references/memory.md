# Memory

| Tier | Store | Lifetime | Written by |
| --- | --- | --- | --- |
| Durable | OMC wiki / `project-memory` | across sessions | orchestrator, deliberately |
| Task | wherever the producing workflow writes it, recorded in the Run | one Run | `spec-<round>` |
| Handoff | `.herdr/runs/<run>/handoffs/<task>-<dispatch>.md` | one Run | each dispatched agent |
| Ephemeral | pane transcript | one turn | everyone, trusted by no one |

## Rules

- **State lives in files, never in conversation.** An agent's transcript is
  never the source of truth for what happened — only the artifact it wrote is.
- Handoffs go to the **main checkout's** `.herdr/runs/<run>/handoffs/`, by
  absolute path. Load-bearing twice over: a linked worktree's copy of a
  gitignored directory dies with the worktree, and `.herdr/` is grown beside
  `.omc/` rather than inside it because `.omc/` is OMC's lifecycle —
  `state_clear`, `OMC_STATE_DIR` redirection and worktree pruning may all
  remove what is under it, and a Run's evidence is not one agent's scratch
  state.
- A plan is **not moved**. It stays wherever the workflow that produced it
  writes it — OMC `/plan` keeps using `.omc/plans/` — and the Run records its
  absolute path, which is also the key that recovers the Run after a
  compaction. Every consumer takes a path; nothing indexes a directory.
- **herdr owns coordination, not content.** A handoff is a receipt: an artifact
  a workflow wrote stays where that workflow put it, and the handoff lists its
  absolute path under `artifacts:`, distinct from `files_changed:`. Nothing
  here copies such a file into a handoff, and **nothing here ever deletes a
  path listed under `artifacts:`** — not teardown, not release, not any later
  gc verb. That field is the exclusion list.
- **Write before compacting.** An agent near its context limit writes its
  handoff first. A compaction that discards unwritten findings is the classic
  multi-agent data loss.
- **Re-assert role on every re-prompt.** A pane agent can silently lose its
  bootstrap at compaction. Never assume continuity: restate the role, the Task
  and Dispatch ids, and the handoff path every time.
- Orchestrator context holds **only** roster state, the plan path and handoff
  paths — never accumulated executor output.

## One plan, many readers

Executors read the plan file at the absolute path the Run records. They never
read the planner's transcript, and the planner never re-explains the plan in a
prompt.
