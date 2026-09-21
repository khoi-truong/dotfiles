# Fixture plan — several problems at once

Status: fixture. A planner fixing its own output should see all of these
in one run, not one per invocation.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["README.md"], "verify": "npx markdownlint-cli2 README.md | tail -1", "blocks": ["T-09"]},
  {"task": "T-02", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": []}
]
```

Three findings: T-01 blocks on a row that does not exist, T-01's verify
cannot fail, and T-03 has a section with no row.

### T-01 — Dangling blocker and a masking verify

Two problems in one row.

### T-02 — Fine

Nothing wrong here.

### T-03 — A section with no row

Work nobody would ever be dispatched to do.
