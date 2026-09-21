# Fixture plan — two tasks, one dependency

Status: fixture. Not a real plan; `run.sh` dispatches against this file.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "cc", "files": ["README.md"],
   "verify": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1",
   "blocks": ["T-01"]}
]
```

The `verify` string on T-02 contains a pipe on purpose: it is the case a
markdown table could not carry without an escaping rule. It leads with
`set -o pipefail` for the same reason every `verify` with a pipe must — a
pipeline's exit status is the last command's, so `… | tail -1` would exit 0
whatever markdownlint did, and an executor would observe 0 and claim
`evidence: verified` on a check that cannot fail.

### T-01 — A task with no blockers

Do the thing. This prose is what an executor reads after following the
pointer; `dispatch` never copies it into the prompt.

### T-02 — A task blocked on T-01

Do the other thing, which only makes sense once T-01 is verified.
