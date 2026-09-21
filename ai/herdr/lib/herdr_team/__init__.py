"""The readers `team.sh`'s `python3 -` blocks import.

Two modules, one per document more than one verb has to read the same way:

    plan.py     the reader of a plan's `## Tasks` block
    handoff.py  the reader of a handoff's frontmatter

`team.sh` reaches them by setting `PYTHONPATH` to `lib/` on the `python3 -`
blocks that import them, so this package is never installed and has no
`__init__` of its own beyond this file. Nothing here is re-exported: an import
that named `herdr_team.plan_rows` would be a second way to reach the one reader,
which is the thing this package exists to avoid.
"""
