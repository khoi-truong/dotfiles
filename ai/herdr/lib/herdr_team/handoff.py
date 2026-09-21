"""The one reader of a handoff's frontmatter.

`collect`, `collect --plan`, `wait`, `surface` and the dispatch gate all have to
agree about what a handoff says, and two readers that disagreed would read one
Run as `done` in one table and `UNVERIFIED` in the other. This module is that
one reader, so `team.sh`'s `python3 -` blocks import it instead of each carrying
a copy of it.
"""

from __future__ import annotations

import json
import os
from typing import Any

# One handoff's frontmatter: key -> value, both strings. A value that arrived
# as a block list carries its newlines; see `handoff_meta`.
Meta = dict[str, str]

__all__ = [
    "abandoned",
    "artifacts",
    "command_entries",
    "dispatched",
    "handoff_meta",
    "journal_lines",
    "journal_malformed",
    "journal_row",
    "path_list",
    "same_cmd",
    "unproven",
    "yaml_block",
]


def handoff_meta(path: str) -> Meta | None:
    """One handoff's frontmatter, or None when it has none.

    A field's value is everything under its key, not just the rest of the key's
    own line: the frontmatter is a YAML document, and the shape its own style
    invites for a list is a block list — `commands:`, then `- cmd: "…"` under
    it, then `exit: 0` under that — which arrives as three lines and is one
    value. Joining them here, at the one reader every caller goes through, is
    what keeps `commands:` from reaching a caller as nothing at all.
    """
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    meta: Meta = {}
    key: str | None = None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.strip():
            continue
        # Indented under the key, or a sequence entry at its own column: YAML
        # allows the second, and a frontmatter key here never starts with `-`.
        # The indentation is kept, not stripped: it is what says which item of
        # a block list a line belongs to.
        if key is not None and (line[:1] in " \t" or line.lstrip().startswith("-")):
            meta[key] = meta[key] + "\n" + line.rstrip()
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            key = k.strip()
            meta[key] = v.strip()
    return meta


def yaml_block(raw: str) -> list[list[str]] | None:
    """A block list's items, each item its own chunk of lines, or None.

    `- ` opens an item and a line indented under it belongs to that item, so
    `- cmd: …` with `exit: …` beneath it is one item of two lines. None when
    the text opens no item, or holds a line that is neither an item nor part of
    one: a caller's way of telling "an empty list" from "a shape I cannot
    read", which are UNVERIFIED and UNPARSED respectively.
    """
    items: list[list[str]] = []
    cur: list[str] | None = None
    for line in raw.splitlines():
        if not line.strip():
            continue
        s = line.strip()
        if s.startswith("- "):
            cur = [s[2:].strip()]
            items.append(cur)
        elif s == "-":
            cur = [""]
            items.append(cur)
        elif cur is not None and line[:1] in " \t":
            cur.append(s)
        else:
            return None
    if not items or not any(item[0] for item in items):
        return None
    return items


def path_list(raw: str | None) -> list[str]:
    """The paths in a `files_changed:` or `artifacts:` value, in order.

    Two shapes, and the one a handoff carries without being taught is the YAML
    block list: the frontmatter is a YAML document, and a list in it is written
    that way. The comma-separated line the contract block shows is the other.

    Split by hand rather than by json: the value reaches the file through an
    agent, so quoted and bare paths both have to read, and a field nobody can
    parse costs a printed path rather than a whole Run — `collect` must not
    fail over a receipt. Absent is [], which is what the contract says an
    omitted field means.
    """
    raw = (raw or "").strip()
    if not raw:
        return []
    if raw.lstrip().startswith("-"):
        items = yaml_block(raw)
        if items is not None:
            return [
                item[0].strip().strip('"').strip("'")
                for item in items
                if item[0].strip()
            ]
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    return [p.strip().strip('"').strip("'") for p in raw.split(",") if p.strip()]


def artifacts(meta: Meta) -> list[str]:
    """The paths under `artifacts:`, in the order the handoff lists them.

    A receipt, not a copy: these name documents a workflow of the agent's own
    wrote — `/research`, `/plan` — and nothing here opens one. `run gc` will
    eventually need the list as an exclusion set; every reader until then only
    prints it.
    """
    return path_list(meta.get("artifacts"))


