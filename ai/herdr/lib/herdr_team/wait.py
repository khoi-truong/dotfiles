"""`team.sh wait` — the outstanding Dispatches under a Run, off the journal.

Every Dispatch the journal names whose handoff is not on disk yet, in the
three tab-separated columns `cmd_wait` reads them back as. A journal line this
code cannot read is a Dispatch it cannot watch, so it is named and refused
rather than skipped.
"""

from __future__ import annotations

import os
import sys

from herdr_team.handoff import dispatched, journal_malformed

__all__ = ["outstanding", "main"]


def outstanding(handoffs: str, run: str) -> list[tuple[str, str | None, str]]:
    """(task, dispatch, agent) per Dispatch under `run` with no handoff yet."""
    rows = []
    for task, rec in sorted(dispatched(handoffs, run).items()):
        path = os.path.join(handoffs, "%s-%s.md" % (task, rec["dispatch"]))
        if not os.path.exists(path):
            rows.append((task, rec["dispatch"], rec["agent"] or ""))
    return rows


def main(argv: list[str]) -> int:
    handoffs, run = argv[0], argv[1]

    bad = journal_malformed(handoffs, run)
    for line_no, text in bad:
        sys.stderr.write(
            "wait: journal line %d is not 3 or 4 columns: %s\n" % (line_no, text)
        )
    if bad:
        return 1

    for task, dispatch, agent in outstanding(handoffs, run):
        print("%s\t%s\t%s" % (task, dispatch, agent))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
