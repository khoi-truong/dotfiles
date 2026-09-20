# Fixture plan — a `verify` that cannot fail

Status: fixture. Exercises the masked-exit-code check.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["README.md"], "verify": "npx markdownlint-cli2 README.md | tail -1", "blocks": []}
]
```

A pipeline exits with its last stage's status, so `tail -1` reports 0
whatever markdownlint found. An executor would observe 0 and claim
`evidence: verified` on a check with no power to fail. The fix is to lead
with `set -o pipefail`, which is what `plan-ok.md` does.

### T-01 — Verified by a command that always succeeds

The defect is in the row, not in the prose.