def command_entries(raw: str) -> list[Any] | None:
    """The `commands:` entries, or None for a shape this file cannot read.

    Two shapes, the same data: the inline JSON the contract block shows, and
    the YAML block list the frontmatter's own style invites. Accepting the
    second does not weaken the first — an entry still needs `cmd` and `exit`,
    an entry that is not a mapping is skipped the way a non-dict JSON entry
    already was, and a value that is neither shape still reads UNPARSED.
    """
    text = raw.strip()
    if text.startswith("[") or text.startswith("{"):
        try:
            parsed = json.loads(text)
        except ValueError:
            return None
        return parsed if isinstance(parsed, list) else []
    items = yaml_block(raw)
    if items is None:
        return None
    entries: list[Any] = []
    for item in items:
        head = item[0].strip()
        # One layer of YAML quoting off the item first: an agent may wrap the
        # object it writes, and which it chose says nothing about what it
        # meant. Whether an item is quoted is not evidence about the Run.
        for q in ('"', "'"):
            if len(head) >= 2 and head.startswith(q) and head.endswith(q):
                head = head[1:-1].strip()
                break
        if head.startswith("{"):
            # The other block spelling: the list is YAML and each item is the
            # whole inline object the contract block shows. Two agents fixed
            # this field independently and each accepted the shape it had seen
            # — one mapping per item, or one object per item — so the reader
            # takes both. A continuation line under an object is neither shape.
            if len(item) > 1:
                return None
            try:
                entry = json.loads(head)
            except ValueError:
                return None
            if isinstance(entry, dict):
                entries.append(entry)
            continue
        mapping: dict[str, Any] = {}
        for line in item:
            if ":" not in line:
                return None
            k, v = line.split(":", 1)
            k, v = k.strip(), v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
                v = v[1:-1]
            # A separate name for the converted value, because `mapping` holds
            # both: `exit` is an int where every other key is the string it
            # arrived as, which is what `unproven` compares against 0.
            value: Any = v
            if k == "exit":
                try:
                    value = int(v)
                except ValueError:
                    pass
            mapping[k] = value
        if not mapping:
            return None
        entries.append(mapping)
    return entries


def same_cmd(verify: str, cmd: str) -> bool:
    """True when `cmd` is the verify the plan named, as an agent ran it.

    Substring, not equality, because the command reaches the handoff through an
    agent: a `cd`, a quote or a `set -o pipefail;` prefix around it is still the
    same command. Word by word as a second pass, because one argument may be
    spelled from the root where the plan spelled it relative — which is exactly
    what the first handoff written against this contract did, the plan's path
    being `.omc/plans/…` in the plan and absolute in the pane, since `.omc/` is
    not in the worktree the agent was working in. Both spellings run the same
    check, so both prove it. A token only extends the verify's token; a
    different path does not match.

    Loose on purpose — a false positive here must not be able to wedge a Run
    (see the header) — and the exit code is required alongside the command,
    never instead of it.
    """
    if verify in cmd:
        return True
    want, got = verify.split(), cmd.split()
    for start in range(len(got) - len(want) + 1):
        if all(
            g == w or g.endswith(w)
            for w, g in zip(want, got[start : start + len(want)])
        ):
            return True
    return False


def journal_row(line: str) -> tuple[str, str, str | None] | None:
    """(task, dispatch, agent) for a journal line this code can read.

    Three columns is the shape written before `wait` needed a pane to block
    on: it yields agent None, so a journal from before that change keeps
    counting as `running` and is merely un-waitable. Four is the current
    shape. Anything else is None — `dispatched` skips it so one bad line
    cannot hide a whole Run, and `wait` refuses on it instead.
    """
    parts = line.split("\t")
    if len(parts) == 3:
        return parts[1], parts[2], None
    if len(parts) == 4:
        return parts[1], parts[2], parts[3].strip() or None
    return None


def journal_lines(handoffs: str, run: str) -> list[tuple[str, str, str | None]]:
    """Every readable journal line under `run`, as (task, dispatch, agent).

    In file order, retries included: `dispatched` folds these down to the
    highest Dispatch id per Task, and `report` counts them, so a Run's Dispatch
    count and its winning Dispatch come off one list rather than off two
    readers that could disagree about the file.

    No directory at all is no journal, and never the one in the caller's
    working directory: `surface` asks this with no Run and must not read a
    `.dispatched` it happens to be standing next to.
    """
    rows: list[tuple[str, str, str | None]] = []
    if not handoffs:
        return rows
    try:
        text = open(os.path.join(handoffs, ".dispatched"), encoding="utf-8").read()
    except OSError:
        return rows
    for line in text.splitlines():
        if not line.strip() or line.split("\t")[0] != run:
            continue
        row = journal_row(line)
        if row is not None:
            rows.append(row)
    return rows


