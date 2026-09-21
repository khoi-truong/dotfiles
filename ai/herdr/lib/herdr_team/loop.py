"""`team.sh loop` — which pane each `ready` row of the table goes to.

Reads the plan and `collect --plan`'s table and answers one tab-separated line
per dispatchable row: the Task, its lane, the profile to launch and the row's
`tier_reason`. `cmd_loop` in `team.sh` says which rows those are and what it
does with them.

The lane and the profile are both the route table's answer (`config route`):
the lane is the matched role's prefix, and the profile is the row's own
`provider` when the config knows that name, the route's when it states one, and
otherwise the first profile the role can launch — which is what makes `ccd` the
answer for a row that names nothing, rather than a default written here. A
`team.toml` that routes a kind of row to another role, or renames the profile
that role launches, needs no line of this file to change.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from herdr_team import config
from herdr_team.plan import plan_rows

__all__ = ["lane_for", "routes", "main"]

# The checkout this module is in — five directories up from
# `ai/herdr/lib/herdr_team/loop.py` — which is `config.py`'s own
# `_DERIVED_DOTFILES` and `team.sh`'s `_CHECKOUT`, derived here for the reason
# `team.sh:75-86` states for setting `DOTFILES="${_CHECKOUT}"` on every reader
# it calls: `~/.zshrc` exports `DOTFILES=${HOME}/.dotfiles`, so a run out of a
# linked worktree would otherwise read the *main* checkout's
# `ai/herdr/team.toml` — which, on a branch that is not merged, is no route
# table at all. Not resolved through symlinks: a checkout reached with its
# `lib/` linked in, as run.sh's fixtures are, is the checkout being tested.
_CHECKOUT = Path(__file__).parents[4]


def _load() -> config.Config | None:
    """The resolved configuration, or None when it will not resolve."""
    try:
        return config.load(dotfiles=_CHECKOUT)
    except config.ConfigError:
        return None


def _route(cfg: config.Config | None, row: dict[str, Any]) -> dict[str, str]:
    """`{role, lane, profile}` for a row, or the pre-route-table answer.

    A configuration that will not resolve falls back to `exec` and the row's own
    provider rather than failing: the verbs that read a config for what it is
    (`config lint`, `doctor`) are where that failure belongs, and `team.sh` has
    already refused to start on one by the time a loop runs. The fallback is the
    answer this file gave before there was a route table.

    A configuration that resolves and then refuses this row is the same answer
    for the same reason: `route` refuses a row naming a profile no layer defines,
    which is a plan defect rather than a broken machine, and a loop that stopped
    on it would leave the rows behind it undispatched. `spawn` refuses the same
    row with the file to fix, one wave later and with the reason in front of the
    human who can act on it.
    """
    fallback = {
        "role": "exec",
        "lane": "exec",
        "profile": str(row.get("provider") or ""),
    }
    if cfg is None:
        return fallback
    try:
        return cfg.route(row)
    except config.ConfigError:
        return fallback


def lane_for(provider: str, blocks: list[str]) -> str:
    """The lane a row on `provider` that blocks `blocks` goes to.

    The signature is the one callers have — a provider and the blockers it
    holds — so a caller that has no plan row (a test, or a pane asking where a
    row would go) asks the route table the same question the wave does. The
    answer is the matched role's prefix, which is why a `cc` row that blocks
    something lands on the reviewer and a `ccd` row does not: that is `route` in
    `team.toml`, and it is the only place it is written down.
    """
    return _route(_load(), {"provider": provider, "blocks": list(blocks)})["lane"]


def routes(plan: str, table: str) -> tuple[list[str], int]:
    """(route lines, exit code) for the `ready` rows of `table`."""
    parsed = plan_rows(plan)
    if parsed["findings"]:
        for finding in parsed["findings"]:
            sys.stderr.write("loop: %s\n" % finding)
        return [], 1

    # Read once for the table rather than once per row: this is a plan's worth
    # of rows, and a `load()` per row would parse the layers per row.
    cfg = _load()
    rows = {r["task"]: r for r in parsed["rows"]}
    lines = []
    for line in table.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[1] != "ready":
            continue
        row: dict[str, Any] | None = rows.get(parts[0])
        routed = _route(cfg, row or {})
        # `-` rather than an empty field, because the wave reads this line with
        # `IFS=$'\t' read` and a tab is IFS whitespace there: two in a row
        # collapse into one delimiter, so a row with no provider but a
        # `tier_reason` would hand the reason over as the provider and spawn
        # the pane on `cc` with the row's own sentence as its `--tier-reason`.
        # It is also what the route table answers when the matched role places
        # no usable profile — nothing to launch, which the wave refuses rather
        # than filling in with a name the config does not state.
        #
        # A row the plan does not have keeps the placeholder: there is no row to
        # route, so the lane is the table's answer for one that says nothing and
        # the profile is left for the shell's own default, which is that same
        # route. A row the plan *does* have is routed, which is what lets a
        # `[[route]]` in `team.toml` put a row that names no provider on the
        # profile it names.
        provider = (routed["profile"] or "-") if row is not None else "-"
        # Whitespace-collapsed: this is one tab-separated field on a line the
        # wave splits on tabs, and a reason written as two lines in the plan
        # would otherwise arrive as extra columns and be read as a lane or a
        # provider.
        reason = " ".join(str((row or {}).get("tier_reason") or "").split())
        lines.append("%s\t%s\t%s\t%s" % (parts[0], routed["lane"], provider, reason))
    return lines, 0


def main(argv: list[str]) -> int:
    lines, code = routes(argv[0], argv[1])
    if code:
        return code
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
