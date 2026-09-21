"""The Python every `team.sh` verb runs.

Two kinds of module, and the difference is who imports them:

    plan.py         the reader of a plan's `## Tasks` block
    handoff.py      the reader of a handoff's frontmatter

are read by more than one subcommand, so each is one reader with a name. The
rest — `status`, `collect`, `collect_plan`, `report`, `wait`, `loop`,
`surface`, `lint` and `dispatch` — are one module per subcommand, each with a
`main(argv)` that `team.sh` runs as `herdr_py -m herdr_team.<name>`. `proquota`
is that same shape with one caller instead of a verb: `pro_window_used` in
`team.sh` runs it, and it reads the Pro 5h quota cache.

`team.sh` reaches them by setting `PYTHONPATH` to `lib/` on those calls, so
this package is never installed and has no `__init__` of its own beyond this
file. Nothing here is re-exported: an import that named `herdr_team.plan_rows`
would be a second way to reach the one reader, which is the thing this package
exists to avoid.
"""
