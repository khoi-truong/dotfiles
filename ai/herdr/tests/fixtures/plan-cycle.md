# Fixture plan — a cycle in `blocks`

Status: fixture. Exercises the cycle check in `plan_rows`.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": ["T-02"]},
  {"task": "T-02", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": ["T-01"]}
]
```

Neither task can ever be dispatched: each waits on the other. No per-task
gate can see this — the row for T-01 only knows it is blocked on T-02 — so
the check has to read the whole rows list, which is why it lives in the
parser rather than in the dispatch gate.

### T-01 — Blocked on T-02

Never dispatchable.

### T-02 — Blocked on T-01

Never dispatchable either.
