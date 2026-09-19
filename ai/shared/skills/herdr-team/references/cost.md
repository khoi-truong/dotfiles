# Cost

Per **stage**, not per provider.

| Stage | Tier |
| --- | --- |
| plan, spec, research | Pro (`cc`) |
| implement, boilerplate, tests, lint/CI fixes | DeepSeek (`ccd`) |
| review, merge, integrate | Pro (`cc`) |
| commit message authoring | cheapest available |
| orchestration itself | cheap — it routes, it does not judge |

The orchestrator is a dispatcher and must never be the most expensive thing
running. Configuring the dispatcher changes the cost of the courier, never the
quality of the work it drives.

## Why the split is also a quality mechanism

A reviewer sharing the author's model family shares its blind spots. `cc` plan
→ `ccd` execute → `cc` review is not only cheaper; it is a second opinion.

## Checklist

- [ ] One plan, many readers — executors read the plan file, not a transcript.
- [ ] Handoffs bounded at 150 lines; frontmatter fielded, narrative short.
- [ ] No transcript read on the success path.
- [ ] Fire-then-wait, never sequential blocking.
- [ ] Provider asserted at spawn — a silent fallback to Pro is invisible and
      expensive.
- [ ] Concurrency capped at 2; the scarce resource is contended auth, not
      review bandwidth.
