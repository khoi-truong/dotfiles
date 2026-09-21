# Fixture plan — a task block that is not JSON

Status: fixture. Exercises the JSON check.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": []},
]
```

The trailing comma is the whole point: valid in several languages, not in
JSON, and a plan that cannot be read is not a plan that dispatches half.

### T-01 — Unreachable

The block above never parses, so this section is never found.
