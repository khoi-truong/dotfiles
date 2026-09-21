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
  so research goes here regardless of price. It is **never a fallback for
  `ccd`** either: it is a different agent spending a DeepSeek key of its own
  (`ai/omp/models.yml`), so falling back to it saves nothing on the credential
  a fallback would exist to spare, and buys a different agent's habits into
  work that was dispatched with these ones assumed.

The corollary: a task with no `verify` command is not a `ccd` task yet. Find
the command, or keep the work on `cc`.

A row on `cc` says why, in a `tier_reason` string — the task shapes later work,
it is a spec, or it is a review. `plan lint` warns about a `cc` row with a
`verify` and no reason, and `spawn --provider cc` refuses one, because neither
can tell a review from a row that is simply mislabelled.

## Review is always `cc`

Two reasons, and they stack.

A review is the one stage whose `verify` cannot fail on the thing that matters.
The `verify` command runs the tests, and the bug a review is for is the one the
tests do not catch — so a `ccd` review runs the suite, observes 0, and reads
`verified` on exactly the case it was sent to find. The check is powerless
there in a way it is not anywhere else in the table.

And a reviewer sharing the author's model family shares its blind spots, so
`cc` plan → `ccd` execute → `cc` review is not just cheaper: it is a second
opinion. That is the whole return on spending Pro for it, and it is why quota
pressure never moves the review down a tier.

## Checklist

- [ ] Tier stated, not asserted: every `cc` row carries a `tier_reason`, and
      every `ccd` spawn that fell back to Pro is inside the window a fallback
      is allowed at and written into the pane record — `status` shows it as
      `ccd→cc` and `report` lists it. A fallback that isn't recorded is the
      silent Pro spend this list exists to catch.
- [ ] Inside both caps: 2 executors per Run, 4 panes per provider machine-wide.
- [ ] Every Task worth its Dispatch, and every handoff inside its 150 lines.
