"""Unit tests for `herdr_team.handoff`, the one reader of a handoff's frontmatter.

Every verb that reads a receipt reads it through this module — `collect`,
`collect --plan`, `report`, `wait`, `surface` and the dispatch gate — so a
mistake here shows up as a Run that is `done` in one table and `UNVERIFIED` in
another, which is exactly what the module exists to prevent. `run.sh` drives
those verbs end to end; this file asks the reader directly, one field at a time.

The frontmatter is written by an agent, not by this code, so most of what is
below is about shapes: a list as a block or as a comma-separated line, an exit
code as an int or as the string of one, a command spelled from the root where
the plan spelled it relative. Where a shape cannot be read the answer has to be
`UNPARSED` rather than `UNVERIFIED`, because a human has to be able to tell a
claim that does not hold from one this code cannot see.
"""

from __future__ import annotations

import json
from pathlib import Path

from herdr_team.handoff import (
    Meta,
    abandoned,
    artifacts,
    command_entries,
    dispatched,
    handoff_meta,
    journal_lines,
    journal_malformed,
    journal_row,
    path_list,
    same_cmd,
    unproven,
    yaml_block,
)

VERIFY = "bash scripts/ci/lint-local.sh"


def write(tmp_path: Path, name: str, text: str) -> str:
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return str(path)


def handoff(commands: str, files: str = "ai/herdr/team.sh") -> str:
    """A handoff whose only interesting field is `commands:`."""
    return (
        "---\nrun: R-1\ntask: T-01\nevidence: verified\nfiles_changed: %s\ncommands:%s\n---\n\nbody\n"
        % (
            files,
            commands,
        )
    )


def meta_of(commands: str) -> Meta:
    return {"run": "R-1", "task": "T-01", "evidence": "verified", "commands": commands}


# --- frontmatter -------------------------------------------------------------
def test_frontmatter_keys_and_values(tmp_path: Path) -> None:
    meta = handoff_meta(write(tmp_path, "a.md", handoff('\n  - cmd: "x"\n    exit: 0')))
    assert meta is not None
    assert (meta["run"], meta["task"], meta["evidence"]) == ("R-1", "T-01", "verified")


def test_frontmatter_is_none_without_one(tmp_path: Path) -> None:
    """`wait` and the dispatch gate refuse a handoff that is not one."""
    path = write(tmp_path, "a.md", "# just prose\n")
    assert handoff_meta(path) is None


def test_a_block_list_is_one_value_not_three_lines(tmp_path: Path) -> None:
    """The joining every caller depends on: a list keyed under itself."""
    meta = handoff_meta(
        write(tmp_path, "a.md", handoff('\n  - cmd: "%s"\n    exit: 0' % VERIFY))
    )
    assert meta is not None
    assert "- cmd:" in meta["commands"]
    assert "exit: 0" in meta["commands"]


def test_a_bare_sequence_at_its_own_column(tmp_path: Path) -> None:
    """YAML lets a sequence sit at column zero; a key never starts with `-`."""
    meta = handoff_meta(write(tmp_path, "a.md", handoff("\n- cmd: x\n  exit: 0")))
    assert meta is not None
    assert meta["commands"].lstrip().startswith("- cmd: x")


# --- path lists --------------------------------------------------------------
def test_path_list_shapes() -> None:
    assert path_list(None) == []
    assert path_list("") == []
    assert path_list("a, b") == ["a", "b"]
    assert path_list("[a, b]") == ["a", "b"]
    assert path_list('"a/b", c') == ["a/b", "c"]
    assert path_list('- "a"\n- b') == ["a", "b"]
    assert path_list("\n  - a\n  - b\n") == ["a", "b"]


def test_artifacts_reads_the_field_and_defaults_to_empty() -> None:
    assert artifacts(meta_of("")) == []
    assert artifacts({"artifacts": "- /research/x.md\n- /plan/y.md"}) == [
        "/research/x.md",
        "/plan/y.md",
    ]


def test_yaml_block_refuses_a_shape_it_cannot_read() -> None:
    """None and "" are different answers: UNPARSED and UNVERIFIED."""
    assert yaml_block("") is None
    assert yaml_block("exit: 0") is None
    assert yaml_block("- cmd: x\nnot indented") is None
    assert yaml_block("- cmd: x\n  exit: 0") == [["cmd: x", "exit: 0"]]


# --- commands ----------------------------------------------------------------
def test_command_entries_inline_json() -> None:
    raw = json.dumps([{"cmd": VERIFY, "exit": 0}])
    assert command_entries(raw) == [{"cmd": VERIFY, "exit": 0}]


