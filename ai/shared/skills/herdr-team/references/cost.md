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

Neither planning nor research earns a standing pane. A spec or research round
is a `spec-<round>` or `res-<topic>` pane spawned for that round: it writes its
artifact, the handoff names the path, and it settles. What a long-lived
planning pane accumulates is context, and the protocol already says a
transcript is not the source of truth — so the standing pane costs a slot and
a login to hold something nothing is allowed to read.

The orchestrator is a dispatcher and must never be the most expensive thing
running. Configuring the dispatcher changes the cost of the courier, never the
quality of the work it drives.

## The discriminator is verifiability, not price

Read the table above as a consequence, not a rule. What puts a stage on a tier
is whether a mechanical command catches a wrong answer:

- **`ccd`** — a command in the task's `verify` field catches the mistake.
  Implementation, boilerplate, tests, lint and CI fixes. The cheap tier is
  safe here because the check, not the model, is what makes it safe.
- **`cc`** — the work shapes later work: API or schema shape, security,
  architecture, review, merge. It stays on Pro no matter how cheap the
  alternative is, because a wrong answer ships silently and there is no
  command that would have caught it. Quota pressure never moves a task off
  this tier; the reason it is here is correctness, not budget.
- **`omp`** — the task needs web or docs lookup. This is a **capability** axis,
  not a cheaper `ccd`: Claude Code's web search does not work on a non-Pro
  provider, so research goes here regardless of price.

The corollary is that a task with no `verify` command is not a `ccd` task yet.
Either find the command or keep the work on `cc`.

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
- [ ] Concurrency capped at 2 **across every orchestrator**, not per Run — the
      cap is the machine's, because the scarce resource is contended auth (one
      DeepSeek key, one Pro login), not review bandwidth.
