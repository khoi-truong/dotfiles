# Fixture plan — a row that names no provider and says why it is on Pro

Status: fixture. The wave reads a route as one tab-separated line —
`task`, `lane`, `provider`, `reason` — and `IFS=$'\t' read` treats a tab as IFS
whitespace, so two in a row are one delimiter. A row with no `provider` and a
`tier_reason` therefore arrived as a row whose provider *was* the reason, and
`spawn` refused it as a provider nothing knows. The row below is that shape and
nothing else: no `provider` at all, everything in `tier_reason`.

## Tasks

```json
[
  {"task": "T-01", "files": ["ai/herdr/team.sh"],
   "verify": "bash ai/herdr/tests/run.sh", "blocks": [],
   "tier_reason": "review — a second model family reads what the executor wrote"}
]
```

### T-01 — A row with no provider and a reason

The reason is the last field on the route and the only one after the lane. Read
as the provider it is a name `spawn` refuses; read as a reason it is a `ccd` row
with nothing said about its tier, which is what a row that names no provider is.