def test_command_entries_mapping_per_item() -> None:
    raw = '\n  - cmd: "%s"\n    exit: 0' % VERIFY
    assert command_entries(raw) == [{"cmd": VERIFY, "exit": 0}]


def test_command_entries_object_per_item() -> None:
    """Two agents fixed this field independently, one shape each."""
    raw = '\n  - {"cmd": "%s", "exit": 0}' % VERIFY
    assert command_entries(raw) == [{"cmd": VERIFY, "exit": 0}]


def test_command_entries_quoted_object() -> None:
    raw = '\n  - \'{"cmd": "%s", "exit": 0}\'' % VERIFY
    assert command_entries(raw) == [{"cmd": VERIFY, "exit": 0}]


def test_command_entries_unreadable_shapes_are_none() -> None:
    assert command_entries("not a list") is None
    assert command_entries('[{"cmd": ') is None
    assert command_entries('\n  - {"cmd": "x"}\n    exit: 0') is None  # neither shape
    assert command_entries("\n  - [1, 2]") is None  # an item that is not a mapping


def test_an_entry_that_is_not_a_mapping_proves_nothing() -> None:
    assert unproven(meta_of("[1, 2]"), VERIFY) == "UNVERIFIED"


def test_an_entry_with_no_exit_reads_as_no_entry() -> None:
    """A command the handoff did not say the outcome of proves nothing."""
    assert command_entries("\n  - cmd: x") == [{"cmd": "x"}]
    assert unproven(meta_of("\n  - cmd: x"), "x") == "UNVERIFIED"


# --- whether a handoff proves its verify -------------------------------------
def test_unproven_accepts_a_matching_command_at_zero() -> None:
    meta = meta_of('- cmd: "%s"\n  exit: 0' % VERIFY)
    assert unproven(meta, VERIFY) is None


def test_unproven_rejects_a_nonzero_exit() -> None:
    """The whole point of the check: `verified` needs the exit code, not the text."""
    meta = meta_of('- cmd: "%s"\n  exit: 1' % VERIFY)
    assert unproven(meta, VERIFY) == "UNVERIFIED"


def test_unproven_rejects_a_command_that_is_not_the_verify() -> None:
    meta = meta_of('- cmd: "bash ai/herdr/tests/run.sh"\n  exit: 0')
    assert unproven(meta, VERIFY) == "UNVERIFIED"


def test_unproven_reads_absence_as_unverified_not_unparsed() -> None:
    assert unproven({}, VERIFY) == "UNVERIFIED"
    assert unproven(meta_of(""), VERIFY) == "UNVERIFIED"
    assert unproven(meta_of("\n  "), VERIFY) == "UNVERIFIED"


def test_unproven_reads_an_unreadable_shape_as_unparsed() -> None:
    assert unproven(meta_of("not a list"), VERIFY) == "UNPARSED"


def test_an_empty_verify_needs_no_command() -> None:
    """`verify: ""` is the planner saying no command settles this Task."""
    assert unproven({}, "") is None
    assert unproven(meta_of("garbage"), "") is None


def test_unproven_skips_entries_that_are_not_mappings() -> None:
    meta = meta_of('[1, {"cmd": "%s", "exit": 0}]' % VERIFY)
    assert unproven(meta, VERIFY) is None


def test_unproven_through_a_written_handoff(tmp_path: Path) -> None:
    """The integration the verbs use: file on disk in, verdict out."""
    path = write(tmp_path, "a.md", handoff('\n  - cmd: "%s"\n    exit: 0' % VERIFY))
    meta = handoff_meta(path)
    assert meta is not None
    assert unproven(meta, VERIFY) is None

    failed = write(tmp_path, "b.md", handoff('\n  - cmd: "%s"\n    exit: 1' % VERIFY))
    failed_meta = handoff_meta(failed)
    assert failed_meta is not None
    assert unproven(failed_meta, VERIFY) == "UNVERIFIED"


# --- comparing the plan's command with the agent's ---------------------------
def test_same_cmd_is_loose_about_wrapping() -> None:
    assert same_cmd("bash x", "bash x")
    assert same_cmd("bash x", "cd /tmp && bash x")
    assert same_cmd("bash x", "set -o pipefail; bash x | tail -1")
    assert same_cmd("bash x", "bash x --strict")


def test_same_cmd_accepts_a_token_that_extends_the_verify_token() -> None:
    """A relative path in the plan, spelled from the root by the agent."""
    assert same_cmd("bash run.sh", "bash ./run.sh")


