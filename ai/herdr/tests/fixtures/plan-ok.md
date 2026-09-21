# Fixture plan — two tasks, one dependency

Status: fixture. Not a real plan; `run.sh` dispatches against this file.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "cc", "files": ["README.md"],
   "verify": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1",
   "blocks": ["T-01"], "tier_reason": "review — a second model family reads what T-01 wrote"}
]
```

The `verify` string on T-02 contains a pipe on purpose: it is the case a
markdown table could not carry without an escaping rule. It leads with
`set -o pipefail` for the same reason every `verify` with a pipe must — a
pipeline's exit status is the last command's, so `… | tail -1` would exit 0
whatever markdownlint did, and an executor would observe 0 and claim
`evidence: verified` on a check that cannot fail.

Its `tier_reason` is what every `cc` row needs: T-02 has a `verify`, so by
`team.sh plan lint`'s reading it is a `ccd` row — unless it is one of the three
things no command settles, and a review is one of them (`references/cost.md`).
A `cc` row without that sentence is a row `spawn` refuses, so this fixture
carries one rather than modelling the omission.

### T-01 — A task with no blockers

Do the thing. This prose is what an executor reads after following the
pointer; `dispatch` never copies it into the prompt.

### T-02 — A task blocked on T-01

Do the other thing, which only makes sense once T-01 is verified.
