# Fixture plan — one task whose verify is deliberately empty

Status: fixture. `plan lint` accepts it; `run-tests.sh` uses it for the case
where an empty `verify` means the planner has said no command settles the Task,
so a `succeeded`/`verified` handoff is `done` without a `commands:` entry.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "", "blocks": []}
]
```

### T-01 — A task settled by no command

The row says so itself: `"verify": ""`. Whoever verifies this Task is the
reviewer, not a shell command.
