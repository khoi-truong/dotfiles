"""`team.sh plan lint` — a thin alias over `plan_rows`.

It owns no parsing of its own: a linter that read the block separately from
the dispatcher would eventually bless a plan the dispatcher refuses, or worse,
the other way round. What it does own is the order the findings, the shape
line and the warnings print in, which `cmd_plan` in `team.sh` states.
"""

from __future__ import annotations

import os
import sys
from typing import Any

from herdr_team.plan import plan_rows

__all__ = ["lint", "main"]


def lint(plan: str) -> tuple[str, list[str], dict[str, Any] | None]:
    """(path, findings, shape) for the plan at `plan`, the path made absolute."""
    plan = os.path.abspath(plan)
    parsed = plan_rows(plan)
    findings: list[str] = parsed["findings"]
    shape: dict[str, Any] | None = parsed["shape"]
    return plan, findings, shape


def main(argv: list[str]) -> int:
    plan, findings, shape = lint(argv[0])
    for finding in findings:
        print(finding)
    if not findings:
        print("%s: ok" % plan)
    # The plan's own shape, last, so it is the line an eye lands on after the
    # findings. Its warnings go to stderr and change no exit code: a deep plan
    # is sometimes correct, and what this reports is economics rather than
    # validity. The measurements stay on stdout for the caller — `report`
    # reads a plan's depth and width back out of this line rather than
    # re-deriving them.
    if shape:
        for warning in shape["warnings"]:
            sys.stderr.write("lint: %s\n" % warning)
        print(
            "depth %d  width %d  tasks %d"
            % (shape["depth"], shape["width"], shape["tasks"])
        )
    # Every finding at once, where dispatch stops at the first: a planner
    # fixing its own output should not have to run the check seven times.
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