def abandoned(handoffs: str, run: str) -> set[tuple[str, str]]:
    """The (task, dispatch) pairs a `teardown` gave up on, as a set.

    One line per outstanding Dispatch of the pane being destroyed, in the
    journal's own shape, because destroying the pane is exactly what makes the
    Dispatch unanswerable: the journal line stays — the Dispatch did happen —
    and the handoff is no longer coming. `teardown` is the only writer.

    Read here and consumed in `dispatched`, so the two verbs that ask what is
    outstanding inherit it rather than each learning it separately: without
    this, `wait` blocks on a pane herdr no longer knows and dies naming an
    agent nobody can resolve, and `collect --plan` reads the Task as `running`
    for as long as anyone cares to look at a Run that is over.
    """
    pairs: set[tuple[str, str]] = set()
    if not handoffs:
        return pairs
    try:
        text = open(os.path.join(handoffs, ".abandoned"), encoding="utf-8").read()
    except OSError:
        return pairs
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or parts[0] != run:
            continue
        pairs.add((parts[1], parts[2]))
    return pairs


def dispatched(handoffs: str, run: str) -> dict[str, dict[str, str | None]]:
    """The highest Dispatch id sent per Task under `run`, with its agent.

    A Task with a record here and no handoff for it is still out with an
    agent. Nothing else on disk distinguishes that from never dispatched —
    except an abandonment, which is the same absence with the wait removed.
    """
    sent: dict[str, dict[str, str | None]] = {}
    gone = abandoned(handoffs, run)
    for task, dispatch, agent in journal_lines(handoffs, run):
        if (task, dispatch) in gone:
            continue
        # No record, or a higher id than the one recorded, is what displaces a
        # row — and a line whose dispatch column is empty displaces neither,
        # because `"" > ""` is false and it names no Dispatch at all. Recording
        # it would put a Task in the table that no `wait` can resolve: the
        # handoff it blocked on would be `T-01-.md`.
        rec = sent.get(task)
        if dispatch > ((rec or {}).get("dispatch") or ""):
            sent[task] = {"dispatch": dispatch, "agent": agent}
    return sent


def journal_malformed(handoffs: str, run: str) -> list[tuple[int, str]]:
    """Journal lines under `run` that are neither three nor four columns.

    A line this code cannot read is a Dispatch it cannot wait for, so `wait`
    names them rather than blocking on the rest: silently waiting for a
    subset is how an orchestrator loop stalls with work outstanding.
    """
    bad: list[tuple[int, str]] = []
    path = os.path.join(handoffs, ".dispatched")
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return bad
    for n, line in enumerate(text.splitlines(), 1):
        if line.strip() and line.split("\t")[0] == run and journal_row(line) is None:
            bad.append((n, line))
    return bad


def unproven(meta: Meta, verify: str) -> str | None:
    """The cause to report instead of `done`, or None when the handoff proves it.

    A handoff's `commands:` is one object per command the agent ran, in either
    of the shapes the dispatch prompt's contract block now states. `done` needs
    the row's own `verify` to be one of those commands at exit 0, or the handoff
    is claiming a check nobody can see; `settled_state` says so rather than
    showing `done`.

    An empty `verify` is the planner saying no command settles this Task. There
    is nothing to check, so `done` stands.

    Lives here rather than beside `settled_state`, its first caller, because
    `report` proves the same claim for its own table: two copies of this rule
    would eventually show one Run as `done` in one table and `UNVERIFIED` in
    the other, which is the failure handoff_py exists to make impossible.
    """
    if not verify:
        return None
    raw = meta.get("commands")
    if raw is None or not raw.strip():
        # No commands recorded: absent, or present with nothing under it. That
        # is absence, not a shape nobody can read, so it reads UNVERIFIED
        # rather than UNPARSED — and absence is never evidence.
        return "UNVERIFIED"
    entries = command_entries(raw)
    if entries is None:
        # Neither shape. A human has to be able to tell a shape they cannot
        # read from a claim that does not hold.
        return "UNPARSED"
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if same_cmd(verify, str(entry.get("cmd", ""))) and entry.get("exit") == 0:
            return None
    return "UNVERIFIED"
