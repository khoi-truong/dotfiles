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
of the work it drives.

## The discriminator is verifiability, not price

Read the table above as a consequence, not a rule. What puts a stage on a tier
is whether a command catches a wrong answer.

- **`ccd`** — a command in the task's `verify` field catches the mistake. The
  cheap tier is safe here because the check, not the model, makes it so.
- **`cc`** — the work shapes later work. It stays on Pro however cheap the
  alternative is, because a wrong answer ships silently and no command would
  have caught it. Quota pressure never moves a task off this tier: the reason
  it is here is correctness, not budget.
- **`omp`** — the task needs web or docs lookup. A **capability** axis, not a
  cheaper `ccd`: Claude Code's web search does not work on a non-Pro provider,
  so research goes here regardless of price.

The corollary: a task with no `verify` command is not a `ccd` task yet. Find
the command, or keep the work on `cc`.

A reviewer sharing the author's model family shares its blind spots, so `cc`
plan → `ccd` execute → `cc` review is not only cheaper: it is a second opinion.

## Checklist

- [ ] Handoffs bounded at 150 lines; frontmatter fielded, narrative short.
- [ ] No transcript read on the success path.
- [ ] Fire-then-wait, never sequential blocking.
- [ ] Provider asserted at spawn — a silent fallback to Pro is invisible and
      expensive.
- [ ] Concurrency capped at 2 **across every orchestrator**, not per Run.
