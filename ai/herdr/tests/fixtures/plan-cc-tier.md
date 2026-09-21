# Fixture plan — a `cc` row with nothing saying why

Status: fixture. Exercises the tier check in `plan_rows`, which warns about a
`cc` row a command could settle and stays silent on one that answers the
question. Both readings are in here, side by side, because the pair is what
makes the check a check rather than a blanket refusal of `cc`. Every warning
here is a warning: the exit stays 0.

## Tasks

```json
[
  {"task": "T-01", "provider": "ccd", "files": ["ai/setup.sh"],
   "verify": "shellcheck -x ai/setup.sh", "blocks": []},
  {"task": "T-02", "provider": "cc", "files": ["README.md"],
   "verify": "npx markdownlint-cli2 README.md", "blocks": []},
  {"task": "T-03", "provider": "cc", "files": ["ai/herdr/team.sh"],
   "verify": "bash ai/herdr/tests/run.sh", "blocks": [],
   "tier_reason": "review — a second model family reads what T-01 wrote"}
]
```

T-02 has a `verify`, so a command settles it: by the tier rule it is a `ccd`
row, and nothing here says why it is not. T-03 has the same shape and carries
the sentence, so it draws no warning. T-01 is the third answer — a `ccd` row
nothing is asked of — and all three block nothing, so neither the depth nor the
width warning is in the way of the one this fixture is about.

### T-01 — A ccd row

Nothing is asked of this one.

### T-02 — A cc row that says nothing

The row the warning names: a command settles it, and no `tier_reason` says why
it is on Pro anyway.

### T-03 — A cc row that says why

The same shape with the sentence filled in: a review, which no command settles
however much it runs one.
