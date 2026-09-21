# Fixture plan — five rows that block nothing

Status: fixture. The shape `protocol.md` asks for: no row waits on another, so
all five can be dispatched the moment a pool is free and the executor cap is
the only thing limiting how many run at once. `plan lint` reports width 5 and
warns about nothing at all.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/herdr/team.sh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []},
  {"task": "T-02", "provider": "ccd", "files": ["ai/herdr/tests/run.sh"],
   "verify": "shellcheck -x ai/herdr/tests/run.sh", "blocks": []},
  {"task": "T-03", "provider": "ccd", "files": ["ai/shared/skills/herdr-team/SKILL.md"],
   "verify": "set -o pipefail; npx markdownlint-cli2 ai/shared/skills/herdr-team/SKILL.md | tail -1",
   "blocks": []},
  {"task": "T-04", "provider": "ccd", "files": ["ai/claude/providers.zsh"],
   "verify": "shellcheck -x ai/claude/providers.zsh", "blocks": []},
  {"task": "T-05", "provider": "ccd", "files": ["lib/common.sh"],
   "verify": "shellcheck -x lib/common.sh", "blocks": []}
]
```

Every `blocks` is empty, which is the whole point: depth 1, width 5. The
granularity proxies stay quiet too — each row names one path, so none is
oversized, and an unblocked row is never a candidate for merging however short
its prose is. That is what lets the case read stderr as the assertion.

### T-01 — The first of five

Nothing waits on anything here, so this Task can be dispatched before any
other has been read. A plan shaped this way is limited by how many executors
the machine can carry and by nothing in the document itself.

### T-02 — The second of five

Independent of every other row. Whatever it does, it does it without waiting
for a handoff to land anywhere else in the Run.

### T-03 — The third of five

The one row whose file is not a shell script, hence the piped verify and the
`set -o pipefail` leading it: a pipeline without that exits with its last
stage's status, which is a check that cannot fail.

### T-04 — The fourth of five

Independent again. Five rows like this one are how a plan keeps two executors
busy for the length of the run rather than for the length of one Task.

### T-05 — The fifth of five

The last row, and still nothing blocks on it — which is what a wide plan
looks like from either end.
