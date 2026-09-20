# Fixture plan — a row with no section

Status: fixture. The other direction of the row/section agreement check.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"], "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "ccd", "files": ["README.md"], "verify": "shellcheck -x ai/setup.sh", "blocks": []}
]
```

T-02 has a row and no prose, so dispatching it sends an executor to read
nothing.

### T-01 — Has a section

Fine.
