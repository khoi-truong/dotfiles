"""Unit tests for `herdr_team.plan`, the reader of a plan's `## Tasks` block.

`run.sh` is the end-to-end suite: it drives `team.sh` and asserts on what a
verb prints and the code it exits with. This file is the other half of the
same coverage — it calls the reader directly, so a check that regressed inside
`plan_rows` is named as that check rather than as whatever `plan lint` happened
to print first, and a reader that stopped being reachable from `team.sh` at
all still fails here.

The inputs are the fixtures `run.sh` dispatches against, so the two suites
cannot drift about what a plan means: `tests/fixtures/plan-*.md` is the one
place a defect is described, and each case below says which line of which
fixture it is reading.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from herdr_team.plan import plan_rows

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def parsed(name: str) -> dict[str, Any]:
    """`plan_rows` over a fixture, by file name."""
    return plan_rows(str(FIXTURES / name))


def findings(name: str) -> list[str]:
    # Named rather than returned straight through: `plan_rows` answers a
    # `dict[str, Any]`, and a helper whose return type is checked is what keeps
    # a typo in a key from reading as an empty list here and nowhere else.
    found: list[str] = parsed(name)["findings"]
    return found


def warnings(name: str) -> list[str]:
    shape = parsed(name)["shape"]
    warned: list[str] = shape["warnings"]
    return warned


# --- the findings ------------------------------------------------------------
# One case per defect a plan can carry. The two whose text embeds the plan's own
# path are asserted by suffix rather than by equality, because the path is the
# one the caller passed in and not something this reader invents.
@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("plan-cycle.md", ["blocks has a cycle: T-01 -> T-02 -> T-01"]),
        ("plan-dangling.md", ["T-01 blocks on T-09, which has no row"]),
        (
            "plan-masking-verify.md",
            [
                "T-01: verify pipes without a leading 'set -o pipefail', so its "
                "exit code is the last stage's and the check cannot fail"
            ],
        ),
    ],
)
def test_findings(name: str, expected: list[str]) -> None:
    assert findings(name) == expected


@pytest.mark.parametrize(
    ("name", "suffix"),
    [
        ("plan-dupe.md", " has two rows for T-01: one Task, one row"),
        ("plan-orphan.md", " has sections with no row: T-02"),
        ("plan-no-section.md", " has a row for T-02 but no '### T-02' section"),
        ("plan-no-block.md", " has no '## Tasks' json block"),
    ],
)
def test_findings_that_name_the_plan(name: str, suffix: str) -> None:
    assert len(findings(name)) == 1
    assert findings(name)[0].endswith(suffix)


def test_unparseable_json_is_a_finding_not_an_exception() -> None:
    """The trailing comma is the fixture's whole point."""
    assert findings("plan-bad-json.md")[0].startswith("task block is not valid JSON: ")


def test_every_finding_at_once() -> None:
    """`plan lint` reports all of them, so a planner fixes its output once."""
    assert [f.split(" has sections")[0] for f in findings("plan-many.md")] == [
        str(FIXTURES / "plan-many.md"),
        "T-01 blocks on T-09, which has no row",
    ] + [
        "T-01: verify pipes without a leading 'set -o pipefail', so its exit "
        "code is the last stage's and the check cannot fail"
    ]


def test_a_plan_that_cannot_be_read_is_a_finding(tmp_path: Path) -> None:
    missing = tmp_path / "not-there.md"
    parsed = plan_rows(str(missing))
    assert parsed["findings"][0].startswith("cannot read plan: ")
    assert parsed["rows"] == []
    assert parsed["shape"] is None


def test_a_duplicate_is_one_task_that_stays_visible() -> None:
    """Two rows under one id: both reach the caller, and the shape counts one.

    The reading a duplicate must not get is a silent merge — a caller handed
    one row would seat one pane and never learn a second attempt was described.
    So both rows come back, in the file's order, while `shape` measures the one
    Task they are. Which of the two rows the shape checks then read is not
    asserted: nothing in this output distinguishes them, and the finding above
    is what a caller acts on.
    """
    dupe = parsed("plan-dupe.md")
    assert [r["task"] for r in dupe["rows"]] == ["T-01", "T-01"]
    assert [r["files"] for r in dupe["rows"]] == [
        ["ai/herdr/team.sh"],
        ["lib/common.sh"],
    ]
    assert dupe["shape"]["tasks"] == 1