def test_same_cmd_rejects_a_different_command() -> None:
    assert not same_cmd("bash run.sh", "bash lint.sh")
    assert not same_cmd("bash run.sh", "")
    assert not same_cmd("bash run.sh --strict", "bash run.sh")


# --- the journal -------------------------------------------------------------
def test_journal_row_shapes() -> None:
    assert journal_row("R-1\tT-01\tD-01") == ("T-01", "D-01", None)
    assert journal_row("R-1\tT-01\tD-01\tpane-1") == ("T-01", "D-01", "pane-1")
    # A blank fourth column is an unwaitable Dispatch, not an agent named "".
    assert journal_row("R-1\tT-01\tD-01\t") == ("T-01", "D-01", None)
    assert journal_row("R-1\tT-01") is None
    assert journal_row("") is None


def journal(tmp_path: Path, lines: str, name: str = ".dispatched") -> str:
    root = tmp_path / "handoffs"
    root.mkdir(exist_ok=True)
    (root / name).write_text(lines, encoding="utf-8")
    return str(root)


def test_journal_lines_reads_one_run_and_skips_what_it_cannot_read(
    tmp_path: Path,
) -> None:
    root = journal(
        tmp_path,
        "R-1\tT-01\tD-01\tpane-1\n"
        "R-2\tT-09\tD-01\tpane-9\n"
        "\n"
        "R-1\tT-02\tD-01\n"
        "R-1\tT-03\n",
    )
    assert journal_lines(root, "R-1") == [
        ("T-01", "D-01", "pane-1"),
        # Three columns is the shape written before `wait` needed a pane: the
        # Dispatch still happened, it is merely un-waitable.
        ("T-02", "D-01", None),
    ]
    assert journal_lines(root, "R-2") == [("T-09", "D-01", "pane-9")]


def test_no_journal_at_all_is_no_rows(tmp_path: Path) -> None:
    """`surface` asks with no Run and must not read a stray `.dispatched`."""
    assert journal_lines("", "R-1") == []
    assert journal_lines(str(tmp_path), "R-1") == []
    assert abandoned(str(tmp_path), "R-1") == set()
    assert journal_malformed(str(tmp_path), "R-1") == []


def test_dispatched_keeps_the_highest_id_per_task(tmp_path: Path) -> None:
    root = journal(
        tmp_path,
        "R-1\tT-01\tD-01\tpane-1\n"
        "R-1\tT-01\tD-03\tpane-3\n"
        "R-1\tT-01\tD-02\tpane-2\n"
        "R-1\tT-02\tD-01\tpane-4\n",
    )
    assert dispatched(root, "R-1") == {
        "T-01": {"dispatch": "D-03", "agent": "pane-3"},
        "T-02": {"dispatch": "D-01", "agent": "pane-4"},
    }


def test_a_line_with_no_dispatch_id_names_no_dispatch(tmp_path: Path) -> None:
    """An empty dispatch column is not a Dispatch id, so it is not outstanding.

    Four columns with the third blank reads fine as a line — the reader takes
    it — but there is no id in it to wait for. Counting it would put the Task
    in this table and make `wait` block on a handoff named `T-01-.md`, which
    no agent will ever write.
    """
    root = journal(tmp_path, "R-1\tT-01\t\tpane-1\n")
    assert journal_lines(root, "R-1") == [("T-01", "", "pane-1")]
    assert journal_malformed(root, "R-1") == []
    assert dispatched(root, "R-1") == {}


def test_an_abandoned_dispatch_is_not_outstanding(tmp_path: Path) -> None:
    """`teardown` is the only writer: the pane is gone, the answer is not coming."""
    root = journal(
        tmp_path,
        "R-1\tT-01\tD-01\tpane-1\nR-1\tT-02\tD-01\tpane-2\n",
    )
    assert abandoned(root, "R-1") == set()
    (Path(root) / ".abandoned").write_text(
        "R-1\tT-01\tD-01\nR-2\tT-02\tD-01\n", encoding="utf-8"
    )
    assert abandoned(root, "R-1") == {("T-01", "D-01")}
    assert dispatched(root, "R-1") == {"T-02": {"dispatch": "D-01", "agent": "pane-2"}}


def test_journal_malformed_names_the_line_number(tmp_path: Path) -> None:
    root = journal(
        tmp_path, "R-1\tT-01\tD-01\nR-1\tT-02\nR-2\tT-03\nR-1\tT-04\tD-01\tpane-4\n"
    )
    assert journal_malformed(root, "R-1") == [(2, "R-1\tT-02")]
    assert journal_malformed(root, "R-2") == [(3, "R-2\tT-03")]
