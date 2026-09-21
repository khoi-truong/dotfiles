"""Unit tests for `herdr_team`'s one-module-per-subcommand family.

`run.sh` is the end-to-end suite: it drives `team.sh` and asserts on what a
verb prints and the code it exits with. This file is the other half of the same
coverage for the ten readers `team.sh` now reaches with `python3 -m` — it calls
each function directly, so a mistake inside one of them is named as that
function rather than as whatever the verb happened to print first, and a reader
that stopped being reachable from `team.sh` at all still fails here.

One section per module, in the order `team.sh` declares the verbs. The cases
are the ones the end-to-end suite cannot state cheaply: a refusal that turns on
a clock the harness cannot wait for (`window_used` takes `now`), a fallback
column that only exists in a record from a newer Run (`provider_of`), and the
fold that decides a retried Task is done rather than failed (`settled_state`).
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

import pytest

from herdr_team import (
    collect,
    collect_plan,
    dispatch,
    lint,
    loop,
    proquota,
    report,
    status,
    surface,
    wait,
)
from herdr_team.handoff import Meta, missing_fields

# The journal shape `dispatched` returns, named here so the literals below are
# checked against the fold rather than against whatever this file inferred.
Sent = dict[str, dict[str, str | None]]

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def meta(**fields: str) -> Meta:
    """A handoff's frontmatter with the five required fields already filled.

    The defaults are a first Dispatch that verified: a case that wants a
    different one overrides the field it is about, so the reason it differs is
    the argument rather than a whole literal to read side by side.
    """
    m: Meta = {
        "run": "R-1",
        "task": "T-01",
        "dispatch": "D-01",
        "outcome": "succeeded",
        "evidence": "verified",
    }
    m.update(fields)
    return m


def handoff(omit: tuple[str, ...] = (), **fields: str) -> str:
    """The file `dispatch`'s prompt tells an agent to write, as `meta` says.

    `omit` is the other half of `meta`: a frontmatter that carries a field with
    no value still states the field, so the only way to write a handoff that is
    missing one is to leave its line out.
    """
    m = meta(**fields)
    for k in omit:
        del m[k]
    return "---\n%s\n---\n\n## What was done\n" % "\n".join(
        "%s: %s" % (k, v) for k, v in m.items()
    )


def verified_cmd(cmd: str) -> str:
    """A `commands:` block of one command that ran `cmd` and passed.

    `json.dumps` is what spells it, because that is what an agent writing a
    command with a quote in it produces: a YAML double-quoted scalar, escapes
    and all.
    """
    return "\n  - cmd: %s\n    exit: 0" % json.dumps(cmd)


# --- `handoff.missing_fields` -------------------------------------------------
# What both `collect` and `collect --plan` require of a handoff, in the order
# the handoff contract states it.
@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({}, ["run", "task", "dispatch", "outcome", "evidence"]),
        ({"task": "T-01"}, ["run", "dispatch", "outcome", "evidence"]),
        ({"evidence": "verified"}, ["run", "task", "dispatch", "outcome"]),
        (
            {"outcome": "failed", "cause": "timeout"},
            ["run", "task", "dispatch", "evidence"],
        ),
    ],
)
def test_missing_fields_names_what_is_absent_in_contract_order(
    fields: dict[str, str], expected: list[str]
) -> None:
    assert missing_fields(fields) == expected


def test_missing_fields_is_empty_for_a_complete_handoff() -> None:
    assert missing_fields(meta(cause="null", artifacts="a.md")) == []


# --- `proquota` ---------------------------------------------------------------
CACHE: dict[str, Any] = {
    "rate_limits": {"five_hour": {"used_percentage": 43.7, "resets_at": 2000.0}},
    "cached_at": 950.0,
}


@pytest.mark.parametrize(
    ("data", "now", "max_age", "expected"),
    [
        # Stamped 50s ago, window resets at 2000: a number, truncated.
        (CACHE, 1000.0, 300, 43),
        # The window has already reset, so the percentage is the old window's.
        (CACHE, 2000.0, 300, None),
        (CACHE, 2100.0, 300, None),
        # Stamped in the future: a clock this reader cannot trust.
        (CACHE, 900.0, 300, None),
        # 450s old against a caller that allows 300.
        (CACHE, 1400.0, 300, None),
        ({}, 1000.0, 300, None),
        ({"rate_limits": {}}, 1000.0, 300, None),
        ({"rate_limits": {"five_hour": None}}, 1000.0, 300, None),
        (
            {
                "rate_limits": {
                    "five_hour": {"resets_at": 2000.0, "used_percentage": "x"}
                }
            },
            1000.0,
            300,
            None,
        ),
        ([], 1000.0, 300, None),
    ],
)
def test_window_used_refuses_anything_that_is_not_a_number(
    data: Any, now: float, max_age: int, expected: int | None
) -> None:
    assert proquota.window_used(data, now, max_age) == expected


def test_main_refuses_a_limit_that_is_not_a_number(
    capsys: pytest.CaptureFixture[str],
) -> None:
    assert proquota.main(["/nonexistent/cache.json", "not-a-number"]) == 0
    assert capsys.readouterr().out == ""


def test_main_is_silent_about_a_cache_that_is_not_there(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert proquota.main([str(tmp_path / "absent.json"), "300"]) == 0
    assert capsys.readouterr().out == ""


def test_main_prints_the_window_it_can_read(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    # `cached_at` is stamped now because that is the only clock `main` has:
    # the three refusals above are what `now` in the signature is for.
    cache = tmp_path / "cache.json"
    cache.write_text(
        json.dumps(
            {
                "rate_limits": {
                    "five_hour": {
                        "used_percentage": 12.6,
                        "resets_at": time.time() + 3600,
                    }
                },
                "cached_at": time.time(),
            }
        )
    )
    assert proquota.main([str(cache), "300"]) == 0
    assert capsys.readouterr().out == "12\n"


# --- `status` -----------------------------------------------------------------
@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("exec-051624-7", "051624"),
        ("exec-051624-10", "051624"),
        # Six digits or nothing: a guessed Run is worse than a dash.
        ("exec-05162-1", "-"),
        ("exec-0516241-2", "-"),
        ("exec-1", "-"),
        ("orch-051624-1", "-"),
        ("", "-"),
    ],
)
def test_exec_run_suffix(name: str, expected: str) -> None:
    assert status.exec_run_suffix(name) == expected


def test_provider_of_shows_a_fallback_as_both_providers(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-1").write_text(
        "exec-051624-1\tcc\tpane-1\t/work\tbranch\tccd\n"
    )
    assert status.provider_of(str(tmp_path), "exec-051624-1") == "ccd→cc"


def test_provider_of_is_the_record_alone_without_a_fallback(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-2").write_text(
        "exec-051624-2\tcc\tpane-2\t/work\tbranch\n"
    )
    assert status.provider_of(str(tmp_path), "exec-051624-2") == "cc"


def test_provider_of_is_unknown_without_a_record(tmp_path: Path) -> None:
    assert status.provider_of(str(tmp_path), "exec-051624-3") == "unknown"
    (tmp_path / "exec-051624-4").write_text("")
    assert status.provider_of(str(tmp_path), "exec-051624-4") == "unknown"


def test_agent_lines_names_the_run_and_the_provider(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-1").write_text(
        "exec-051624-1\tccd\tpane-1\t/work\tbranch\tcc\n"
    )
    doc = json.dumps(
        {
            "result": {
                "agents": [
                    {
                        "name": "exec-051624-1",
                        "pane_id": "pane-1",
                        "agent_status": "working",
                        "cwd": "/work",
                    }
                ]
            }
        }
    )
    lines = status.agent_lines(doc, str(tmp_path))
    assert len(lines) == 1
    assert lines[0].split() == [
        "exec-051624-1",
        "051624",
        "cc→ccd",
        "pane-1",
        "working",
        "/work",
    ]


def test_agent_lines_says_so_when_there_are_no_agents(tmp_path: Path) -> None:
    assert status.agent_lines(
        json.dumps({"result": {"agents": []}}), str(tmp_path)
    ) == ["no agents"]


def test_handoff_lines_counts_what_the_run_left(tmp_path: Path) -> None:
    (tmp_path / "T-01-D-01.md").write_text(handoff())
    assert status.handoff_lines(str(tmp_path), "R-1") == [
        "",
        "1 handoff(s) in %s" % tmp_path,
        "  T-01-D-01.md",
    ]


def test_handoff_lines_points_at_run_new_without_a_run(tmp_path: Path) -> None:
    assert status.handoff_lines(str(tmp_path), "") == [
        "",
        "no Run started — team.sh run new",
    ]


# --- `collect` ----------------------------------------------------------------
def test_collect_table_lines_formats_a_row_and_appends_its_receipt() -> None:
    row = meta(cause="tool_error", artifacts="a.md, b.md")
    assert collect.table_lines([row], [], "R-1") == [
        "R-1          T-01   D-01   succeeded verified  tool_error  artifacts: a.md b.md"
    ]


def test_collect_table_lines_omits_the_cause_and_receipt_a_handoff_lacks() -> None:
    lines = collect.table_lines([meta()], [], "R-1")
    assert lines[0].split() == ["R-1", "T-01", "D-01", "succeeded", "verified"]
    assert "artifacts" not in lines[0]


def test_collect_table_lines_names_a_malformed_handoff_after_the_rows() -> None:
    assert collect.table_lines([meta()], [("bad.md", "no frontmatter")], "R-1")[-1] == (
        "MALFORMED bad.md (no frontmatter)"
    )


@pytest.mark.parametrize(
    ("run", "expected"),
    [("R-1", ["no handoffs for run R-1"]), ("", ["no handoffs"])],
)
def test_collect_table_lines_says_when_there_is_nothing(
    run: str, expected: list[str]
) -> None:
    assert collect.table_lines([], [], run) == expected


def test_read_rows_finds_every_run_under_the_state_root(tmp_path: Path) -> None:
    d = tmp_path / "runs" / "R-1" / "handoffs"
    d.mkdir(parents=True)
    (d / "T-01-D-01.md").write_text(handoff())
    rows, bad = collect.read_rows("", str(tmp_path / "runs"), "R-1")
    assert [r["task"] for r in rows] == ["T-01"]
    assert bad == []


def test_read_rows_separates_another_run_and_a_handoff_that_cannot_be_a_row(
    tmp_path: Path,
) -> None:
    (tmp_path / "T-01-D-01.md").write_text(handoff())
    (tmp_path / "T-02-D-01.md").write_text(handoff(task="T-02", run="R-2"))
    (tmp_path / "T-03-D-01.md").write_text("no frontmatter here\n")
    (tmp_path / "T-04-D-01.md").write_text(handoff(task="T-04", omit=("dispatch",)))
    rows, bad = collect.read_rows(str(tmp_path), str(tmp_path), "R-1")
    assert [r["task"] for r in rows] == ["T-01"]
    assert bad == [
        ("T-03-D-01.md", "no frontmatter"),
        ("T-04-D-01.md", "missing dispatch"),
    ]


# --- `collect_plan` -----------------------------------------------------------
ROW: dict[str, Any] = {"task": "T-01", "verify": ""}


def test_settled_state_is_unknown_without_a_handoff_or_a_dispatch() -> None:
    assert collect_plan.settled_state(ROW, {}, {}) is None


def test_settled_state_is_running_when_only_the_journal_speaks() -> None:
    sent: Sent = {"T-01": {"dispatch": "D-01", "agent": "exec-051624-1"}}
    assert collect_plan.settled_state(ROW, {}, sent) == (
        "running",
        "D-01",
        "dispatched, no handoff yet",
    )


def test_settled_state_is_done_when_verified_and_the_row_names_no_verify() -> None:
    assert collect_plan.settled_state(ROW, {"T-01": {"D-01": meta()}}, {}) == (
        "done",
        "D-01",
        "succeeded/verified",
    )


def test_settled_state_is_review_when_the_agent_only_reported() -> None:
    seen = {"T-01": {"D-01": meta(evidence="reported")}}
    assert collect_plan.settled_state(ROW, seen, {}) == (
        "review",
        "D-01",
        "succeeded/reported",
    )


def test_settled_state_is_review_when_the_rows_verify_is_not_in_the_handoff() -> None:
    row = {"task": "T-01", "verify": "make test"}
    assert collect_plan.settled_state(row, {"T-01": {"D-01": meta()}}, {}) == (
        "review",
        "D-01",
        "UNVERIFIED succeeded/verified",
    )


def test_settled_state_is_failed_with_the_cause_it_reported() -> None:
    seen = {"T-01": {"D-01": meta(outcome="failed", cause="timeout")}}
    assert collect_plan.settled_state(ROW, seen, {}) == (
        "failed",
        "D-01",
        "failed/verified (timeout)",
    )


def test_settled_state_is_failed_without_a_null_cause() -> None:
    seen = {"T-01": {"D-01": meta(outcome="failed", cause="null")}}
    assert collect_plan.settled_state(ROW, seen, {}) == (
        "failed",
        "D-01",
        "failed/verified",
    )


def test_settled_state_reads_a_retry_at_its_highest_dispatch() -> None:
    seen = {"T-01": {"D-01": meta(outcome="failed"), "D-02": meta()}}
    assert collect_plan.settled_state(ROW, seen, {}) == (
        "done",
        "D-02",
        "succeeded/verified",
    )


def test_settled_state_is_running_when_the_journal_is_ahead_of_the_handoffs() -> None:
    seen = {"T-01": {"D-01": meta()}}
    sent: Sent = {"T-01": {"dispatch": "D-02", "agent": "exec-051624-1"}}
    assert collect_plan.settled_state(ROW, seen, sent) == (
        "running",
        "D-02",
        "dispatched, no handoff yet",
    )


def test_receipt_names_the_newest_dispatches_artifacts() -> None:
    seen = {
        "T-01": {"D-01": meta(artifacts="old.md"), "D-02": meta(artifacts="new.md")}
    }
    assert collect_plan.receipt("T-01", seen) == ["new.md"]


def test_receipt_is_empty_before_a_handoff_lands() -> None:
    assert collect_plan.receipt("T-01", {}) == []
    assert collect_plan.receipt("T-01", {"T-01": {"D-01": meta()}}) == []


@pytest.mark.parametrize(
    ("states", "expected"),
    [
        # A Task the plan does not list: the journal is the Run's record, and a
        # Dispatch in it is out whether or not a row mentions it.
        ({}, True),
        ({"T-01": None}, False),
        ({"T-01": ("running", "D-01", "dispatched, no handoff yet")}, True),
        ({"T-01": ("done", "D-01", "succeeded/verified")}, False),
        ({"T-01": ("review", "D-01", "succeeded/reported")}, False),
    ],
)
def test_outstanding(
    states: dict[str, collect_plan.State | None], expected: bool
) -> None:
    assert collect_plan.outstanding("T-01", states) is expected


def test_releasable_names_a_done_tasks_agent() -> None:
    sent: Sent = {"T-01": {"dispatch": "D-01", "agent": "exec-051624-1"}}
    states: dict[str, collect_plan.State | None] = {"T-01": ("done", "D-01", "x")}
    assert collect_plan.releasable("T-01", "exec-051624-1", sent, states) == (
        "releasable exec-051624-1"
    )


def test_releasable_is_silent_while_the_agent_owes_another_task() -> None:
    sent: Sent = {
        "T-01": {"dispatch": "D-01", "agent": "exec-051624-1"},
        "T-02": {"dispatch": "D-01", "agent": "exec-051624-1"},
    }
    states: dict[str, collect_plan.State | None] = {
        "T-01": ("done", "D-01", "x"),
        "T-02": ("running", "D-01", "dispatched, no handoff yet"),
    }
    assert collect_plan.releasable("T-01", "exec-051624-1", sent, states) is None


def test_releasable_names_an_agent_whose_other_task_has_settled() -> None:
    sent: Sent = {
        "T-01": {"dispatch": "D-01", "agent": "exec-051624-1"},
        "T-02": {"dispatch": "D-01", "agent": "exec-051624-1"},
    }
    states: dict[str, collect_plan.State | None] = {
        "T-01": ("done", "D-01", "x"),
        "T-02": ("done", "D-01", "x"),
    }
    assert collect_plan.releasable("T-01", "exec-051624-1", sent, states) == (
        "releasable exec-051624-1"
    )


@pytest.mark.parametrize("agent", [None, ""])
def test_releasable_is_silent_without_an_agent_name(agent: str | None) -> None:
    states: dict[str, collect_plan.State | None] = {"T-01": ("done", "D-01", "x")}
    assert collect_plan.releasable("T-01", agent, {}, states) is None


def test_plan_out_reads_a_row_with_nothing_against_it_as_ready() -> None:
    parsed: dict[str, Any] = {"rows": [{"task": "T-01", "verify": ""}]}
    assert collect_plan.plan_out(parsed, {}, {}) == [("T-01", "ready", None, "-", [])]


def test_plan_out_blocks_a_row_whose_blocker_is_not_done() -> None:
    parsed: dict[str, Any] = {
        "rows": [
            {"task": "T-01", "verify": ""},
            {"task": "T-02", "verify": "", "blocks": ["T-01"]},
        ]
    }
    assert collect_plan.plan_out(parsed, {}, {})[1] == (
        "T-02",
        "blocked",
        None,
        "blocked on T-01",
        [],
    )


def test_plan_out_clears_a_blocker_that_is_done() -> None:
    parsed: dict[str, Any] = {
        "rows": [
            {"task": "T-01", "verify": ""},
            {"task": "T-02", "verify": "", "blocks": ["T-01"]},
        ]
    }
    out = collect_plan.plan_out(parsed, {"T-01": {"D-01": meta()}}, {})
    assert out[0][:3] == ("T-01", "done", "D-01")
    assert out[1] == ("T-02", "ready", None, "-", [])


def test_plan_out_marks_a_done_task_releasable() -> None:
    parsed: dict[str, Any] = {"rows": [{"task": "T-01", "verify": ""}]}
    seen = {"T-01": {"D-01": meta()}}
    sent: Sent = {"T-01": {"dispatch": "D-01", "agent": "exec-051624-1"}}
    out = collect_plan.plan_out(parsed, seen, sent)
    assert out[0][3] == "releasable exec-051624-1 succeeded/verified"


def test_plan_table_lines_appends_a_receipt() -> None:
    out: list[tuple[str, str, str | None, str, list[str]]] = [
        ("T-02", "done", "D-01", "succeeded/verified", ["a.md", "b.md"])
    ]
    assert collect_plan.table_lines(out, []) == [
        "T-02   done     D-01   succeeded/verified  artifacts: a.md b.md"
    ]


def test_plan_table_lines_omits_the_receipt_a_task_has_none_for() -> None:
    out: list[tuple[str, str, str | None, str, list[str]]] = [
        ("T-02", "failed", "D-01", "failed/verified", [])
    ]
    assert collect_plan.table_lines(out, []) == [
        "T-02   failed   D-01   failed/verified"
    ]


def test_plan_table_lines_names_a_malformed_handoff_after_the_rows() -> None:
    assert collect_plan.table_lines([], [("T-01-D-01.md", "missing outcome")]) == [
        "MALFORMED T-01-D-01.md (missing outcome)"
    ]


# The plan `run.sh` dispatches against, and the `verify` its two rows carry:
# settling a row takes a handoff whose commands hold that string, so the
# exit-code cases below spell both out rather than reaching for the row.
PLAN = str(FIXTURES / "plan-ok.md")
VERIFY = {
    "T-01": "shellcheck -x ai/setup.sh",
    "T-02": "set -o pipefail; npx markdownlint-cli2 README.md | tail -1",
}


def test_collect_plan_main_is_zero_while_a_row_can_be_dispatched(
    tmp_path: Path,
) -> None:
    """No handoffs at all: T-01 is ready, which is the orchestrator's signal."""
    assert collect_plan.main([PLAN, "R-1", str(tmp_path)]) == 0


