"""`team.sh surface` — the header above one agent's screen.

Whose question it is, from the journal, and never a refusal: an agent can be
live without a line under this Run and its screen is still worth showing, so
the header says unknown rather than naming a Task it cannot know. `cmd_surface`
in `team.sh` says why that is the opposite of `wait`'s rule about a line it
cannot read.
"""

from __future__ import annotations

import sys

from herdr_team.handoff import dispatched

__all__ = ["header_lines", "main"]


def header_lines(handoffs: str, run: str, agent: str) -> list[str]:
    """The Run, Task and Dispatch that `agent` is holding, or `unknown`."""
    rows = sorted(
        (t, r["dispatch"])
        for t, r in dispatched(handoffs, run).items()
        if r["agent"] == agent
    )
    lines = ["Run: %s" % (run or "unknown")]
    for task, dispatch in rows:
        lines.append("Task: %s" % task)
        lines.append("Dispatch: %s" % dispatch)
    if not rows:
        lines.append("Task: unknown")
        lines.append("Dispatch: unknown")
        sys.stderr.write(
            "surface: no journal line under %s names %s\n" % (run or "(no Run)", agent)
        )
    return lines


def main(argv: list[str]) -> int:
    handoffs, run, agent = argv[0], argv[1], argv[2]
    for line in header_lines(handoffs, run, agent):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
