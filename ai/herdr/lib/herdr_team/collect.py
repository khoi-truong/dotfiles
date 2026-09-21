"""`team.sh collect` — one row per handoff, over one Run or every Run.

Which one is `cmd_collect`'s decision in `team.sh`: a named Run, the caller's
own handoff directory, or every Run under the state root.
"""

from __future__ import annotations

import glob
import os
import sys

from herdr_team.handoff import Meta, artifacts, handoff_meta, missing_fields

__all__ = ["read_rows", "table_lines", "main"]


def read_rows(
    handoffs: str, runs_root: str, run: str
) -> tuple[list[Meta], list[tuple[str, str]]]:
    """(rows, malformed) over the handoffs one Run covers.

    One directory when a Run is named, or when the caller has its own; empty
    means neither, and no Run named is every Run.
    """
    # A Run id is R-<date>-<time>: globbing that shape cannot pick up a stray
    # directory under runs/ that is not one.
    dirs = (
        [handoffs]
        if handoffs
        else sorted(glob.glob(os.path.join(runs_root, "R-*", "handoffs")))
    )
    rows: list[Meta] = []
    bad: list[tuple[str, str]] = []
    for path in sorted(p for d in dirs for p in glob.glob(os.path.join(d, "*.md"))):
        # Through handoff_meta rather than a second copy of its six lines: this
        # table and `collect --plan` reading one handoff two ways is the failure
        # `herdr_team.handoff` exists to make impossible.
        meta = handoff_meta(path)
        if meta is None:
            bad.append((os.path.basename(path), "no frontmatter"))
            continue
        if run and meta.get("run") != run:
            continue
        missing = missing_fields(meta)
        if missing:
            bad.append((os.path.basename(path), "missing " + ",".join(missing)))
            continue
        rows.append(meta)
    return rows, bad


def table_lines(rows: list[Meta], bad: list[tuple[str, str]], run: str) -> list[str]:
    """The table, one line per row and one per malformed handoff."""
    if not rows and not bad:
        return ["no handoffs" + (" for run %s" % run if run else "")]
    lines = []
    for m in rows:
        line = "%-12s %-6s %-6s %-9s %-9s %s" % (
            m["run"],
            m["task"],
            m["dispatch"],
            m["outcome"],
            m.get("evidence", "-"),
            m.get("cause", "") or "",
        )
        # The receipt is appended rather than given a column of its own: a row
        # for a handoff that names no artifact stays byte-for-byte what it
        # always was, which is what lets the path be read off the same table as
        # everything else without anything already reading it having to change.
        arts = artifacts(m)
        if arts:
            line += "  artifacts: %s" % " ".join(arts)
        lines.append(line)
    for name, why in bad:
        lines.append("MALFORMED %s (%s)" % (name, why))
    return lines


def main(argv: list[str]) -> int:
    handoffs, runs_root, run = argv[0], argv[1], argv[2]
    rows, bad = read_rows(handoffs, runs_root, run)
    for line in table_lines(rows, bad, run):
        print(line)
    # An unreadable handoff is a failed Dispatch, not a missing one.
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
