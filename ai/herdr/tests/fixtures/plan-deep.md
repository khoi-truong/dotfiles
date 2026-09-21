# Fixture plan — a chain of five

Status: fixture. Exercises the depth check in `plan_rows`: five Tasks, each
blocked on the one before it, so a Run can only ever have one of them out.
That is what depth costs — five Dispatches taken one at a time, and a second
executor idle throughout — and it is what the linter is here to say out loud.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/herdr/team.sh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []},
  {"task": "T-02", "provider": "ccd", "files": ["ai/herdr/tests/run.sh"],
   "verify": "shellcheck -x ai/herdr/tests/run.sh", "blocks": ["T-01"]},
  {"task": "T-03", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": ["T-02"]},
  {"task": "T-04", "provider": "ccd", "files": ["ai/claude/providers.zsh"],
   "verify": "shellcheck -x ai/claude/providers.zsh", "blocks": ["T-03"]},
  {"task": "T-05", "provider": "ccd", "files": ["lib/common.sh"],
   "verify": "shellcheck -x lib/common.sh", "blocks": ["T-04"]}
]
```

Five rows, one edge each, and the chain is the whole graph: depth 5, width 1.
`plan lint` warns about both and still exits 0 — a deep plan is sometimes
correct, and this is the fixture that says the warning never becomes a refusal.

### T-01 — The first link

The work the other four wait on.

### T-02 — The second link

Needs T-01's result before it can start.

### T-03 — The third link

Needs T-02's result before it can start.

### T-04 — The fourth link

Needs T-03's result before it can start.

### T-05 — The last link

Needs T-04's result. Nothing in a Run can reach this Task until four
Dispatches have settled in front of it.
