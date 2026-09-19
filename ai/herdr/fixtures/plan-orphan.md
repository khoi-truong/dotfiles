# Fixture plan — a section with no row

Status: fixture. Exercises the row/section agreement check.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": []}
]
```

### T-01 — Has a row

Fine.

### T-02 — Has no row

Work nobody would ever be dispatched to do.