def test_rows_and_sections_agree() -> None:
    ok = parsed("plan-ok.md")
    assert [r["task"] for r in ok["rows"]] == ["T-01", "T-02"]
    assert ok["sections"] == ["T-01", "T-02"]


def test_orphan_section_is_not_a_row_id() -> None:
    """A section with no row is prose the reader names but never lists."""
    assert parsed("plan-orphan.md")["sections"] == ["T-01", "T-02"]


# --- the shape ---------------------------------------------------------------
# Depth, width and task count, which no row can state about the document.
@pytest.mark.parametrize(
    ("name", "depth", "width", "tasks"),
    [
        ("plan-ok.md", 2, 1, 2),
        ("plan-deep.md", 5, 1, 5),
        ("plan-wide.md", 1, 5, 5),
        ("plan-thin.md", 2, 3, 4),
        ("plan-no-section.md", 1, 2, 2),
    ],
)
def test_shape(name: str, depth: int, width: int, tasks: int) -> None:
    shape = parsed(name)["shape"]
    assert (shape["depth"], shape["width"], shape["tasks"]) == (depth, width, tasks)


def test_shape_is_none_until_the_rows_parse() -> None:
    """A plan whose block does not read has no shape to measure."""
    assert parsed("plan-bad-json.md")["shape"] is None
    assert parsed("plan-no-block.md")["shape"] is None


def test_depth_names_the_chain_it_measured() -> None:
    chain = parsed("plan-deep.md")["shape"]["chain"]
    assert chain == ["T-01", "T-02", "T-03", "T-04", "T-05"]
    assert (
        "depth 5 is over the 4 a plan should stay under" in warnings("plan-deep.md")[0]
    )
    assert (
        "Longest chain: T-01 -> T-02 -> T-03 -> T-04 -> T-05"
        in warnings("plan-deep.md")[0]
    )


def test_width_warning_fires_on_a_chain_not_on_one_task() -> None:
    """One Task cannot be narrow; `plan-dangling` is one and draws nothing."""
    assert any("width 1 on 5 Tasks" in w for w in warnings("plan-deep.md"))
    assert not any("width" in w for w in warnings("plan-dangling.md"))


def test_granularity_warnings() -> None:
    thin = warnings("plan-thin.md")
    assert any(
        "T-01 is 1 non-blank line and shares ai/herdr/team.sh" in w for w in thin
    )
    assert any("T-03 names ai/herdr/, a directory" in w for w in thin)
    assert any("T-04 names 9 paths, over the 8" in w for w in thin)
    # Once per pair, not once per end: both halves of the chain are thin.
    assert len([w for w in thin if "shares ai/herdr/team.sh" in w]) == 1


def test_granularity_stays_quiet_on_a_wide_plan() -> None:
    """An unblocked row is never a merge candidate, however short its prose."""
    assert warnings("plan-wide.md") == []


def test_tier_warning_names_only_the_row_that_says_nothing() -> None:
    tier = [w for w in warnings("plan-cc-tier.md") if "is cc with a verify" in w]
    assert len(tier) == 1
    assert tier[0].startswith("T-02 is cc with a verify")


def test_warnings_are_never_findings() -> None:
    """A deep plan is sometimes correct: no warning may fail a lint."""
    for name in ("plan-deep.md", "plan-thin.md", "plan-cc-tier.md"):
        assert warnings(name), name
        assert findings(name) == [], name


def test_the_clean_plan_draws_nothing() -> None:
    assert findings("plan-ok.md") == []
    assert warnings("plan-ok.md") == []
    # An empty `verify` is the planner saying no command settles the Task, and
    # a `cc` row with a reason is a row that answered the tier question.
    assert findings("plan-empty-verify.md") == []
    assert findings("plan-no-provider.md") == []
