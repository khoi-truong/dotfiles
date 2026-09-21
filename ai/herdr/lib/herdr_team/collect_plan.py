"""`team.sh collect --plan` — one row per Task in the plan, not per handoff.

The table and the exit codes are the contract, and `team.sh` states both above
`cmd_collect_plan`: this module is the reader that produces them. It reports
and never decides — it writes no state and blocks no dispatch.
"""

from __future__ import annotations

import glob
import os
import sys
from typing import Any, Optional

from herdr_team.handoff import (
    Meta,
    artifacts,
    dispatched,
    handoff_meta,
    missing_fields,
    unproven,
)
from herdr_team.plan import plan_rows

__all__ = [
    "Receipt",
    "State",
    "outstanding",
    "plan_out",
    "receipt",
    "releasable",
    "settled_state",
    "table_lines",
    "main",
]

# One Task's settled state: the name, the Dispatch it came off, and the detail
# column. None is a Task no handoff and no journal line mentions.
#
# `Optional[…]` rather than `X | None`, and the reason is not style: an alias is
# an assignment, so it is evaluated when the module is imported, and
# `from __future__ import annotations` defers annotations only. The interpreter
# `team.sh` calls is macOS's `/usr/bin/python3`, which is 3.9 — where the `|`
# operand is a TypeError at import, and every verb reading this module exits 1
# before it does anything. The rest of the module stays 3.10-shaped because the
# work below is inside annotations, which never reach the interpreter.
State = tuple[str, Optional[str], str]

# A Task's newest handoff's `artifacts:`.
Receipt = list[str]

# task -> dispatch id -> frontmatter, and task -> its journal record.
Seen = dict[str, dict[str, Meta]]
Sent = dict[str, dict[str, Optional[str]]]


def settled_state(row: dict[str, Any], seen: Seen, sent: Sent) -> State | None:
    """State from this Task's own handoffs, or None when it has none.

    The highest Dispatch id wins. Without that fold a Task that failed at
    D-01 and was retried to success at D-02 reads `failed` forever, and an
    orchestrator loop can never terminate.
    """
    tid = row["task"]
    hs = seen.get(tid)
    last_sent = sent.get(tid, {}).get("dispatch")
    if not hs:
        return (
            ("running", last_sent, "dispatched, no handoff yet") if last_sent else None
        )
    last = max(hs)
    if last_sent and last_sent > last:
        return "running", last_sent, "dispatched, no handoff yet"
    m = hs[last]
    detail = "%s/%s" % (m["outcome"], m.get("evidence", "-"))
    if m["outcome"] == "succeeded":
        # Verified is the only evidence that settles a Task; a claim is work
        # to dispatch a reviewer at, not a result.
        if m.get("evidence") != "verified":
            return "review", last, detail
        why = unproven(m, row.get("verify") or "")
        if why:
            # Not `done` — the row's own verify is not in the handoff — but not
            # a failure either. `review` is what sends a reviewer at it, and a
            # dependent stays `blocked` on it rather than building on a claim.
            return "review", last, "%s %s" % (why, detail)
        return "done", last, detail
    # An agent that reports `blocked` needs a human exactly as a failure does.
    # The `blocked` state name is already spoken for by the dependency sense.
    cause = m.get("cause") or ""
    if cause and cause != "null":
        detail += " (%s)" % cause
    return "failed", last, detail


def receipt(tid: str, seen: Seen) -> Receipt:
    """The Task's newest handoff's `artifacts:`, or [] while it has none.

    The newest Dispatch id, the same fold `settled_state` reads: a retry that
    names a different receipt is the one that counts. A Task with no handoff
    yet has written nothing, so there is nothing to name.
    """
    hs = seen.get(tid)
    if not hs:
        return []
    return artifacts(hs[max(hs)])


def outstanding(tid: str, states: dict[str, State | None]) -> bool:
    """True when this Task still has a Dispatch out with an agent.

    The fold `wait` blocks on and `running` already means here: the journal
    sent it, no handoff has landed. A Task the plan does not list counts as
    outstanding too — the journal is the Run's record, and a Dispatch in it is
    out whether or not a row mentions it.
    """
    if tid not in states:
        return True
    known = states[tid]
    return known is not None and known[0] == "running"


