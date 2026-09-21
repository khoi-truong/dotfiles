"""The one reader of a plan's `## Tasks` block.

`plan lint`, `dispatch --from-plan`, `collect --plan` and `loop` all have to
agree about what a plan says, and two readers that disagreed about a plan would
be a silent unblock. This module is that one reader, so the modules behind each
verb import it instead of each carrying a copy of it.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from herdr_team import config

__all__ = ["plan_rows"]

# What a plan's *shape* is measured against. Every number here is a starting
# guess and the warnings that use them say so: a plan file cannot say how long
# a Task takes, so these are proxies, and a proxy that fails a correct plan is
# a check that stops being run. Depth and width are properties of the document
# no individual row can state; the granularity pair are the two proxies the
# document does carry, and both are what `team.sh report` (T-02) replaces with
# observed numbers — which is why they live here, together, rather than beside
# the checks that read them.
DEPTH_MAX = 4  # the longest chain of `blocks` edges a plan should have
WIDTH_MIN = 2  # Tasks a plan should be able to run at once ...
WIDTH_MIN_TASKS = 3  # ... once it has this many Tasks to run at all
THIN_LINES = 8  # non-blank lines a chained row needs to earn its Dispatch
FAT_FILES = 8  # paths a row may name before its verify stops localizing ...
# ... which is the shipped value of `limits.plan_max_paths`, and no longer the
# last word on it: `_max_paths` reads the setting, so a machine that would
# rather trade a wider row for a coarser retry gets that from team.toml.

# The checkout this module is in — five directories up from
# `ai/herdr/lib/herdr_team/plan.py`, which is `config.py`'s own
# `_DERIVED_DOTFILES` and `team.sh`'s `_CHECKOUT`. A reader here that asked the
# environment instead would be asking the wrong tree the moment
# `DOTFILES=${HOME}/.dotfiles` (exported by `~/.zshrc`, see team.sh:75-86)
# names a checkout other than the one running — a linked worktree's main
# checkout, or this file imported by a test. Not resolved through symlinks: a
# checkout reached with its `lib/` linked in, as run.sh's fixtures are, is the
# checkout being tested.
_CHECKOUT = Path(__file__).parents[4]


def _max_paths() -> int:
    """`limits.plan_max_paths` from ai/herdr/team.toml, else `FAT_FILES`.

    Read here rather than handed in, because every caller of `plan_rows` —
    `lint`, `dispatch`, `collect`, `loop`, `report` — would otherwise have to
    be given the number, and the one that forgot would disagree with the rest
    about the same plan.

    A configuration that cannot be read falls back to the shipped default
    instead of failing the plan: this is a warning threshold, and a `plan lint`
    that refused to run because `team.local.toml` has a typo would be a plan
    nobody could lint — with the reader's own failure reported by the verbs
    that read the configuration for what it is.
    """
    try:
        value = config.load(dotfiles=_CHECKOUT).get("limits.plan_max_paths")
    except config.ConfigError:
        return FAT_FILES
    return value if isinstance(value, int) and value >= 1 else FAT_FILES


def _cycles(by_id: dict[str, Any]) -> list[list[str]]:
    """Every cycle in `blocks`, as a list of id paths ending where it began."""
    colour: dict[str, int] = {}
    stack: list[str] = []
    found: list[list[str]] = []

    def walk(tid: str) -> None:
        colour[tid] = 1
        stack.append(tid)
        for b in sorted(by_id[tid].get("blocks") or []):
            if b not in by_id:
                continue
            if colour.get(b) == 1:
                found.append(stack[stack.index(b) :] + [b])
            elif colour.get(b) is None:
                walk(b)
        stack.pop()
        colour[tid] = 2

    for tid in sorted(by_id):
        if colour.get(tid) is None:
            walk(tid)
    return found


def _masks_exit(verify: str) -> bool:
    """True when `verify` pipes without `set -o pipefail` leading.

    A pipeline exits with its last stage's status, so `… | tail -1` exits 0
    whatever the check did. An executor observes 0 and claims `evidence:
    verified` on something that cannot fail, which turns the one invariant
    the protocol rests on into a rubber stamp. Narrow, and it will flag a
    deliberate pipeline — the remedy is `set -o pipefail; …`, correct anyway.
    """
    if verify.lstrip().startswith("set -o pipefail"):
        return False
    quote = ""
    for ch in verify:
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "'\"":
            quote = ch
        elif ch == "|":
            return True
    return False


def _section_bodies(text: str) -> dict[str, str]:
    """The prose under each `### T-nn`, keyed by Task id.

    Bounded at the next heading of any level rather than at the next `###`:
    the `## ` a document may carry after the tasks block ends the sections,
    and a body that ran on into it would make every row look long enough to
    be worth a Dispatch of its own.

    One reader for both jobs that need a section — the row/section agreement
    check compares the ids, the thin-row proxy counts the lines — because two
    readers of one heading is how they come to disagree about whether it is
    there at all.
    """
    out: dict[str, str] = {}
    heads = list(re.finditer(r"^(#{1,6})[ \t]+(.*)$", text, re.M))
    for i, head in enumerate(heads):
        if head.group(1) != "###":
            continue
        words = head.group(2).split()
        # The slice runs to the next heading of any level, so a section with
        # nothing under it reads as the empty string rather than as the next
        # section's prose: the thin-row count is then zero, which is what a
        # Task stating its work elsewhere actually costs.
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        if words and re.match(r"^T-\d{2}$", words[0]):
            out[words[0]] = text[head.end() : end]
    return out


def _levels(by_id: dict[str, Any]) -> dict[str, int]:
    """The longest chain of `blocks` edges ending at each Task, as a length.

    The walk `_cycles` already makes, asking a different question of the same
    graph. Cycle-safe: a back edge is a finding of its own, and following it
    here would be a recursion that never returns rather than a second report
    of one defect. A row this code has no entry for is not an edge — `blocks`
    naming a row that does not exist is a finding too.
    """
    level: dict[str, int] = {}

    def walk(tid: str, path: frozenset[str]) -> int:
        if tid in level:
            return level[tid]
        path = path | {tid}
        best = 0
        for b in by_id[tid].get("blocks") or []:
            if b in by_id and b not in path:
                best = max(best, walk(b, path))
        level[tid] = best + 1
        return level[tid]

    for tid in sorted(by_id):
        walk(tid, frozenset())
    return level


def _chain(by_id: dict[str, Any], level: dict[str, int]) -> list[str]:
    """One longest chain of `blocks` edges, first Task to last.

    Reconstructed by stepping back from the deepest Task to a blocker one
    level shallower, lowest id first at each step, so a plan with two equally
    long chains names the same one every run: a warning that named a different
    chain each time would read as two different problems.
    """
    if not level:
        return []
    cur = sorted(level, key=lambda t: (-level[t], t))[0]
    chain = [cur]
    while True:
        step = sorted(
            b
            for b in (by_id[cur].get("blocks") or [])
            if b in level and level[b] == level[cur] - 1
        )
        if not step:
            return list(reversed(chain))
        cur = step[0]
        chain.append(cur)


def _chained_twin(by_id: dict[str, Any], tid: str, path: str) -> str | None:
    """A row at the other end of a `blocks` edge that names the same path.

    Either direction is the same defect: a row queued behind another on one
    file, and a row the other waits on, are two Dispatches doing one task's
    work. The clause is what keeps the thin warning honest — a small
    independent Task is fine, and only the chained one is worth merging.
    """
    for other in sorted(by_id):
        if other == tid or path not in (by_id[other].get("files") or []):
            continue
        if other in (by_id[tid].get("blocks") or []) or tid in (
            by_id[other].get("blocks") or []
        ):
            return other
    return None


def _granularity(by_id: dict[str, Any], bodies: dict[str, str]) -> list[str]:
    """Warnings for rows unlikely to be worth a Dispatch of their own.

    A Dispatch has fixed overhead — a prompt, a handoff, a wave of the
    orchestrator loop, and a worktree when the pool has to grow — so a Task
    too small to cover it costs more than it returns, and a Task too broad to
    have its failure localized costs a whole retry. Nothing here can measure
    either, so both are proxies, and the text names the number as a guess
    because a threshold nobody knows is a guess reads as a measurement.

    A trailing slash is the only way a plan file says "tree" rather than
    "file", so that is what the directory check reads: asking the filesystem
    would make the answer depend on what is checked out beside the plan.
    """
    out: list[str] = []
    pairs: set[frozenset[str]] = set()
    fat = _max_paths()
    for tid in sorted(by_id):
        body = bodies.get(tid)
        # A row with no section is a finding of its own, and a proxy measured
        # against a body that is not there would be a second report of it.
        if body is None:
            continue
        files = [f for f in (by_id[tid].get("files") or []) if isinstance(f, str) and f]
        dirs = [f for f in files if f.endswith("/")]
        if dirs:
            out.append(
                "%s names %s, a directory — no verify can localize a "
                "failure inside one, so a retry re-does all of it" % (tid, dirs[0])
            )
        elif len(files) > fat:
            out.append(
                "%s names %d paths, over the %d a verify can localize a "
                "failure in — a retry would re-do all of them (%d is a "
                "starting guess, not a measurement)" % (tid, len(files), fat, fat)
            )
        lines = len([ln for ln in body.splitlines() if ln.strip()])
        if len(files) != 1 or lines >= THIN_LINES:
            continue
        twin = _chained_twin(by_id, tid, files[0])
        # Once per pair: both ends of a chain are thin by the same measure,
        # and naming the same merge twice reads as two problems.
        if twin and frozenset((tid, twin)) not in pairs:
            pairs.add(frozenset((tid, twin)))
            sized = "%d non-blank line%s" % (lines, "" if lines == 1 else "s")
            out.append(
                "%s is %s and shares %s with %s, which it is chained "
                "to — two Dispatches doing one task's work; merge them "
                "(%d non-blank lines is a starting guess, not a "
                "measurement)" % (tid, sized, files[0], twin, THIN_LINES)
            )
    return out


def _needs_reason(cfg: config.Config, provider: str) -> bool:
    """Whether a profile's tier is one a row has to account for.

    `requires_reason` is the profile's own word for that (and `config lint`
    refuses a premium profile without it), so a second profile whose tier has to
    be justified is a line of `team.toml` rather than a second name compared
    here. Read from the profile's body rather than through `config.profile()`:
    the question is what the *row* is claiming, and a profile this machine
    cannot launch right now is still a claim a plan should state a reason for.
    """
    return cfg.get("profile.%s.requires_reason" % provider) is True


def _tiers(by_id: dict[str, Any]) -> list[str]:
    """Rows claiming a tier that needs a reason, with nothing saying why.

    The test is verifiability: a row whose `verify` command can catch a wrong
    answer is a `ccd` row, and a profile that costs what `cc` costs is for the
    work no command settles — the row shapes later work, it is a spec, or it is
    a review (cost.md). So a row on such a profile that has a `verify` reads one
    of two ways, and both want the same thing written down: a row that is really
    `ccd` and is mislabelled, or a row that is really `cc` for a reason the plan
    has not stated. `tier_reason` is where that reason goes — and `spawn
    --provider cc` refuses without one, so a plan that omits it is a plan whose
    Dispatches are refused, or worse, quietly run on the wrong credential.

    A warning and never a finding, because the second reading is legitimate:
    a review row has a `verify` (it runs the suite) and is still `cc`. No
    parser can tell the two apart, so refusing would refuse correct plans —
    which is how a check stops being read.

    A configuration that cannot be read draws one warning about the check it
    stopped making, and not silence: no row can be measured against a profile
    nobody can read, and a plan that reads clean because the checker fell over
    is exactly the plan an author stops looking at. It still does not refuse to
    run — the reader's own failure is the verbs' to report, and a `plan lint`
    that stopped because `team.local.toml` has a typo would be a plan nobody
    could lint — so the failure is named once, for the whole plan.
    """
    why = ""
    try:
        cfg: config.Config | None = config.load(dotfiles=_CHECKOUT)
    except config.ConfigError as exc:
        cfg = None
        why = str(exc)
    out: list[str] = []
    if cfg is None:
        out.append(
            "no tier_reason check — the configuration does not resolve (%s), so "
            "no row can be measured against a profile and a premium row missing "
            "its reason passes here to be refused by spawn: fix that file and "
            "lint again" % why
        )
    for tid in sorted(by_id):
        row = by_id[tid]
        provider = str(row.get("provider") or "")
        # Read once for the plan rather than once per row, and asked of the
        # profile's own word rather than of a name: a `ccd` row draws nothing
        # because `ccd` does not require a reason, and a second profile that
        # does draws the same warning without a line here.
        if cfg is None or not provider or not _needs_reason(cfg, provider):
            continue
        if not (row.get("verify") or "").strip():
            continue
        if str(row.get("tier_reason") or "").strip():
            continue
        out.append(
            "%s is cc with a verify — a command settles this row, so it is a "
            "ccd row unless it shapes later work, is a spec, or is a review; "
            'say which with a "tier_reason" string, or run it on ccd '
            "(cost.md)" % tid
        )
    return out


def _shape(by_id: dict[str, Any], bodies: dict[str, str]) -> dict[str, Any]:
    """A plan's depth, width and task count, and what they earn in warnings.

    Depth is the longest chain of `blocks` edges, which is the number of
    Dispatches a Run has to take one at a time; width is the most Tasks any
    one level holds, which is the most it can ever have out at once. The
    second is why the executor cap is not the limit on a plan: nothing here
    branches, so a second executor cannot be used however many are idle.
    """
    level = _levels(by_id)
    counts: dict[int, int] = {}
    for lv in level.values():
        counts[lv] = counts.get(lv, 0) + 1
    depth = max(level.values()) if level else 0
    width = max(counts.values()) if counts else 0
    tasks = len(level)
    chain = _chain(by_id, level)

    warnings: list[str] = []
    if depth > DEPTH_MAX:
        warnings.append(
            "depth %d is over the %d a plan should stay under — shape the work "
            "wide, not deep: depth is where these systems fail (protocol.md). "
            "Longest chain: %s" % (depth, DEPTH_MAX, " -> ".join(chain))
        )
    if tasks >= WIDTH_MIN_TASKS and width < WIDTH_MIN:
        warnings.append(
            "width %d on %d Tasks — no two of them can run at once, so a "
            "second executor cannot help this plan whatever the cap says "
            "(%d is the width to shape for)" % (width, tasks, WIDTH_MIN)
        )
    warnings.extend(_granularity(by_id, bodies))
    warnings.extend(_tiers(by_id))
    return {
        "depth": depth,
        "width": width,
        "tasks": tasks,
        "chain": chain,
        "warnings": warnings,
    }


def plan_rows(plan: str) -> dict[str, Any]:
    """Read a plan's `## Tasks` block.

    Returns {"rows", "sections", "findings", "shape"} and raises nothing: the
    caller decides whether to stop at the first finding (dispatch) or report
    them all (plan lint). `findings` are human-readable and carry no prefix, so
    a caller can name itself.

    `shape` is None until the rows parse, and then the plan's own measurements
    with the warnings they earn — a property of the whole document that no row
    can state, which is why it is computed here rather than by each caller.
    Warnings are not findings and no caller may fail on one: a deep plan is
    sometimes correct, and a linter that refuses correct plans stops being run.
    """
    out: dict[str, Any] = {"rows": [], "sections": [], "findings": [], "shape": None}
    say = out["findings"].append
    try:
        text = open(plan, encoding="utf-8").read()
    except OSError as e:
        say("cannot read plan: %s" % e)
        return out

    m = re.search(r"^## Tasks\s*\n+```json\n(.*?)\n```", text, re.S | re.M)
    if not m:
        say("%s has no '## Tasks' json block" % plan)
        return out
    try:
        rows = json.loads(m.group(1))
    except ValueError as e:
        say("task block is not valid JSON: %s" % e)
        return out
    if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
        say("%s: the task block must be a list of objects" % plan)
        return out

    out["rows"] = rows
    bodies = _section_bodies(text)
    out["sections"] = sorted(bodies)
    sections = set(out["sections"])

    by_id: dict[str, Any] = {}
    for r in rows:
        missing = [k for k in ("task", "files", "verify", "blocks") if k not in r]
        if missing:
            say(
                "row %s is missing %s" % (r.get("task", "(unnamed)"), " ".join(missing))
            )
        if r.get("task"):
            # Two rows under one id are two Dispatches at one Task in one wave:
            # `collect --plan` emits a `ready` line per row, so the loop seats
            # both and two panes take the same section on two branches. Caught
            # here so every reader refuses it, rather than in the one that
            # happened to notice.
            if r["task"] in by_id:
                say("%s has two rows for %s: one Task, one row" % (plan, r["task"]))
            by_id[r["task"]] = r

    # A row and its prose section must agree, in both directions: a row with no
    # section dispatches an executor to read nothing, and a section with no row
    # is work nobody will ever be sent to do.
    for tid in sorted(by_id):
        if tid not in sections:
            say("%s has a row for %s but no '### %s' section" % (plan, tid, tid))
    orphans = sorted(sections - set(by_id))
    if orphans:
        say("%s has sections with no row: %s" % (plan, " ".join(orphans)))

    for tid in sorted(by_id):
        dangling = sorted(b for b in (by_id[tid].get("blocks") or []) if b not in by_id)
        if dangling:
            say("%s blocks on %s, which has no row" % (tid, " ".join(dangling)))

    for cycle in _cycles(by_id):
        say("blocks has a cycle: %s" % " -> ".join(cycle))

    for tid in sorted(by_id):
        if _masks_exit(by_id[tid].get("verify") or ""):
            say(
                "%s: verify pipes without a leading 'set -o pipefail', so its "
                "exit code is the last stage's and the check cannot fail" % tid
            )

    out["shape"] = _shape(by_id, bodies)

    return out
