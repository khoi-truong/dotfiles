"""`team.sh dispatch --from-plan` — the body for one Task named in a plan.

The body is a pointer, not a copy: the executor reads the section out of the
plan file itself, and `plan_body` in `team.sh` says why an absolute path is
what makes that readable from every pane.
"""

from __future__ import annotations

import glob
import os
import sys
from typing import Any

from herdr_team.handoff import handoff_meta, unproven
from herdr_team.plan import plan_rows

__all__ = ["body_for", "settled_tasks", "unmet_blockers", "main"]


def settled_tasks(
    handoffs: str, run: str, by_id: dict[str, dict[str, Any]]
) -> set[str | None]:
    """The Tasks settled under `run`, for this Run only.

    Task ids restart every Run and handoff filenames carry no Run, so the
    frontmatter is the only thing that scopes them. This stays out of
    `plan_rows`: it is the dispatch gate, not a property of the document.
    """
    settled: set[str | None] = set()
    for path in glob.glob(os.path.join(handoffs, "*.md")):
        meta = handoff_meta(path)
        if meta is None or meta.get("run") != run:
            continue
        # 'succeeded' at 'reported' is a claim, not a result: it does not settle.
        if meta.get("outcome") != "succeeded" or meta.get("evidence") != "verified":
            continue
        # The blocker's own `verify`, out of its row: the gate and
        # `collect --plan` ask `unproven()` the same question about the same
        # handoff on purpose, so the two cannot reach opposite verdicts about
        # one file. 'verified' is the agent's word for a check; this is the
        # check itself, and a Task whose commands do not carry it is not
        # settled here either. Stricter than this gate used to be,
        # deliberately: `--force` is the way past it.
        #
        # `or ""` for the lookup only: a handoff stating no `task` names no row
        # and so has no blocker, which is the same answer an absent key gets.
        blocker = by_id.get(meta.get("task") or "")
        if unproven(meta, (blocker or {}).get("verify") or ""):
            continue
        settled.add(meta.get("task"))
    return settled


def unmet_blockers(row: dict[str, Any], settled: set[str | None]) -> list[str]:
    """The row's blockers that have no verified handoff under this Run."""
    return [b for b in row.get("blocks", []) if b not in settled]


def body_for(plan: str, task: str, row: dict[str, Any], verify: str) -> str:
    """The prompt body: the section to read, the files, and the verify."""
    body = ['Read %s, section "### %s". Do that task and nothing else.' % (plan, task)]
    files = row.get("files") or []
    if files:
        body.append("Files in scope: %s" % " ".join(files))
    if verify:
        body.append(
            "Your verification command is:\n\n  %s\n\n"
            "Run it, record it in commands: with the exit code you observed, and\n"
            "only then claim evidence: verified." % verify
        )
    return "\n\n".join(body)


def main(argv: list[str]) -> int:
    plan, task, run, handoffs, force = argv[0], argv[1], argv[2], argv[3], argv[4]
    plan = os.path.abspath(plan)

    # A malformed plan fails whole, before any pane is spawned, so the linter
    # and the dispatcher can never disagree about whether a document is
    # dispatchable.
    parsed = plan_rows(plan)
    if parsed["findings"]:
        return _fail("dispatch: %s" % parsed["findings"][0])

    by_id = {r["task"]: r for r in parsed["rows"]}
    row = by_id.get(task)
    if row is None:
        return _fail("dispatch: %s has no row for %s" % (plan, task))

    settled = settled_tasks(handoffs, run, by_id)

    unmet = unmet_blockers(row, settled)
    if unmet:
        if force != "1":
            sys.stderr.write(
                "dispatch: %s is blocked on %s (no verified handoff under run %s)\n"
                "  retry is human-gated: pass --force to dispatch anyway\n"
                % (task, " ".join(unmet), run)
            )
            return 3
        sys.stderr.write(
            "dispatch: --force: %s dispatched over unmet %s\n" % (task, " ".join(unmet))
        )

    print(body_for(plan, task, row, row.get("verify") or ""))
    return 0


def _fail(message: str) -> int:
    """Say why on stderr and answer 1, which is what `main` returns."""
    sys.stderr.write("%s\n" % message)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