def test_collect_plan_main_is_one_for_a_plan_that_does_not_resolve(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = collect_plan.main([str(FIXTURES / "plan-cycle.md"), "R-1", str(tmp_path)])
    assert code == 1
    assert "collect: blocks has a cycle" in capsys.readouterr().err


def test_collect_plan_main_is_one_for_a_handoff_that_cannot_be_a_row(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "T-01-D-01.md").write_text(handoff(task="T-01", omit=("evidence",)))
    assert collect_plan.main([PLAN, "R-1", str(tmp_path)]) == 1
    assert "MALFORMED T-01-D-01.md (missing evidence)" in capsys.readouterr().out


def test_collect_plan_main_is_two_when_a_row_failed(tmp_path: Path) -> None:
    (tmp_path / "T-01-D-01.md").write_text(
        handoff(task="T-01", outcome="failed", cause="timeout")
    )
    assert collect_plan.main([PLAN, "R-1", str(tmp_path)]) == 2


def test_collect_plan_main_is_three_when_every_row_is_done(tmp_path: Path) -> None:
    """T-02 is done as well as T-01: done is the only state left to report."""
    for task in ("T-01", "T-02"):
        (tmp_path / ("%s-D-01.md" % task)).write_text(
            handoff(task=task, commands=verified_cmd(VERIFY[task]))
        )
    assert collect_plan.main([PLAN, "R-1", str(tmp_path)]) == 3


# --- `wait` -------------------------------------------------------------------
def test_wait_outstanding_lists_a_dispatch_with_no_handoff(tmp_path: Path) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\texec-051624-1\n")
    assert wait.outstanding(str(tmp_path), "R-1") == [("T-01", "D-01", "exec-051624-1")]


def test_wait_outstanding_skips_a_dispatch_its_handoff_answers(tmp_path: Path) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\texec-051624-1\n")
    (tmp_path / "T-01-D-01.md").write_text(handoff())
    assert wait.outstanding(str(tmp_path), "R-1") == []


def test_wait_outstanding_reports_a_three_column_line_without_an_agent(
    tmp_path: Path,
) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\n")
    assert wait.outstanding(str(tmp_path), "R-1") == [("T-01", "D-01", "")]


def test_wait_outstanding_skips_what_a_teardown_gave_up_on(tmp_path: Path) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\texec-051624-1\n")
    (tmp_path / ".abandoned").write_text("R-1\tT-01\tD-01\n")
    assert wait.outstanding(str(tmp_path), "R-1") == []


def test_wait_outstanding_reads_nothing_from_a_directory_that_is_not_the_runs() -> None:
    assert wait.outstanding("", "R-1") == []


# --- `loop` -------------------------------------------------------------------
@pytest.mark.parametrize(
    ("provider", "blocks", "expected"),
    [
        ("cc", ["T-01"], "rev"),
        ("cc", [], "exec"),
        ("ccd", ["T-01"], "exec"),
        ("-", ["T-01"], "exec"),
    ],
)
def test_lane_for(provider: str, blocks: list[str], expected: str) -> None:
    assert loop.lane_for(provider, blocks) == expected


def test_routes_sends_a_cc_row_that_blocks_something_to_review() -> None:
    lines, code = loop.routes(str(FIXTURES / "plan-ok.md"), "T-02  ready\n")
    assert code == 0
    assert lines[0].split("\t")[:3] == ["T-02", "rev", "cc"]


def test_routes_skips_a_row_that_is_not_ready() -> None:
    lines, code = loop.routes(str(FIXTURES / "plan-ok.md"), "T-02  done\n")
    assert (lines, code) == ([], 0)


def test_routes_names_a_row_the_plan_does_not_have_as_a_placeholder() -> None:
    lines, code = loop.routes(str(FIXTURES / "plan-ok.md"), "T-09  ready\n")
    assert code == 0
    assert lines[0].split("\t") == ["T-09", "exec", "-", ""]


def test_routes_refuses_a_plan_it_cannot_read(
    capsys: pytest.CaptureFixture[str],
) -> None:
    lines, code = loop.routes(str(FIXTURES / "plan-cycle.md"), "T-02  ready\n")
    assert (lines, code) == ([], 1)
    assert "loop: blocks has a cycle" in capsys.readouterr().err


# --- `report` -----------------------------------------------------------------
@pytest.mark.parametrize(
    ("n", "one", "many", "expected"),
    [
        (1, "task", None, "1 task"),
        (2, "task", None, "2 tasks"),
        (0, "task", None, "0 tasks"),
        (1, "dispatch", "dispatches", "1 dispatch"),
        (2, "dispatch", "dispatches", "2 dispatches"),
    ],
)
def test_plural(n: int, one: str, many: str | None, expected: str) -> None:
    assert report.plural(n, one, many) == expected


@pytest.mark.parametrize(
    ("v", "expected"),
    [(None, "-"), (0.0, "0%"), (0.5, "50%"), (0.667, "67%"), (1.0, "100%")],
)
def test_pct(v: float | None, expected: str) -> None:
    assert report.pct(v) == expected


def test_column_widths_fit_the_header_and_every_cell() -> None:
    head = ("task", "provider")
    table: list[dict[str, Any]] = [
        {"task": "T-01-long", "provider": "cc"},
        {"task": "T-02", "provider": "ccd"},
    ]
    assert report.column_widths(head, table) == [9, 8]


def test_row_line_pads_between_cells_and_trims_the_tail() -> None:
    assert report.row_line(["T-01", "cc"], [6, 8]) == "T-01    cc"
    # A row whose last column is empty ends at the column before it, which is
    # what keeps the table from carrying trailing whitespace nobody can see.
    assert report.row_line(["T-01", ""], [6, 8]) == "T-01"


def test_recorded_field_reads_the_column_spawn_wrote(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-1").write_text(
        "exec-051624-1\tcc\tpane-1\t/work\tx\tccd\n"
    )
    assert report.recorded_field(str(tmp_path), "exec-051624-1", 1) == "cc"
    assert report.recorded_field(str(tmp_path), "exec-051624-1", 5) == "ccd"


def test_recorded_field_is_empty_for_a_five_field_record_or_no_record(
    tmp_path: Path,
) -> None:
    (tmp_path / "exec-051624-2").write_text("exec-051624-2\tcc\tpane-2\t/work\tx\n")
    assert report.recorded_field(str(tmp_path), "exec-051624-2", 5) == ""
    assert report.recorded_field(str(tmp_path), "exec-051624-9", 1) == ""
    assert report.recorded_field(str(tmp_path), "", 1) == ""


def test_bound_providers_reads_the_runs_own_note(tmp_path: Path) -> None:
    (tmp_path / ".providers").write_text("R-1\tT-01\tD-01\texec-051624-1\tcc\tccd\n")
    assert report.bound_providers(str(tmp_path), "R-1") == {
        ("T-01", "D-01"): ("cc", "ccd")
    }


def test_bound_providers_ignores_another_run_and_a_short_line(tmp_path: Path) -> None:
    (tmp_path / ".providers").write_text(
        "R-2\tT-01\tD-01\texec-1\tcc\tccd\nR-1\tT-02\tD-02\texec-2\tcc\n"
    )
    assert report.bound_providers(str(tmp_path), "R-1") == {}


def test_bound_providers_is_empty_without_the_file(tmp_path: Path) -> None:
    assert report.bound_providers(str(tmp_path), "R-1") == {}


def test_provider_for_prefers_the_runs_note_to_the_pane_record(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-1").write_text(
        "exec-051624-1\tcc\tpane-1\t/work\tx\tccd\n"
    )
    bound = {("T-01", "D-01"): ("ccd", "cc")}
    sent = {"T-01": "exec-051624-1"}
    assert report.provider_for(
        "T-01", "D-01", {"provider": "cc"}, bound, sent, str(tmp_path)
    ) == (
        "ccd",
        "cc",
    )


def test_provider_for_reads_a_noteless_dispatch_from_the_record(tmp_path: Path) -> None:
    (tmp_path / "exec-051624-1").write_text(
        "exec-051624-1\tcc\tpane-1\t/work\tx\tccd\n"
    )
    sent = {"T-01": "exec-051624-1"}
    assert report.provider_for("T-01", "D-01", {}, {}, sent, str(tmp_path)) == (
        "cc",
        "ccd",
    )


def test_provider_for_falls_back_to_the_plan_row_then_to_a_dash(tmp_path: Path) -> None:
    row = {"provider": "ccd"}
    assert report.provider_for("T-01", "D-01", row, {}, {}, str(tmp_path)) == (
        "ccd",
        "",
    )
    assert report.provider_for("T-01", "D-01", {}, {}, {}, str(tmp_path)) == ("-", "")


def test_provider_for_reads_a_provider_from_the_row_when_the_note_is_empty(
    tmp_path: Path,
) -> None:
    bound = {("T-01", "D-01"): ("", "cc")}
    assert report.provider_for(
        "T-01", "D-01", {"provider": "ccd"}, bound, {}, str(tmp_path)
    ) == (
        "ccd",
        "cc",
    )


def test_wall_seconds_measures_the_newest_handoff_against_the_run_directory(
    tmp_path: Path,
) -> None:
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    os.utime(run_dir, (1000.0, 1000.0))
    assert report.wall_seconds(1012.5, str(run_dir)) == 12


def test_wall_seconds_is_zero_without_a_handoff_and_is_never_negative(
    tmp_path: Path,
) -> None:
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    os.utime(run_dir, (1000.0, 1000.0))
    assert report.wall_seconds(0.0, str(run_dir)) == 0
    assert report.wall_seconds(900.0, str(run_dir)) == 0


# --- `surface` ----------------------------------------------------------------
def test_surface_header_names_the_task_and_dispatch(tmp_path: Path) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\texec-051624-1\n")
    assert surface.header_lines(str(tmp_path), "R-1", "exec-051624-1") == [
        "Run: R-1",
        "Task: T-01",
        "Dispatch: D-01",
    ]


def test_surface_header_says_unknown_and_warns_rather_than_refusing(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert surface.header_lines(str(tmp_path), "", "exec-051624-1") == [
        "Run: unknown",
        "Task: unknown",
        "Dispatch: unknown",
    ]
    assert (
        "no journal line under (no Run) names exec-051624-1" in capsys.readouterr().err
    )


def test_surface_header_reads_no_journal_from_the_working_directory(
    tmp_path: Path,
) -> None:
    (tmp_path / ".dispatched").write_text("R-1\tT-01\tD-01\texec-051624-1\n")
    assert surface.header_lines("", "R-1", "exec-051624-1") == [
        "Run: R-1",
        "Task: unknown",
        "Dispatch: unknown",
    ]


# --- `dispatch` ---------------------------------------------------------------
def test_unmet_blockers_lists_what_has_no_verified_handoff() -> None:
    assert dispatch.unmet_blockers({"blocks": ["T-01", "T-02"]}, {"T-01"}) == ["T-02"]


def test_unmet_blockers_is_empty_without_blocks() -> None:
    assert dispatch.unmet_blockers({}, set()) == []
    assert dispatch.unmet_blockers({"blocks": ["T-01"]}, {"T-01"}) == []


def test_body_for_points_at_the_section_and_the_files_in_scope() -> None:
    body = dispatch.body_for("/p/plan.md", "T-01", {"files": ["a.sh", "b.md"]}, "")
    assert body.split("\n\n") == [
        'Read /p/plan.md, section "### T-01". Do that task and nothing else.',
        "Files in scope: a.sh b.md",
    ]


def test_body_for_carries_the_verify_and_what_evidence_means() -> None:
    body = dispatch.body_for("/p/plan.md", "T-01", {}, "make test")
    assert body.startswith('Read /p/plan.md, section "### T-01".')
    assert "  make test\n" in body
    assert "evidence: verified" in body


def test_body_for_is_one_paragraph_without_files_or_a_verify() -> None:
    assert "\n\n" not in dispatch.body_for("/p/plan.md", "T-01", {}, "")


# The gate's own reading of a handoff, which is `collect --plan`'s reading of
# the same file: both ask `unproven` about the blocker's row.
def test_settled_tasks_takes_a_handoff_that_carries_the_rows_verify(
    tmp_path: Path,
) -> None:
    (tmp_path / "T-01-D-01.md").write_text(
        handoff(task="T-01", commands=verified_cmd(VERIFY["T-01"]))
    )
    by_id = {"T-01": {"task": "T-01", "verify": VERIFY["T-01"]}}
    assert dispatch.settled_tasks(str(tmp_path), "R-1", by_id) == {"T-01"}


def test_settled_tasks_ignores_a_handoff_that_never_ran_the_verify(
    tmp_path: Path,
) -> None:
    """`evidence: verified` is the agent's word for a check; this is the check."""
    (tmp_path / "T-01-D-01.md").write_text(
        handoff(task="T-01", commands=verified_cmd("make lint"))
    )
    by_id = {"T-01": {"task": "T-01", "verify": VERIFY["T-01"]}}
    assert dispatch.settled_tasks(str(tmp_path), "R-1", by_id) == set()


def test_settled_tasks_ignores_a_report_and_another_runs_handoff(
    tmp_path: Path,
) -> None:
    (tmp_path / "T-01-D-01.md").write_text(handoff(task="T-01", evidence="reported"))
    (tmp_path / "T-02-D-01.md").write_text(handoff(task="T-02", run="R-2"))
    by_id = {
        "T-01": {"task": "T-01", "verify": ""},
        "T-02": {"task": "T-02", "verify": ""},
    }
    assert dispatch.settled_tasks(str(tmp_path), "R-1", by_id) == set()


def test_settled_tasks_settles_nothing_for_a_handoff_that_names_no_task(
    tmp_path: Path,
) -> None:
    """It settles the empty Task id, which no row can be called."""
    (tmp_path / "x.md").write_text(handoff(omit=("task",)))
    assert dispatch.settled_tasks(str(tmp_path), "R-1", {}) == {None}


def test_dispatch_main_is_one_for_a_task_the_plan_has_no_row_for(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert dispatch.main([PLAN, "T-99", "R-1", str(tmp_path), "0"]) == 1
    assert "has no row for T-99" in capsys.readouterr().err


def test_dispatch_main_is_three_for_a_task_still_blocked(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert dispatch.main([PLAN, "T-02", "R-1", str(tmp_path), "0"]) == 3
    assert "is blocked on T-01" in capsys.readouterr().err


def test_dispatch_main_dispatches_over_a_blocker_settled_by_a_handoff(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "T-01-D-01.md").write_text(
        handoff(task="T-01", commands=verified_cmd(VERIFY["T-01"]))
    )
    assert dispatch.main([PLAN, "T-02", "R-1", str(tmp_path), "0"]) == 0
    assert "is blocked on" not in capsys.readouterr().err


def test_dispatch_main_force_dispatches_over_an_unmet_blocker(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert dispatch.main([PLAN, "T-02", "R-1", str(tmp_path), "1"]) == 0
    assert "--force: T-02 dispatched over unmet T-01" in capsys.readouterr().err


# --- `lint` -------------------------------------------------------------------
def test_lint_forwards_the_findings_of_a_plan_that_does_not_resolve() -> None:
    path, findings, _ = lint.lint(str(FIXTURES / "plan-cycle.md"))
    assert path == str(FIXTURES / "plan-cycle.md")
    assert findings == ["blocks has a cycle: T-01 -> T-02 -> T-01"]


def test_lint_blesses_a_plan_and_measures_its_shape() -> None:
    path, findings, shape = lint.lint(str(FIXTURES / "plan-ok.md"))
    assert path == str(FIXTURES / "plan-ok.md")
    assert findings == []
    assert shape is not None
    assert shape["tasks"] == 2
