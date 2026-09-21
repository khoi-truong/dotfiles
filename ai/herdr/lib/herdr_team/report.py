"""`team.sh report` — the one verb that writes.

It reads a Run back off what the Run already left — the `.dispatched` journal
and the handoff frontmatter — and puts the answer in three places of
increasing durability: stdout for whoever is reading now, `report.json` for
the session that wants this Run without re-deriving it from handoffs, and one
line in `metrics.jsonl` for the series the executor cap and `plan lint`'s
granularity thresholds are argued from rather than guessed at.

`team.sh` states the contract above `cmd_report` — the exit codes, and why
writing is safe here — so what stands here is the reader, not the verb.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from typing import Any

from herdr_team.handoff import Meta, handoff_meta, journal_lines, unproven
from herdr_team.plan import plan_rows

__all__ = [
    "bound_providers",
    "column_widths",
    "pct",
    "plural",
    "provider_for",
    "recorded_field",
    "row_line",
    "wall_seconds",
    "main",
]


def recorded_field(panes: str, name: str, index: int) -> str:
    """Field `index` of the record `spawn` wrote for that pane, or empty.

    Empty rather than a placeholder, because the callers substitute: a
    provider falls back to the plan's own row, and a pane that never fell back
    has nothing to say about where it came from. Out of range is empty too,
    which is how a five-field record from an older Run reads — the field
    simply was not written then.
    """
    if not name:
        return ""
    try:
        with open(os.path.join(panes, name), encoding="utf-8") as fh:
            fields = fh.readline().rstrip("\n").split("\t")
        return fields[index] if len(fields) > index else ""
    except OSError:
        return ""


def bound_providers(handoffs: str, run: str) -> dict[tuple[str, str], tuple[str, str]]:
    """(task, dispatch) -> (provider, fell back from), from the Run's own note.

    From the Run's own `.providers`, not from the pane record, and preferred
    over it: a record is what a *live* pane holds, and `settle … release` and
    `teardown` both delete it — so a fallback read from there is a fallback
    that vanishes exactly when the pane it explains does, and the report bills
    a Run that ran a substitution as if it had run `ccd`. `dispatch` writes it
    down at the moment the Task is bound to the pane, which is the last moment
    the record is certainly there, so a Run with either one tells the same
    story about itself a month later.

    An absent key — not ("", "") — is a Dispatch with no note, which is every
    Dispatch of a Run that predates the file: the caller falls back to the
    record and then to the plan row, which is what it did before there was a
    file at all.
    """
    bound: dict[tuple[str, str], tuple[str, str]] = {}
    try:
        prov_lines = (
            open(os.path.join(handoffs, ".providers"), encoding="utf-8")
            .read()
            .splitlines()
        )
    except OSError:
        prov_lines = []
    for line in prov_lines:
        parts = line.split("\t")
        if len(parts) < 6 or parts[0] != run:
            continue
        bound[(parts[1], parts[2])] = (parts[4], parts[5])
    return bound


def provider_for(
    tid: str,
    winner: str,
    row: dict[str, Any],
    bound: dict[tuple[str, str], tuple[str, str]],
    sent_agent: dict[str, str],
    panes: str,
) -> tuple[str, str]:
    """(provider, fell back from) the winning Dispatch was sent on.

    The provider the winning Dispatch was sent on, and the plan's own row only
    when nothing wrote one down — a Run from before `.providers` or before
    records existed, or a pane nobody here started. It cannot be inferred: the
    journal has no provider in it, an agent name is `exec-<run>-N`, and
    reading the pane is not passive (herdr-adapter.md). The two sources
    disagreeing is itself worth seeing: the note is what was launched, the row
    is what was asked for, and a Run that quietly ran on the wrong credential
    is what a report is for.
    """
    note = bound.get((tid, winner))
    if note is not None:
        provider = note[0] or row.get("provider") or "-"
        fell_back = note[1]
    else:
        provider = (
            recorded_field(panes, sent_agent.get(tid, ""), 1)
            or row.get("provider")
            or "-"
        )
        fell_back = recorded_field(panes, sent_agent.get(tid, ""), 5)
    return provider, fell_back


def wall_seconds(newest: float, run_dir: str) -> int:
    """The newest handoff's mtime against the Run directory's own.

    And the only reason it is a number at all: the journal records no
    timestamps, so this is the closest honest answer. Both are approximations
    of a span — the directory's mtime is the Run's start only until the first
    `report` writes `report.json` into it, and the floor moves then. Every
    place it is printed says so, and metrics keeps the first value it saw for
    the Run rather than a later, shorter one.
    """
    return int(max(0, newest - os.path.getmtime(run_dir))) if newest else 0


def plural(n: int, one: str, many: str | None = None) -> str:
    return "%d %s" % (n, one if n == 1 else (many or one + "s"))


def pct(v: float | None) -> str:
    return "-" if v is None else "%.0f%%" % (v * 100)


def column_widths(head: tuple[str, ...], table: list[dict[str, Any]]) -> list[int]:
    """One width per column, wide enough for the header and every cell."""
    width = [len(c) for c in head]
    for r in table:
        width = [max(w, len(r[c])) for w, c in zip(width, head)]
    return width


def row_line(cells: list[str], width: list[int]) -> str:
    return "  ".join(c.ljust(w) for c, w in zip(cells, width)).rstrip()


def main(argv: list[str]) -> int:
    root, run, handoffs = argv[0], argv[1], argv[2]
    write = argv[3] == "1"
    handoff_max = int(argv[4])
    panes = argv[5]
    run_dir = os.path.join(root, "runs", run)

    bound = bound_providers(handoffs, run)

    # --- the plan, when this Run has one -----------------------------------
    # The path `run new --plan` wrote down, not the plan this shell happens to
    # be standing next to: a report is about that Run, and a Run knows its own
    # plan even from a tab that has never seen the file.
    plan: str | None = None
    try:
        plan = (
            open(os.path.join(run_dir, "plan"), encoding="utf-8").read().strip() or None
        )
    except OSError:
        plan = None

    row_by_id: dict[str, dict[str, Any]] = {}
    shape: dict[str, Any] | None = None
    if plan:
        parsed = plan_rows(plan)
        if parsed["findings"]:
            # Not a failure: the Run happened, and its handoffs are worth
            # reading either way. But a plan is why the Run exists, so a reader
            # is told what is wrong with it rather than left with a Run that
            # measures out to nothing. This is also the switch metrics keys off
            # below, which is why it is said out loud here rather than only
            # felt there.
            sys.stderr.write(
                "report: %s does not resolve: %s\n" % (plan, parsed["findings"][0])
            )
        else:
            row_by_id = {r["task"]: r for r in parsed["rows"]}
            shape = parsed["shape"]

    # --- what the Run left behind ------------------------------------------
    # Dispatch counts come off the journal, which is the only thing that tells
    # one attempt from two; outcomes come from the highest-id handoff, the same
    # fold `collect --plan` reads a Task through.
    sends: dict[str, int] = {}
    sent_max: dict[str, str] = {}
    sent_agent: dict[str, str] = {}
    for task, dispatch, agent in journal_lines(handoffs, run):
        sends[task] = sends.get(task, 0) + 1
        if dispatch > sent_max.get(task, ""):
            sent_max[task] = dispatch
            # The pane the winning Dispatch went to, which is the pane whose
            # record the provider is read off below. The losing attempt's pane
            # is not this Task's answer, and a retry that moved to another
            # provider should report the one that finished the work.
            sent_agent[task] = agent or ""

    by_task: dict[str, dict[str, Meta]] = {}
    lengths: dict[tuple[str, str], int] = {}
    newest: float = 0
    over_long: list[str] = []
    for path in sorted(glob.glob(os.path.join(handoffs, "*.md"))):
        meta = handoff_meta(path)
        if meta is None or meta.get("run") != run:
            continue
        tid, did = meta.get("task"), meta.get("dispatch")
        if not tid or not did:
            continue
        by_task.setdefault(tid, {})[did] = meta
        # Every handoff the Run wrote, not only the winning ones: a 200-line
        # handoff was 200 lines somebody read, and the retry that replaced it
        # did not make it shorter. This is also the only place the cap
        # protocol.md states is ever looked at, and it is a count here rather
        # than a refusal — by the time anyone could object, the file is written
        # and is the only record of what the agent did.
        n = len(open(path, encoding="utf-8").read().splitlines())
        lengths[(tid, did)] = n
        newest = max(newest, os.path.getmtime(path))
        if n > handoff_max:
            over_long.append("%s/%s" % (tid, did))

    # Rows are the Run's Tasks, not the plan's: a Task the plan never got to
    # has no handoff and is exactly what a reader wants to see, and a Dispatch
    # the plan has no row for is an anomaly a plan-only table would hide.
    #
    # The columns, in the order they print. One spelling of them, so the table,
    # the JSON beside it and the totals below cannot come to disagree about
    # which field is which — which is the one thing about a report anybody can
    # check.
    head = (
        "task",
        "dispatch",
        "outcome",
        "evidence",
        "provider",
        "sends",
        "lines",
        "verify",
    )
    table: list[dict[str, Any]] = []
    dispatches, retried, proven = 0, 0, 0
    providers: set[str] = set()
    fallbacks: list[tuple[str, str, str]] = []
    for tid in sorted(set(sends) | set(by_task) | set(row_by_id)):
        row = row_by_id.get(tid) or {}
        hs = by_task.get(tid, {})
        # The journal is the record of Dispatches; a handoff with no line under
        # it arrived some other way (moved by hand, or written before the
        # journal existed), and counting the files is the closest honest answer
        # for it.
        count = sends.get(tid, 0) or len(hs)
        if hs:
            # The highest Dispatch id wins, the same fold `collect --plan`
            # makes: a Task that failed at D-01 and succeeded at D-02 is done,
            # not failed.
            winner = max(hs)
            meta = hs[winner]
            outcome = meta.get("outcome") or "-"
            evidence = meta.get("evidence") or "-"
            lines = str(lengths.get((tid, winner), 0))
            # Proved through the same function `collect --plan` reads `done`
            # through: two tables disagreeing about one handoff would be worse
            # than either alone.
            why = unproven(meta, row.get("verify") or "")
            verify = why or ("ok" if row.get("verify") else "-")
        elif count:
            # Journalled and unanswered: the Dispatch is still out, or the Run
            # was abandoned with it out. Either way there is no outcome yet,
            # and `running` is the word `collect --plan` already uses for
            # exactly this.
            winner = sent_max.get(tid, "-")
            outcome, evidence, lines, verify = "running", "-", "-", "-"
        else:
            winner, outcome, evidence, lines, verify = "-", "-", "-", "-", "-"
        provider, fell_back = provider_for(tid, winner, row, bound, sent_agent, panes)
        if provider != "-":
            providers.add(provider)
        # The provider that pane fell back from, when `spawn` had to substitute
        # one. Its own line below rather than a wider provider column: the
        # column is on one line of a table whose readers match a row by shape,
        # and a fallback is a fact about the Run worth reading in a sentence,
        # not a fifth glyph in a cell. `cc` alone would report a substitution
        # as a choice.
        if fell_back:
            fallbacks.append((tid, fell_back, provider))
        if verify == "ok":
            proven += 1
        dispatches += count
        if count > 1:
            retried += 1
        table.append(
            {
                "task": tid,
                "dispatch": winner,
                "outcome": outcome,
                "evidence": evidence,
                "provider": provider,
                "sends": str(count),
                "lines": lines,
                "verify": verify,
                "fallback": fell_back or None,
            }
        )

    total = len(table)
    # Rated over the Tasks whose plan row states a `verify`, not over every
    # row: a planner that answered "no command settles this" is not a pass and
    # not a fail, and folding it into the denominator would quietly move the
    # number this series exists to make comparable.
    rated = [t for t in row_by_id if (row_by_id[t].get("verify") or "").strip()]
    retry_rate = round(retried / total, 3) if total else None
    verify_rate = round(proven / len(rated), 3) if rated else None

    wall = wall_seconds(newest, run_dir)

    width = column_widths(head, table)

    print("%s  plan %s" % (run, plan or "(none)"))
    if newest:
        print(
            "wall ~%ds (approximate: newest handoff mtime against the Run directory's)"
            % wall
        )
    else:
        print("wall: unknown — no handoff has landed to measure against")
    print()
    print(row_line(list(head), width))
    print("  ".join("-" * w for w in width))
    for r in table:
        print(row_line([r[c] for c in head], width))
    print()
    footer = [
        plural(total, "task"),
        plural(dispatches, "dispatch", "dispatches"),
        "retry rate %s" % pct(retry_rate),
        "verify pass rate %s" % pct(verify_rate),
    ]
    over = "%s over %d lines" % (plural(len(over_long), "handoff"), handoff_max)
    if over_long:
        over += " (%s)" % " ".join(sorted(over_long))
    footer.append(over)
    print("  ".join(footer))
    # A substitution is the one thing about a Run that its provider column
    # cannot say, because the column is right: the work did run on `cc`. This
    # is the line that says it was not supposed to.
    if fallbacks:
        print(
            "fallback(s): %s"
            % "  ".join(
                "%s %s→%s" % (tid, src, dst) for tid, src, dst in sorted(fallbacks)
            )
        )

    payload = {
        "run": run,
        "plan": plan,
        "shape": shape,
        "wall_seconds": wall,
        "wall_approximate": True,
        "tasks": [
            {
                "task": r["task"],
                "dispatch": r["dispatch"],
                "outcome": r["outcome"],
                "evidence": r["evidence"],
                "provider": r["provider"],
                "fallback": r["fallback"],
                "dispatches": int(r["sends"]),
                "handoff_lines": None if r["lines"] == "-" else int(r["lines"]),
                "verify": r["verify"],
            }
            for r in table
        ],
        "totals": {
            "tasks": total,
            "dispatches": dispatches,
            "retried_tasks": retried,
            "retry_rate": retry_rate,
            "verify_rated": len(rated),
            "verify_proven": proven,
            "verify_pass_rate": verify_rate,
            "over_long_handoffs": len(over_long),
            "fallbacks": len(fallbacks),
        },
    }
    metrics = {
        "run": run,
        "plan": plan,
        "tasks": total,
        "dispatches": dispatches,
        "retry_rate": retry_rate,
        "verify_pass_rate": verify_rate,
        "wall_seconds": wall,
        "providers": sorted(providers),
        "fallbacks": len(fallbacks),
        "plan_depth": (shape or {}).get("depth"),
        "plan_width": (shape or {}).get("width"),
        "over_long_handoffs": len(over_long),
    }

    if not write:
        print("--no-write: report.json and metrics.jsonl untouched")
        return 0

    os.makedirs(run_dir, exist_ok=True)
    report_path = os.path.join(run_dir, "report.json")
    with open(report_path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print("report.json: %s" % report_path)

    # One Run, one line, appended and never rewritten or pruned by any verb
    # here — the point of a series is that the earlier numbers are still there.
    # Read back first so a second `report` on the same Run does not add a
    # second row: the first is the snapshot of the Run as it stood, and a
    # series that gained a line every time somebody looked at it would measure
    # looking, not working.
    metrics_path = os.path.join(root, "metrics.jsonl")
    recorded = set()
    try:
        with open(metrics_path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    recorded.add(json.loads(line)["run"])
                except (ValueError, KeyError, TypeError):
                    # A line this code cannot read costs its own row, not the
                    # series: the append below still happens.
                    continue
    except OSError:
        pass

    if run in recorded:
        print("metrics.jsonl: %s already recorded — not appended" % run)
    elif not shape:
        # A Run whose plan does not resolve is a Run whose numbers are not
        # comparable with the rest of the series (no depth, no width), and a
        # smoke test against a fixture is exactly this shape. Nothing was
        # measured, so nothing is recorded.
        print("metrics.jsonl: no plan resolves for %s — not appended" % run)
    else:
        # One write of one line to a file opened `a`: the same guarantee a
        # single `printf >>` gives, without a second process holding the
        # descriptor.
        with open(metrics_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(metrics, sort_keys=True) + "\n")
        print("metrics.jsonl: appended %s" % run)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
