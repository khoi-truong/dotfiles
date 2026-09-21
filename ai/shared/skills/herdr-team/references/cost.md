# Cost

Per **stage**, not per provider.

| Stage | Tier |
| --- | --- |
| plan, spec | Pro (`cc`) |
| research | `omp` — capability, not price |
| implement, boilerplate, tests, lint/CI fixes | DeepSeek (`ccd`) |
| review, merge, integrate | Pro (`cc`) |
| commit message authoring | cheapest available |
| orchestration itself | cheap — it routes, it does not judge |

Configuring the dispatcher changes the cost of the courier, never the quality
of the work it drives — and `loop` keeps the courier off the per-Task side of
that ledger: one verb drives a whole plan, and its turns do not scale with the
Tasks.

**A Dispatch has fixed overhead** — a prompt, a pane, a handoff, a collect — so
a Task has to be worth one. Two chained rows on one file are one Task written
twice, paying the overhead twice for work nothing can run in parallel.

## The discriminator is verifiability, not price

- **`ccd`** — a command in the task's `verify` field catches the mistake. The
  cheap tier is safe here because the check, not the model, makes it so.
- **`cc`** — the work shapes later work, so a wrong answer ships silently and
  no command would have caught it. Quota pressure never moves a task off this
  tier: what holds it here is correctness, not budget.
- **`omp`** — the task needs web or docs lookup. A **capability** axis, not a
  cheaper `ccd`: Claude Code's web search does not work on a non-Pro provider,
  so research goes here regardless of price.

The corollary: a task with no `verify` command is not a `ccd` task yet. Find
the command, or keep the work on `cc`.

A reviewer sharing the author's model family shares its blind spots, so `cc`
plan → `ccd` execute → `cc` review is not just cheaper: it is a second opinion.

## Checklist

- [ ] Provider asserted at spawn: a silent fallback to Pro is expensive.
- [ ] Inside both caps: 2 executors per Run, 4 panes per provider machine-wide.
- [ ] Every Task worth its Dispatch, and every handoff inside its 150 lines.
