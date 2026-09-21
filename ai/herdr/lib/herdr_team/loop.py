"""`team.sh loop` — which pane each `ready` row of the table goes to.

Reads the plan and `collect --plan`'s table and answers one tab-separated line
per dispatchable row: the Task, its lane, the provider the row asked for and
its `tier_reason`. `cmd_loop` in `team.sh` says which rows those are and what
it does with them.
"""

from __future__ import annotations

import sys
from typing import Any

from herdr_team.plan import plan_rows

__all__ = ["lane_for", "routes", "main"]


def lane_for(provider: str, blocks: list[str]) -> str:
    """`rev` for a `cc` row that blocks something, `exec` otherwise."""
    return "rev" if provider == "cc" and blocks else "exec"


def routes(plan: str, table: str) -> tuple[list[str], int]:
    """(route lines, exit code) for the `ready` rows of `table`."""
    parsed = plan_rows(plan)
    if parsed["findings"]:
        for finding in parsed["findings"]:
            sys.stderr.write("loop: %s\n" % finding)
        return [], 1

    rows = {r["task"]: r for r in parsed["rows"]}
    lines = []
    for line in table.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[1] != "ready":
            continue
        row: dict[str, Any] = rows.get(parts[0]) or {}
        # `-` rather than an empty field, because the wave reads this line with
        # `IFS=$'\t' read` and a tab is IFS whitespace there: two in a row
        # collapse into one delimiter, so a row with no provider but a
        # `tier_reason` would hand the reason over as the provider and spawn
        # the pane on `cc` with the row's own sentence as its `--tier-reason`.
        # The placeholder is read back to empty at the one place that decides a
        # tier.
        provider = row.get("provider") or "-"
        # Whitespace-collapsed: this is one tab-separated field on a line the
        # wave splits on tabs, and a reason written as two lines in the plan
        # would otherwise arrive as extra columns and be read as a lane or a
        # provider.
        reason = " ".join(str(row.get("tier_reason") or "").split())
        lane = lane_for(provider, row.get("blocks") or [])
        lines.append("%s\t%s\t%s\t%s" % (parts[0], lane, provider, reason))
    return lines, 0


def main(argv: list[str]) -> int:
    lines, code = routes(argv[0], argv[1])
    if code:
        return code
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
