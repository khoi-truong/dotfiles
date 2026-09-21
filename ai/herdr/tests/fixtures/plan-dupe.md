# Fixture plan — two rows under one task id

Status: fixture. The shape that reads clean to every other check and is still
two Dispatches at one Task: both rows name `T-01`, there is a `### T-01`
section for them, nothing blocks on anything, and no id is dangling. Without
the duplicate finding `collect --plan` emits two `ready` lines for the one
section and a `--spawn` wave seats both on two branches.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/herdr/team.sh"],
   "verify": "shellcheck -x ai/herdr/team.sh", "blocks": []},
  {"task": "T-01", "provider": "ccd", "files": ["lib/common.sh"],
   "verify": "shellcheck -x lib/common.sh", "blocks": []}
]
```

### T-01 — The only section

One section, and it says nothing about which of the two rows is meant. That is
the point: a second row does not make a second Task, it makes a second attempt
at this one, and an attempt is a Dispatch id rather than a plan row.
