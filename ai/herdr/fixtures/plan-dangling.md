# Fixture plan — `blocks` naming a task with no row

Status: fixture. Exercises the dangling-blocker check.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": ["T-09"]}
]
```

T-09 has no row, so nothing will ever settle it and T-01 is blocked
forever. The dispatch gate alone would report this as an ordinary unmet
blocker, which reads like "not yet" rather than "never".

### T-01 — Blocked on a task that does not exist

Never dispatchable.
