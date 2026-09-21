"""`team.sh status` — the live agent table, then one Run's handoffs.

The agent table and the handoff list are two questions about two scopes, and
`cmd_status` in `team.sh` says which: every Run's panes, one Run's handoffs.
"""

from __future__ import annotations

import glob
import json
import os
import re
import sys

__all__ = ["agent_lines", "exec_run_suffix", "handoff_lines", "provider_of", "main"]


def provider_of(panes: str, name: str) -> str:
    """The provider `spawn` recorded for that pane, or `unknown`.

    Recorded rather than inferred: a provider is not in the agent's name (an
    `exec-` name is a Run and an index) and not readable off its screen, and a
    table that guessed would be most wrong about exactly the panes a reader is
    about to count. A pane with no record — hand-started, or spawning while
    this file is being read — is `unknown`, which is the same bucket the
    provider ceiling counts it in.

    A pane that fell back shows both providers, `ccd→cc`, because either alone
    is a half-truth: `cc` reads as a decision somebody made, and `ccd` as the
    provider the task asked for and did not get.
    """
    try:
        with open(os.path.join(panes, name), encoding="utf-8") as fh:
            fields = fh.readline().rstrip("\n").split("\t")
        provider = fields[1] or "unknown"
        fell_back = fields[5] if len(fields) > 5 else ""
        return "%s→%s" % (fell_back, provider) if fell_back else provider
    except (OSError, IndexError):
        return "unknown"


def exec_run_suffix(name: str) -> str:
    """The Run suffix in an executor's name, or `-`.

    An executor's name says which Run it works: `exec-<run-suffix>-N`, the
    suffix being the last field of `R-<date>-<hhmmss>`, so a table holding
    three orchestrators' executors reads as three groups instead of a flat run
    of `exec-1`. Six digits or nothing: a pane named any other way — another
    role, or the older hand-typed `exec-1` — has no Run in its name, and a
    guessed one would be worse than the dash.
    """
    m = re.match(r"^exec-(\d{6})-", name)
    return m.group(1) if m else "-"


def agent_lines(doc: str, panes: str) -> list[str]:
    """The agent table, from `herdr agent list`'s JSON on `doc`."""
    d = json.loads(doc)
    agents = d["result"]["agents"]
    if not agents:
        return ["no agents"]
    lines = []
    w = max(len(a.get("name") or a["pane_id"]) for a in agents)
    for a in sorted(agents, key=lambda a: a["pane_id"]):
        name = a.get("name") or a["pane_id"]
        lines.append(
            "%-*s  %-6s  %-8s  %-8s  %-8s  %s"
            % (
                w,
                name,
                exec_run_suffix(name),
                provider_of(panes, name),
                a["pane_id"],
                a.get("agent_status", "?"),
                a.get("cwd", ""),
            )
        )
    return lines


def handoff_lines(handoffs: str, run: str) -> list[str]:
    """The Run's handoff count and its newest ten, or the way to start one."""
    if not run:
        return ["", "no Run started — team.sh run new"]
    pending = sorted(glob.glob(os.path.join(handoffs, "*.md")))
    lines = ["", "%d handoff(s) in %s" % (len(pending), handoffs)]
    for p in pending[-10:]:
        lines.append("  " + os.path.basename(p))
    return lines


def main(argv: list[str]) -> int:
    handoffs, run, agents_json, panes = argv[0], argv[1], argv[2], argv[3]
    for line in agent_lines(agents_json, panes):
        print(line)
    for line in handoff_lines(handoffs, run):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
