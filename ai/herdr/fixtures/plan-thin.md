# Fixture plan — an undersized chained pair, and two oversized rows

Status: fixture. Exercises the granularity proxies in `plan_rows`, which are
the only two things a plan file says about whether a row is worth a Dispatch
of its own. Every warning here is a warning: the exit stays 0.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/herdr/team.sh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []},
  {"task": "T-02", "provider": "ccd", "files": ["ai/herdr/team.sh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": ["T-01"]},
  {"task": "T-03", "provider": "ccd", "files": ["ai/herdr/"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []},
  {"task": "T-04", "provider": "ccd",
   "files": ["ai/herdr/team.sh", "ai/herdr/fixtures/run-tests.sh",
             "ai/shared/skills/herdr-team/SKILL.md", "ai/claude/providers.zsh",
             "ai/setup.sh", "README.md", "brew/Brewfile", "lib/common.sh",
             "zsh/functions.zsh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []}
]
```

T-01 and T-02 are two short rows on one file with an edge between them: two
Dispatches, two worktree decisions, two waves of the orchestrator loop, and
one task's worth of work at the end of it. T-03 names a directory and T-04
names nine paths; neither can have a `verify` that localizes a failure, so a
retry on either re-does everything.

### T-01 — The thin half

The first half of what should be one Dispatch, queued behind nothing.

### T-02 — The other thin half

The second half, queued behind the first half.

### T-03 — A directory, not a file

A row whose `files` names a tree rather than a path.

### T-04 — Nine paths, one verify

A row spread across nine files, which no single verification command can
settle: a failure comes back as "something, somewhere", and the retry is the
whole Task again.