def releasable(
    tid: str, agent: str | None, sent: Sent, states: dict[str, State | None]
) -> str | None:
    """`releasable <agent>` for a done Task whose agent owes nothing else.

    Reporting only: `collect` names the agent and settles nothing. Settlement
    stays an explicit `settle` call, because it is a decision with three
    answers and picking one silently is how a worktree someone wanted to keep
    gets destroyed.

    An agent still needed elsewhere is not named. Release destroys a worktree,
    so the marker has to mean done with the Run rather than done with this
    Task — an agent holding a second outstanding Task is still working away on
    it, and settling the pane it is working in would throw that work away.
    """
    if not agent:
        # A journal line written before the agent column existed: no name to
        # settle, so nothing to name.
        return None
    for other in sent:
        if (
            other != tid
            and sent[other].get("agent") == agent
            and outstanding(other, states)
        ):
            return None
    return "releasable %s" % agent


def plan_out(
    parsed: dict[str, Any], seen: Seen, sent: Sent
) -> list[tuple[str, str, str | None, str, Receipt]]:
    """(task, state, dispatch, detail, artifacts) per row, in plan order."""
    states: dict[str, State | None] = {}
    for row in parsed["rows"]:
        states[row["task"]] = settled_state(row, seen, sent)

    out = []
    for row in parsed["rows"]:
        tid = row["task"]
        known = states[tid]
        if known:
            state, dispatch, detail = known
            if state == "done":
                mark = releasable(tid, sent.get(tid, {}).get("agent"), sent, states)
                if mark:
                    detail = "%s %s" % (mark, detail)
            out.append((tid, state, dispatch, detail, receipt(tid, seen)))
            continue
        blocks = row.get("blocks") or []
        # One `states.get` rather than a `.get` for the test and a subscript for
        # the answer: the subscript is what mypy refuses to narrow, and reading
        # the same key twice invites the two reads to disagree.
        unmet = []
        for b in blocks:
            blocker = states.get(b)
            if blocker is None or blocker[0] != "done":
                unmet.append(b)
        if unmet:
            out.append((tid, "blocked", None, "blocked on %s" % " ".join(unmet), []))
        else:
            out.append((tid, "ready", None, "-", []))
    return out


def table_lines(
    out: list[tuple[str, str, str | None, str, Receipt]],
    bad: list[tuple[str, str]],
) -> list[str]:
    """The table, one line per Task and one per malformed handoff."""
    lines = []
    for tid, state, dispatch, detail, arts in out:
        line = "%-6s %-8s %-6s %s" % (tid, state, dispatch or "-", detail)
        # Appended, not its own column, for the reason `collect` gives: a Task
        # with no artifact to name reads exactly as it did before this existed.
        if arts:
            line += "  artifacts: %s" % " ".join(arts)
        lines.append(line)
    for name, why in bad:
        lines.append("MALFORMED %s (%s)" % (name, why))
    return lines


def main(argv: list[str]) -> int:
    plan, run, handoffs = argv[0], argv[1], argv[2]
    plan = os.path.abspath(plan)

    parsed = plan_rows(plan)
    if parsed["findings"]:
        for finding in parsed["findings"]:
            sys.stderr.write("collect: %s\n" % finding)
        return 1

    # Handoffs for this Run, indexed task -> dispatch id -> frontmatter.
    bad: list[tuple[str, str]] = []
    seen: Seen = {}
    for path in sorted(glob.glob(os.path.join(handoffs, "*.md"))):
        name = os.path.basename(path)
        meta = handoff_meta(path)
        if meta is None:
            bad.append((name, "no frontmatter"))
            continue
        if meta.get("run") != run:
            continue
        missing = missing_fields(meta)
        if missing:
            bad.append((name, "missing " + ",".join(missing)))
            continue
        seen.setdefault(meta["task"], {})[meta["dispatch"]] = meta

    sent = dispatched(handoffs, run)

    out = plan_out(parsed, seen, sent)

    for line in table_lines(out, bad):
        print(line)

    if bad:
        return 1
    if any(s in ("ready", "review") for _, s, _, _, _ in out):
        return 0
    if any(s == "failed" for _, s, _, _, _ in out):
        return 2
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
