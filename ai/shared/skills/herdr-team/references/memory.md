# Memory

| Tier | Store | Lifetime | Written by |
| --- | --- | --- | --- |
| Durable | OMC wiki / `project-memory` | across sessions | orchestrator, deliberately |
| Task | where the producing workflow writes it, recorded in the Run | one Run | `spec-<round>` |
| Handoff | `.herdr/runs/<run>/handoffs/<task>-<dispatch>.md` | one Run | each dispatched agent |
| Run evidence | `.herdr/runs/<run>/report.json`, `loop.log`, `.herdr/metrics.jsonl` | kept | orchestrator |
| Ephemeral | pane transcript | one turn | everyone, trusted by no one |

## Rules

- Handoffs go to the **main checkout's** `.herdr/runs/<run>/handoffs/`, by
  absolute path, because a linked worktree's copy of a gitignored directory
  dies with the worktree.
- **Run evidence is never pruned**, and nothing reads it at runtime. `.herdr/`
  sits beside `.omc/` rather than inside it because `.omc/` is OMC's
  lifecycle — `state_clear`, `OMC_STATE_DIR` redirection and worktree pruning
  may each remove what is under it, and a metrics series a cleanup verb can
  delete is not a series.
- A plan is **not moved**: it stays where the workflow that produced it writes
  it — OMC `/plan` keeps using `.omc/plans/` — and the Run records the absolute
  path, which is also what recovers the Run after a compaction.
- **herdr owns coordination, not content**: **nothing here ever deletes a path
  listed under `artifacts:`** — not teardown, not release, not any later gc
  verb. That field is the exclusion list.
- **Re-assert role on every re-prompt.** A pane agent can silently lose its
  bootstrap at compaction: restate the role, the ids and the handoff path every
  time.
- Orchestrator context holds **only** roster state, the plan path and handoff
  paths, never accumulated executor output.

**One plan, many readers.** Every consumer takes that path; nothing indexes a
directory, no executor reads the planner's transcript, and the planner never
re-explains the plan in a prompt. A compaction that discards unwritten findings
is the classic multi-agent data loss: write before compacting.
