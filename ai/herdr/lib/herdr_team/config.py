"""`team.sh config` — the team's settings, resolved from the layers that hold them.

The file it reads is ai/herdr/team.toml, which says what a harness is, what a
profile runs on, which role a plan row goes to, and what a spawn falls back to.
This module is the only reader: `team.sh` cannot parse TOML, and a second
reader would be a second answer.

Seven layers, lowest to highest, deep-merged tables and replacing arrays:

    1  <dotfiles>/ai/herdr/team.toml          committed defaults
    2  <dotfiles>/ai/herdr/team.local.toml    this machine, gitignored
    3  <repo>/.config/herdr/team.toml         the project's own file
    4  <repo>/.config/herdr/team.local.toml   the project, this machine only
    5  [preset.<name>], selected by HERDR_TEAM_PRESET
    6  HERDR_TEAM_* in the environment
    7  flags on the command line

Layers 1 and 2 are trusted. Layers 3 and 4 are not: a project file that could
name a launch command would be a project file that can run code, so an
untrusted layer may set `limits`, `role.<r>.profiles` and `max_per_run`,
`route`, `preset`, and `fallback.<p>.to`/`never` — and may name only cheap
profiles, so it can never route work onto the Pro login. Anything else is a
finding, and so is a `never` list that shrinks. `config trust`, which records a
repo's path and its file's sha in `~/.dotfiles/.herdr/trust`, is what lifts
that; until it lands a project layer is always untrusted, and layers 3 and 4
are only read when a checkout other than this one is named.

Values may name three things the reader expands:

    {dotfiles}          this checkout's root, from $DOTFILES or from this file
    ${VAR} / ${VAR:-x}  the environment, with a default when it is unset
    ~/…                 $HOME, at the start of a value

None of that is TOML's, so nothing is expanded at parse time and
`show --sources` can still print the value as it was written.

Run as `python3 -m herdr_team.config <verb>` with `lib/` on PYTHONPATH:

    env                      the HERDR_TEAM_* knobs, `KEY=value`, shell-quoted
    show [--sources]         every resolved key, and which layer set it
    get <dotted.key>         one resolved value, and nothing else
    lint                     schema findings, one per line
    doctor                   this machine's findings and notes, one per line
    resolve profile <name>   one profile, resolved, as `key=value`
    resolve profiles         every profile as `name<TAB>credential<TAB>ceiling<TAB>reset`
    route <row-json>         the role, lane and profile for a plan row

`env`, `resolve` and `route` refuse to answer while `lint` has findings: a
config that does not validate is not one any verb should act on, and the two
verbs that exist to explain it — `show` and `lint` — still run. `doctor` reads
the machine the file is about rather than the file, so its findings are about
the laptop: a missing key or launcher, a `--kind` this `herdr` has no. A note
is what it could not decide, and notes do not fail the verb.
"""

from __future__ import annotations

import copy
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterator, NamedTuple

from providers import RegistryError, read_toml
from providers import enabled as provider_enabled
from providers import lint as lint_providers
from providers import load as load_providers

__all__ = ["Config", "ConfigError", "Layer", "default_layers", "load", "main"]

SCHEMA = 1

# This file is `ai/herdr/lib/herdr_team/config.py`, and `parents` counts from
# its own directory rather than from the file: five up is the checkout.
# Derived rather than demanded, because the one caller that would otherwise
# have to pass it — a shell with no DOTFILES exported — is the one that cannot.
_DERIVED_DOTFILES = Path(__file__).resolve().parents[4]

# What `env` is allowed to emit. Fixed, and every name in it is one `team.sh`
# reads: a verb that printed whatever the file happened to contain would let an
# edit to a layer it does not own invent a variable in a shell it does.
#
# `limits.plan_max_paths` is deliberately absent. `plan.py` reads it from this
# file directly, and an environment variable that nothing reads is worse than
# no variable: it looks like a knob.
_ENV_KEYS: tuple[tuple[str, str], ...] = (
    ("HERDR_TEAM_ROOT", "paths.root"),
    ("HERDR_TEAM_EXEC_CAP", "role.exec.max_per_run"),
    ("HERDR_TEAM_DETECT_TIMEOUT", "limits.detect_timeout_s"),
    ("HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT", "limits.clear_confirm_timeout_s"),
    ("HERDR_TEAM_HANDOFF_MAX", "limits.handoff_max_lines"),
)

# The ones that are counts, and so the only ones with a shape to check.
_NUMERIC_ENV = frozenset(
    {
        "HERDR_TEAM_EXEC_CAP",
        "HERDR_TEAM_DETECT_TIMEOUT",
        "HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT",
        "HERDR_TEAM_HANDOFF_MAX",
    }
)

# Input variables, read from the environment and never emitted.
ENV_PRESET = "HERDR_TEAM_PRESET"
ENV_DOTFILES = "DOTFILES"
ENV_CONFIG = "HERDR_TEAM_CONFIG"
ENV_REPO = "HERDR_TEAM_REPO"

_ROOT_KEYS = frozenset(
    {
        "schema",
        "limits",
        "paths",
        "harness",
        "profile",
        "role",
        "route",
        "fallback",
        "preset",
    }
)
# Key → the smallest value that means anything. `clear_confirm_timeout_s` may be
# 0: a clear that gives the name no time to be lost is a legitimate choice.
# `exec_per_run` is not here: the number of executors one Run may hold is the
# exec role's own `max_per_run`, a bound stated beside the role it bounds —
# `HERDR_TEAM_EXEC_CAP` is mapped onto that key rather than onto a second one.
_LIMIT_MIN = {
    "detect_timeout_s": 1,
    "clear_confirm_timeout_s": 0,
    "handoff_max_lines": 1,
    "plan_max_paths": 1,
}
_HARNESS_KEYS = frozenset(
    {"kind", "launch", "launch_args", "model_arg", "reset", "enabled"}
)
_PROFILE_KEYS = frozenset(
    {
        "harness",
        "credential",
        "launch",
        "launch_args",
        "model",
        "cost",
        "requires_reason",
        "caps",
        "enabled",
    }
)
_ROLE_KEYS = frozenset(
    {"prefix", "profile", "profiles", "max_per_run", "lifetime", "cwd", "spawned"}
)
_ROUTE_KEYS = frozenset({"when", "role", "profile"})
_WHEN_KEYS = frozenset({"provider_cost", "has_blockers", "needs", "has_verify"})
_FALLBACK_KEYS = frozenset({"to", "on", "guard", "never"})
_GUARD_KEYS = frozenset({"credential", "quota_max_pct"})

COSTS = ("premium", "cheap")
LIFETIMES = ("ephemeral", "run")
CWDS = ("main", "worktree", "executor-worktree")

# The triggers a fallback chain may name. `ceiling-full` is deliberately absent:
# it is a follow-up, and a trigger a chain can name but nothing honours would
# read as a bound that had been set.
FALLBACK_ON = ("key-missing",)

# The keys an untrusted layer may set. `preset` is walked through rather than
# listed, because a preset is a partial document and may smuggle in nothing the
# layer itself could not have written.
_UNTRUSTED_ROLE_KEYS = ("profiles", "max_per_run")
_UNTRUSTED_FALLBACK_KEYS = ("to", "never")


class ConfigError(ValueError):
    """A configuration that could not be resolved, as `path:line:col: reason`.

    Raised for the failures a caller cannot be handed and asked to work around:
    a layer that will not parse, a schema this reader does not know, and a key
    an untrusted layer may not set. Raised rather than collected because every
    verb does the same thing with any of them — refuse to start, print this —
    and because the alternative, resolving from a file that was rejected, is
    exactly the fail-open a config file must not have.
    """

    def __init__(
        self,
        where: Any,
        reason: str,
        line: int | None = None,
        column: int | None = None,
    ) -> None:
        self.where = str(where)
        self.reason = reason
        self.line = line
        self.column = column
        at = self.where
        if line is not None:
            at += ":%d" % line
            if column is not None:
                at += ":%d" % column
        super().__init__("%s: %s" % (at, reason))


def _common_dir(path: Path) -> str | None:
    """That path's `--git-common-dir`, absolute, or `None` when it names no
    git checkout at all.

    Two worktrees of one repository answer with the same string; a bare
    repository, a submodule and an unrelated repository each answer with a
    different one. Used to tell "this checkout" from "a project" by identity
    rather than by path spelling, so a linked worktree of the dotfiles is
    still the dotfiles and not a project of its own.
    """
    try:
        proc = subprocess.run(
            [
                "git",
                "-C",
                str(path),
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    out = proc.stdout.strip()
    return out or None


class Layer(NamedTuple):
    """One file in the stack, and whether the repository behind it is trusted.

    Trust travels with the layer rather than with the resolver so that `config
    trust` has one thing to flip when it lands: the caller that knows the repo's
    sha is the caller that builds this list.
    """

    path: Path
    trusted: bool


# --- the stack --------------------------------------------------------------


def default_layers(
    dotfiles: Any = None, repo: Any = None, env: dict[str, str] | None = None
) -> list[Layer]:
    """The layers a `team.sh` run reads, lowest first.

    `HERDR_TEAM_CONFIG` replaces all of them with one file, which is the
    recovery path a typo in `team.local.toml` needs: without it the broken file
    is read on every verb and there is no way to ask what the defaults are.

    Layers 3 and 4 are skipped while the checkout *is* the dotfiles: they
    describe a repository other than this one, and reading them here would let
    this repo's own `.config/herdr/` become a project layer over itself, which
    is not what either file is for.
    """
    # Read through a copy, like `load` does: nothing here should be able to
    # write into the process environment, and `os.environ` is a `_Environ`
    # rather than the `dict` this parameter is declared as.
    env = dict(os.environ) if env is None else env
    if env.get(ENV_CONFIG):
        return [Layer(Path(_expand(env[ENV_CONFIG], env)).expanduser(), True)]
    where = Path(dotfiles or env.get(ENV_DOTFILES) or _DERIVED_DOTFILES)
    where = where.expanduser().resolve()
    layers = [
        Layer(where / "ai/herdr/team.toml", True),
        Layer(where / "ai/herdr/team.local.toml", True),
    ]
    project = Path(repo or env.get(ENV_REPO) or where).expanduser().resolve()
    # Compared by git identity, not by path spelling: `project` and `where`
    # name the same repository whenever their `--git-common-dir`s agree, which
    # is what makes a linked worktree of the dotfiles still read as the
    # dotfiles. Neither side being a git checkout (a bare `tmp_path` in a
    # test, say) falls back to the plain path comparison this replaces. The
    # same path needs no `git` at all, which keeps a dotfiles Run's reads free
    # of the two forks.
    same = project == where
    if not same:
        project_common = _common_dir(project)
        where_common = _common_dir(where)
        if project_common is not None and where_common is not None:
            same = project_common == where_common
    if not same:
        layers += [
            Layer(project / ".config/herdr/team.toml", False),
            Layer(project / ".config/herdr/team.local.toml", False),
        ]
    return layers


def load(
    layers: list[Layer] | None = None,
    preset: str | None = None,
    env: dict[str, str] | None = None,
    providers_path: Any = None,
    dotfiles: Any = None,
    repo: Any = None,
) -> Config:
    """Resolve the layers into one configuration.

    Everything that can be decided from the files alone is decided here; which
    machine this runs on is `doctor`'s question, not this one's.
    """
    environment = dict(os.environ) if env is None else dict(env)
    where = (
        Path(dotfiles or environment.get(ENV_DOTFILES) or _DERIVED_DOTFILES)
        .expanduser()
        .resolve()
    )
    # `_expand` reads `{dotfiles}` out of the environment, so a caller that
    # named a checkout — or a test that named a temporary one — has to see that
    # checkout's path in the values too, or the two would disagree about which
    # repository they describe.
    if dotfiles is not None or not environment.get(ENV_DOTFILES):
        environment[ENV_DOTFILES] = str(where)
    if layers is None:
        layers = default_layers(dotfiles=dotfiles, repo=repo, env=environment)
    if preset is None:
        preset = environment.get(ENV_PRESET) or None

    document: dict[str, Any] = {}
    sources: dict[str, str] = {}
    trusted: dict[str, Any] = {}
    untrusted: list[tuple[str, dict[str, Any]]] = []
    for layer in layers:
        overlay = read_layer(layer.path)
        if not overlay:
            continue
        label = str(layer.path)
        merge(document, overlay)
        for leaf in leaves(overlay):
            sources[leaf] = label
        if layer.trusted:
            merge(trusted, overlay)
        else:
            untrusted.append((label, overlay))

    # The preset, whether it came from a layer or from the environment. Applied
    # before the environment so that HERDR_TEAM_PRESET can be answered at all,
    # and it goes through the same rules as any other layer: a preset defined in
    # an untrusted file may not smuggle in a key that file could not set itself.
    presets = document.get("preset")
    if preset:
        body = presets.get(preset) if isinstance(presets, dict) else None
        if not isinstance(body, dict):
            known = ", ".join(sorted(presets)) if isinstance(presets, dict) else "none"
            raise ConfigError(
                "preset:%s" % preset, "no such preset — the layers define %s" % known
            )
        label = "preset:%s" % preset
        merge(document, body)
        for leaf in leaves(body):
            sources[leaf] = label
        shipped = trusted.get("preset")
        if not (isinstance(shipped, dict) and preset in shipped):
            untrusted.append((label, body))

    document.pop("preset", None)

    # Layer 6, the environment, and the last of it to be applied: the names that
    # stand for a key already in the document are written into it, so that `get`
    # and `show` answer what a spawn will use rather than what the files say
    # while `env` emits the other thing. Only the well-formed ones — a limit
    # that is not a number is a finding from `env_findings` below, not a limit —
    # and written as they came, because the environment is passed through
    # untouched everywhere else (`env_pairs` says why) and a value that is
    # expanded here would be the one place it was not.
    #
    # The three derived names are not here. `HERDR_TEAM_PRO_FALLBACK_MAX` and
    # the quota pair come from the guard the *file* names, and nothing but
    # `env` reads them.
    for name, key in _ENV_KEYS:
        given = environment.get(name)
        if given is None or (name in _NUMERIC_ENV and not _whole(given)):
            continue
        document_set(document, key, int(given) if name in _NUMERIC_ENV else given)
        sources[key] = name

    registry = load_registry(providers_path)
    findings = untrusted_findings(untrusted, document, trusted)
    findings += schema_findings(document, registry)
    # The registry's own findings, about the entries this document names: a
    # profile's `credential` and its ceiling are read here, so a key written
    # literally in ai/providers.toml is a secret in git that `config lint` — the
    # one verb that sees both files — has to refuse rather than report as fine
    # while the shell cache quietly defines no launcher for it. Same entries,
    # already loaded: `providers lint` is a second reader of one file, not a
    # second parse of it.
    findings += lint_providers(providers_path, registry)
    findings += env_findings(environment)
    return Config(document, sources, findings, registry, where, environment)


def read_layer(path: Path) -> dict[str, Any]:
    """One layer's document, empty when the file is not there.

    Absent is normal: `team.local.toml` exists on the machine that has one and
    nowhere else, and a project layer is absent on every checkout but its own.
    Present and unreadable is not, and raises with the position `read_toml`
    found so that the caller can name the line.
    """
    try:
        document = read_toml(path)
    except RegistryError as exc:
        if exc.reason == "no such file":
            return {}
        raise ConfigError(exc.path, exc.reason, exc.line, exc.column) from None
    version = document.get("schema")
    if version is not None and version != SCHEMA:
        raise ConfigError(
            path,
            "schema %r is not %d — this reader knows one version" % (version, SCHEMA),
        )
    return document


def load_registry(path: Any = None) -> dict[str, dict[str, Any]]:
    """The provider registry, with its decode failures told as config failures."""
    try:
        return load_providers(path)
    except RegistryError as exc:
        raise ConfigError(exc.path, exc.reason, exc.line, exc.column) from None


# --- merging ----------------------------------------------------------------


def merge(into: dict[str, Any], overlay: dict[str, Any]) -> None:
    """Deep-merge `overlay` into `into`: tables merge, everything else replaces.

    Arrays replace rather than concatenate, and that is load-bearing for the
    trust rules: an untrusted layer that could *append* to `fallback.<p>.never`
    could also drop an entry by writing the list it wants, and `role.exec.
    profiles = ["ccd"]` has to mean "these", not "these as well as what the
    defaults had".

    What is taken from `overlay` is copied, so that no table in `into` is the
    same object as a table in the layer it came from. Without that, every
    document merged from the same layer would share its nested tables, and the
    trust rules would be checking a table a *later* layer had already written
    to: `load` keeps the trusted layers aside to compare `never` against, and
    the project layer's `never = []` would land in both.
    """
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(into.get(key), dict):
            merge(into[key], value)
        else:
            into[key] = copy.deepcopy(value)


# --- what an untrusted layer may do ----------------------------------------


def untrusted_findings(
    untrusted: list[tuple[str, dict[str, Any]]],
    document: dict[str, Any],
    trusted: dict[str, Any],
) -> list[str]:
    """Everything an untrusted layer set that it may not.

    The rules are the plan's: a project chooses, the user defines. A project
    file may set limits, which roles run and how many, where rows route, and
    which fallbacks are cut off — and it may name only cheap profiles, because
    naming a premium one is a way to spend the Pro login that no `--tier-reason`
    ever passes in front of.

    `never` is compared against the *trusted* layers' table rather than the
    merged one, and that is the point of the rule: arrays replace, so by the
    time the merge has run the list an untrusted layer emptied is already empty,
    and a check against the merged document would find nothing missing. What the
    comparison needs is the list as the user left it.
    """
    profiles = document.get("profile") or {}
    roles = document.get("role") or {}
    shipped = trusted.get("fallback") or {}
    found: list[str] = []
    for label, overlay in untrusted:
        found.extend(_untrusted_body(overlay, profiles, roles, shipped, label, ""))
    return found


def _untrusted_body(
    overlay: dict[str, Any],
    profiles: dict[str, Any],
    roles: dict[str, Any],
    fallback: dict[str, Any],
    label: str,
    prefix: str,
) -> list[str]:
    found: list[str] = []
    for key, value in overlay.items():
        path = prefix + key
        # `schema` is let through: `read_layer` has already refused anything
        # that is not this reader's version, so the only thing it can say here
        # is the thing every layer says.
        if key in ("limits", "schema"):
            continue
        if key == "role" and isinstance(value, dict):
            found.extend(_untrusted_roles(value, profiles, label, path))
            continue
        if key == "route":
            found.extend(_untrusted_routes(value, profiles, roles, label, path))
            continue
        if key == "fallback" and isinstance(value, dict):
            found.extend(_untrusted_fallbacks(value, profiles, fallback, label, path))
            continue
        if key == "preset" and isinstance(value, dict):
            for name, body in value.items():
                if isinstance(body, dict):
                    found.extend(
                        _untrusted_body(
                            body,
                            profiles,
                            roles,
                            fallback,
                            label,
                            "%s.%s." % (path, name),
                        )
                    )
            continue
        found.extend(_refused(label, where) for where in _refused_paths(value, path))
    return found


def _untrusted_roles(
    roles: dict[str, Any], profiles: dict[str, Any], label: str, path: str
) -> list[str]:
    found: list[str] = []
    for name, body in roles.items():
        if not isinstance(body, dict):
            found.append(_refused(label, "%s.%s" % (path, name)))
            continue
        for field, value in body.items():
            where = "%s.%s.%s" % (path, name, field)
            if field not in _UNTRUSTED_ROLE_KEYS:
                found.append(_refused(label, where))
            elif field == "profiles":
                found.extend(_cheap_only(value, profiles, label, where))
    return found


def _untrusted_routes(
    routes: Any, profiles: dict[str, Any], roles: dict[str, Any], label: str, path: str
) -> list[str]:
    if not isinstance(routes, list):
        return [_refused(label, path)]
    found: list[str] = []
    for index, route in enumerate(routes):
        where = "%s[%d]" % (path, index)
        if not isinstance(route, dict):
            found.append(_refused(label, where))
            continue
        if "profile" in route:
            found.extend(
                _cheap_only(route["profile"], profiles, label, "%s.profile" % where)
            )
        # A route names a *role* too, and a role names the profiles it launches:
        # `role = "review"` reaches `cc` in the shipped file without a premium
        # profile appearing anywhere in this layer, so the names a route lands
        # on are walked or the rule has a hole the width of the roster. Read
        # from the merged table, so a project that has legally retargeted a role
        # to a cheap profile is not refused for routing to the role it retargeted.
        if "role" in route:
            role = roles.get(str(route["role"]))
            if isinstance(role, dict):
                for field in ("profiles", "profile"):
                    found.extend(
                        _cheap_only(
                            role.get(field),
                            profiles,
                            label,
                            "%s.role.%s" % (where, field),
                        )
                    )
        for key in route:
            if key not in _ROUTE_KEYS:
                found.append(_refused(label, "%s.%s" % (where, key)))
    return found


def _untrusted_fallbacks(
    fallbacks: dict[str, Any],
    profiles: dict[str, Any],
    trusted: dict[str, Any],
    label: str,
    path: str,
) -> list[str]:
    found: list[str] = []
    for name, body in fallbacks.items():
        if not isinstance(body, dict):
            found.append(_refused(label, "%s.%s" % (path, name)))
            continue
        for field, value in body.items():
            where = "%s.%s.%s" % (path, name, field)
            if field not in _UNTRUSTED_FALLBACK_KEYS:
                found.append(_refused(label, where))
            elif field == "to":
                found.extend(_cheap_only(value, profiles, label, where))
            elif field == "never":
                was = (trusted.get(name) or {}).get("never") or []
                dropped = sorted(set(was) - set(_as_list(value)))
                if dropped:
                    found.append(
                        "%s: %s drops %s from `never` — a project may add to "
                        "that list and never take away from it"
                        % (label, where, ", ".join(str(item) for item in dropped))
                    )
    return found


def _cheap_only(
    value: Any, profiles: dict[str, Any], label: str, where: str
) -> list[str]:
    """Untrusted layers name cheap profiles, and nothing else.

    Naming a premium profile is how a project file would spend the Pro login
    without ever passing a `--tier-reason` in front of anyone, so the names a
    project writes are checked against the cost the trusted layers gave them. A
    name no profile has is left to the schema lint, which is the check that
    knows how to say it.
    """
    found: list[str] = []
    for name in _as_list(value):
        if not isinstance(name, str):
            continue
        cost = (profiles.get(name) or {}).get("cost")
        if cost and cost != "cheap":
            found.append(
                "%s: %s names %s, whose cost is %s — an untrusted layer may name "
                "only cheap profiles, so it can never spend the Pro login"
                % (label, where, name, cost)
            )
    return found


def _refused(label: str, path: str) -> str:
    return (
        "%s: %s may not be set by an untrusted layer — a project file may set "
        "limits, role.<r>.profiles and max_per_run, route, preset and "
        "fallback.<p>.to/never; a harness, a profile or a path names a command "
        "to run or a key to spend, and those are the user's to define" % (label, path)
    )


def _refused_paths(node: Any, path: str) -> list[str]:
    """What to call a value an untrusted layer may not set.

    Reported by the deepest name the layer itself wrote, so that `harness.mine`
    is one finding about the table a project file added rather than one line per
    key inside it, while `paths.root = "/tmp"` is named down to the leaf.
    """
    if not isinstance(node, dict) or not node:
        return [path]
    found: list[str] = []
    for key, value in node.items():
        if isinstance(value, dict) and value:
            found.extend(_refused_paths(value, "%s.%s" % (path, key)))
    return found or [path]


def _as_list(value: Any) -> list[Any]:
    if isinstance(value, list):
        return list(value)
    return [value]


# --- the schema of the merged document -------------------------------------


def schema_findings(
    document: dict[str, Any], registry: dict[str, dict[str, Any]]
) -> list[str]:
    """Every way the merged document fails to be a configuration.

    Collected rather than raised, and all of them rather than the first: a
    person fixing their own file should not have to run the check seven times.
    """
    found: list[str] = []
    unknown = sorted(set(document) - _ROOT_KEYS)
    if unknown:
        found.append("unknown key %s" % ", ".join(unknown))
    if document.get("schema") is None:
        found.append("no `schema` — no layer says which version this file is")

    found.extend(_find_limits(document.get("limits")))
    found.extend(_find_paths(document.get("paths")))
    found.extend(_find_harnesses(document.get("harness")))
    found.extend(_find_profiles(document, registry))
    found.extend(_find_roles(document))
    found.extend(_find_routes(document))
    found.extend(_find_fallbacks(document, registry))
    return found


def _find_limits(limits: Any) -> list[str]:
    if not isinstance(limits, dict):
        return ["no `[limits]` table"]
    found: list[str] = []
    unknown = sorted(set(limits) - set(_LIMIT_MIN))
    if unknown:
        found.append("limits: unknown key %s" % ", ".join(unknown))
    for key in sorted(set(_LIMIT_MIN) & set(limits)):
        value = limits[key]
        if not _is_int(value) or value < _LIMIT_MIN[key]:
            found.append(
                "limits.%s must be a whole number of %d or more"
                % (key, _LIMIT_MIN[key])
            )
    return found


def _find_paths(paths: Any) -> list[str]:
    if not isinstance(paths, dict):
        return ["no `[paths]` table"]
    found: list[str] = []
    unknown = sorted(set(paths) - {"root"})
    if unknown:
        found.append("paths: unknown key %s" % ", ".join(unknown))
    root = paths.get("root")
    if not isinstance(root, str) or not root:
        found.append("paths.root must be a path")
    return found


def _find_harnesses(harnesses: Any) -> list[str]:
    if not isinstance(harnesses, dict):
        return ["no `[harness.*]` table"]
    found: list[str] = []
    for name in sorted(harnesses):
        body = harnesses[name]
        where = "harness.%s" % name
        if not isinstance(body, dict):
            found.append("%s must be a table" % where)
            continue
        unknown = sorted(set(body) - _HARNESS_KEYS)
        if unknown:
            found.append("%s: unknown key %s" % (where, ", ".join(unknown)))
        kind = body.get("kind")
        if not isinstance(kind, str) or not kind:
            found.append(
                "%s: no kind — herdr detects a pane by its kind, and a harness "
                "without one is a pane nothing can find" % where
            )
        found.extend(_find_str_list(body, "launch_args", where))
        for key in ("launch", "model_arg", "reset"):
            if key in body and not isinstance(body[key], str):
                found.append("%s.%s must be a string" % (where, key))
        if "enabled" in body and not isinstance(body["enabled"], bool):
            found.append("%s.enabled must be true or false" % where)
    return found


def _find_profiles(
    document: dict[str, Any], registry: dict[str, dict[str, Any]]
) -> list[str]:
    profiles = document.get("profile")
    harnesses = document.get("harness") or {}
    if not isinstance(profiles, dict):
        return ["no `[profile.*]` table"]
    found: list[str] = []
    for name in sorted(profiles):
        body = profiles[name]
        where = "profile.%s" % name
        if not isinstance(body, dict):
            found.append("%s must be a table" % where)
            continue
        unknown = sorted(set(body) - _PROFILE_KEYS)
        if unknown:
            found.append("%s: unknown key %s" % (where, ", ".join(unknown)))

        harness = body.get("harness")
        if not isinstance(harness, str) or not harness:
            found.append(
                "%s: no harness — a profile is harness x credential x model" % where
            )
        elif harness not in harnesses:
            found.append(
                "%s: harness %r is not a [harness.*] entry — known are %s"
                % (where, harness, ", ".join(sorted(harnesses)) or "none")
            )

        credential = body.get("credential")
        if not isinstance(credential, str) or not credential:
            found.append(
                "%s: no credential — a profile spends a key, and the key is a "
                "[provider.*] entry in ai/providers.toml" % where
            )
        elif credential not in registry:
            found.append(
                "%s: credential %r is not in ai/providers.toml — known are %s"
                % (where, credential, ", ".join(sorted(registry)) or "none")
            )
        else:
            reachable = registry[credential].get("harnesses")
            if isinstance(reachable, list) and harness not in reachable:
                found.append(
                    "%s: harness %s is not one the %s credential lists (%s)"
                    % (
                        where,
                        harness,
                        credential,
                        ", ".join(str(item) for item in reachable),
                    )
                )

        cost = body.get("cost", "cheap")
        if cost not in COSTS:
            found.append(
                "%s: cost %r is not one of %s" % (where, cost, ", ".join(COSTS))
            )
        elif cost == "premium" and body.get("requires_reason") is not True:
            found.append(
                "%s: cost is premium and `requires_reason` is not set — a "
                "premium pane nobody has to account for is the silent Pro spend "
                "the cost rules forbid" % where
            )
        for key in ("requires_reason", "enabled"):
            if key in body and not isinstance(body[key], bool):
                found.append("%s.%s must be true or false" % (where, key))
        for key in ("launch", "model"):
            if key in body and not isinstance(body[key], str):
                found.append("%s.%s must be a string" % (where, key))
        found.extend(_find_str_list(body, "caps", where))
        found.extend(_find_str_list(body, "launch_args", where))

        launch = body.get("launch")
        if isinstance(launch, str) and credential in registry:
            short = (registry[credential].get("launcher") or {}).get("short")
            if short and short != launch:
                found.append(
                    "%s: launch %r disagrees with %s's launcher short %r — a "
                    "launcher is defined under the name providers.toml gives it"
                    % (where, launch, credential, short)
                )
    return found


def _find_roles(document: dict[str, Any]) -> list[str]:
    roles = document.get("role")
    profiles = document.get("profile") or {}
    if not isinstance(roles, dict):
        return ["no `[role.*]` table"]
    found: list[str] = []
    for name in sorted(roles):
        body = roles[name]
        where = "role.%s" % name
        if not isinstance(body, dict):
            found.append("%s must be a table" % where)
            continue
        unknown = sorted(set(body) - _ROLE_KEYS)
        if unknown:
            found.append("%s: unknown key %s" % (where, ", ".join(unknown)))
        spawned = body.get("spawned", True)
        if not isinstance(spawned, bool):
            found.append("%s.spawned must be true or false" % where)
        if spawned and not body.get("prefix"):
            # The prefix is the pane-name prefix *and* the lane `loop` answers,
            # so a role without one is a role no pane can be named for.
            found.append(
                "%s: no prefix — a role's prefix is its pane name and its lane" % where
            )
        if "profile" in body and "profiles" in body:
            found.append("%s: profile and profiles are mutually exclusive" % where)
        for key in ("profile", "profiles"):
            for ref in _as_list(body.get(key, [])):
                found.extend(_find_profile_ref(ref, profiles, "%s.%s" % (where, key)))
        if "lifetime" in body and body["lifetime"] not in LIFETIMES:
            found.append(
                "%s.lifetime %r is not one of %s"
                % (where, body["lifetime"], ", ".join(LIFETIMES))
            )
        if "cwd" in body and body["cwd"] not in CWDS:
            found.append(
                "%s.cwd %r is not one of %s" % (where, body["cwd"], ", ".join(CWDS))
            )
        if "max_per_run" in body and (
            not _is_int(body["max_per_run"]) or body["max_per_run"] < 1
        ):
            found.append("%s.max_per_run must be a whole number of 1 or more" % where)
    return found


def _find_routes(document: dict[str, Any]) -> list[str]:
    routes = document.get("route")
    profiles = document.get("profile") or {}
    roles = document.get("role") or {}
    if not isinstance(routes, list) or not routes:
        return ["no `[[route]]` — a plan row with no route has no lane"]
    found: list[str] = []
    for index, route in enumerate(routes):
        where = "route[%d]" % index
        if not isinstance(route, dict):
            found.append("%s must be a table" % where)
            continue
        unknown = sorted(set(route) - _ROUTE_KEYS)
        if unknown:
            found.append("%s: unknown key %s" % (where, ", ".join(unknown)))
        role = route.get("role")
        if not isinstance(role, str) or not role:
            found.append(
                "%s: no role — a route that matches a row must land it somewhere"
                % where
            )
        elif role not in roles:
            found.append(
                "%s: role %r is not a [role.*] entry — known are %s"
                % (where, role, ", ".join(sorted(roles)) or "none")
            )
        if "profile" in route:
            found.extend(
                _find_profile_ref(route["profile"], profiles, "%s.profile" % where)
            )
        when = route.get("when")
        if when is None:
            continue
        if not isinstance(when, dict):
            found.append("%s.when must be a table" % where)
            continue
        unknown = sorted(set(when) - _WHEN_KEYS)
        if unknown:
            found.append(
                "%s.when: unknown condition %s — known are %s"
                % (where, ", ".join(unknown), ", ".join(sorted(_WHEN_KEYS)))
            )
        for key in ("has_blockers", "has_verify"):
            if key in when and not isinstance(when[key], bool):
                found.append("%s.when.%s must be true or false" % (where, key))
        if "provider_cost" in when and when["provider_cost"] not in COSTS:
            found.append(
                "%s.when.provider_cost %r is not one of %s"
                % (where, when["provider_cost"], ", ".join(COSTS))
            )
    return found


def _find_fallbacks(
    document: dict[str, Any], registry: dict[str, dict[str, Any]]
) -> list[str]:
    fallbacks = document.get("fallback")
    profiles = document.get("profile") or {}
    if not isinstance(fallbacks, dict):
        return []
    found: list[str] = []
    for name in sorted(fallbacks):
        body = fallbacks[name]
        where = "fallback.%s" % name
        if not isinstance(body, dict):
            found.append("%s must be a table" % where)
            continue
        unknown = sorted(set(body) - _FALLBACK_KEYS)
        if unknown:
            found.append("%s: unknown key %s" % (where, ", ".join(unknown)))
        if name not in profiles:
            found.append(
                "%s: %r is not a [profile.*] entry — a chain hangs off a profile"
                % (where, name)
            )
        to = _as_list(body["to"]) if "to" in body else []
        never = _as_list(body["never"]) if "never" in body else []
        for ref in to + never:
            found.extend(_find_profile_ref(ref, profiles, where))
        both = sorted({str(ref) for ref in to} & {str(ref) for ref in never})
        if both:
            found.append(
                "%s: %s is in both `to` and `never` — a chain that lands "
                "somewhere it may not is a chain nobody can reason about"
                % (where, ", ".join(both))
            )
        for trigger in _as_list(body["on"]) if "on" in body else []:
            if trigger not in FALLBACK_ON:
                found.append(
                    "%s.on: %r is not one of %s — a trigger nothing honours "
                    "reads as a bound that was set"
                    % (where, trigger, ", ".join(FALLBACK_ON))
                )
        guard = body.get("guard")
        if guard is not None:
            found.extend(_find_guard(guard, to, profiles, registry, where))
    found.extend(_find_cycles(fallbacks))
    return found


def _find_guard(
    guard: Any,
    to: list[Any],
    profiles: dict[str, Any],
    registry: dict[str, dict[str, Any]],
    where: str,
) -> list[str]:
    if not isinstance(guard, dict):
        return ["%s.guard must be a table" % where]
    found: list[str] = []
    unknown = sorted(set(guard) - _GUARD_KEYS)
    if unknown:
        found.append("%s.guard: unknown key %s" % (where, ", ".join(unknown)))
    credential = guard.get("credential")
    if not isinstance(credential, str) or not credential:
        found.append(
            "%s.guard: no credential — a ceiling is measured against one "
            "window, and which one is not inferable from a list" % where
        )
    else:
        if credential not in registry:
            found.append(
                "%s.guard: credential %r is not in ai/providers.toml"
                % (where, credential)
            )
        lands = {
            str((profiles.get(ref) or {}).get("credential"))
            for ref in to
            if isinstance(ref, str)
        }
        if lands and credential not in lands:
            found.append(
                "%s.guard: credential %r is not one the chain lands on — `to` "
                "spends %s" % (where, credential, ", ".join(sorted(lands)))
            )
        entry = registry.get(credential)
        if entry is not None and not isinstance(entry.get("quota"), dict):
            found.append(
                "%s.guard: credential %r has no [quota] to be measured against"
                % (where, credential)
            )
    # `guard` is `Any` all the way down, so `guard.get` is `Any | None`, and
    # `_is_int` is a plain `bool` rather than a `TypeGuard`: a `TypeGuard` narrows
    # the positive branch only, and what this check needs is the negative one —
    # `not _is_int(pct)` leaving `pct` an int, which is `TypeIs`, and 3.13's.
    # Said out loud instead: after the `or`, the value is an int.
    pct: Any = guard.get("quota_max_pct")
    if not _is_int(pct) or not 1 <= pct <= 100:
        found.append(
            "%s.guard.quota_max_pct must be a whole number from 1 to 100" % where
        )
    return found


def _find_cycles(fallbacks: dict[str, Any]) -> list[str]:
    """Every cycle in the `to` graph, named as the path that closes it.

    A cycle is not a slow chain, it is a spawn that can never answer: the
    fallback is what runs when the first credential is unusable, and a chain
    that comes back to where it started asks the same question again.
    """
    found: list[str] = []
    colour: dict[str, int] = {}
    stack: list[str] = []

    def walk(name: str) -> None:
        colour[name] = 1
        stack.append(name)
        body = fallbacks.get(name)
        targets = (
            _as_list(body["to"]) if isinstance(body, dict) and "to" in body else []
        )
        for target in sorted(str(item) for item in targets):
            if target not in fallbacks:
                continue
            if colour.get(target) == 1:
                path = stack[stack.index(target) :] + [target]
                found.append(
                    "fallback: a cycle through %s — a chain that comes back to "
                    "where it started can never answer" % " -> ".join(path)
                )
            elif colour.get(target, 0) == 0:
                walk(target)
        stack.pop()
        colour[name] = 2

    for name in sorted(fallbacks):
        if colour.get(name, 0) == 0 and isinstance(fallbacks[name], dict):
            walk(name)
    return found


def _find_profile_ref(ref: Any, profiles: dict[str, Any], where: str) -> list[str]:
    if not isinstance(ref, str) or not ref:
        return ["%s names %r, which is not a profile name" % (where, ref)]
    if ref not in profiles:
        return [
            "%s names %r, which is not a [profile.*] entry — known are %s"
            % (where, ref, ", ".join(sorted(profiles)) or "none")
        ]
    return []


def _find_str_list(body: dict[str, Any], key: str, where: str) -> list[str]:
    if key not in body:
        return []
    value = body[key]
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        return ["%s.%s must be a list of strings" % (where, key)]
    return []


def _is_int(value: Any) -> bool:
    """True for an int, and for a bool-free int only.

    `isinstance(True, int)` is True in Python and TOML has no `limits.true = 1`,
    so `plan_max_paths = true` would compare as 1 and read as a limit nobody set.
    """
    return isinstance(value, int) and not isinstance(value, bool)


# --- the environment layer --------------------------------------------------


def env_findings(env: dict[str, str]) -> list[str]:
    """A numeric `HERDR_TEAM_*` override that cannot mean what it says.

    Only the counts, and only their shape: every other value from the
    environment is passed through untouched — `HERDR_TEAM_ROOT` is a path, and
    `70%` reaches `team.sh` unread, because `team.sh` has its own gate for a
    limit nobody can parse and that gate exits 6 with the message the frozen
    test matches. What is caught here is the typo that would otherwise surface
    as a shell error in the middle of a spawn.
    """
    found: list[str] = []
    for name, key in _ENV_KEYS:
        if name in _NUMERIC_ENV and name in env and not _whole(env[name]):
            found.append(
                "%s=%s is not a whole number, and %s is a limit `team.sh` "
                "compares as a number" % (name, env[name], key)
            )
    return found


def _whole(value: str) -> bool:
    return bool(value) and all(char in "0123456789" for char in value)


def document_value(document: dict[str, Any], key: str) -> Any:
    node: Any = document
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def document_set(document: dict[str, Any], key: str, value: Any) -> None:
    """Write one dotted key, making the tables above it.

    The reader's only writer, and the environment layer's: a name in `_ENV_KEYS`
    is a path, and `role.exec.max_per_run` is three of them — a table has to
    exist before its leaf can be written, and a `partition(".")` that stopped at
    the first dot would write the literal key `exec.max_per_run` into `[role]`,
    which nothing reads and no lint reports.
    """
    parts = key.split(".")
    node = document
    for part in parts[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            child = {}
            node[part] = child
        node = child
    node[parts[-1]] = value


# --- the expansion of a value ----------------------------------------------


def _expand(value: str, env: dict[str, str]) -> str:
    """`{dotfiles}`, `${VAR}` and `${VAR:-default}` in a value, expanded once.

    Not TOML's, and not expanded at parse time, so `show --sources` can still
    print what the file says. A reference with no default and no value in the
    environment expands to empty rather than raising: which knobs a machine has
    is `doctor`'s question, and a config that refused to resolve because
    `CLAUDE_CONFIG_DIR` was unset would be a config no verb could report on.
    """
    root = env.get(ENV_DOTFILES) or str(_DERIVED_DOTFILES)
    out: list[str] = []
    index = 0
    while index < len(value):
        if value.startswith("{dotfiles}", index):
            out.append(root)
            index += len("{dotfiles}")
        elif value.startswith("${", index):
            end, name, default = _parse_ref(value, index)
            if name in env:
                out.append(env[name])
            elif name == "HOME":
                out.append(_home(env))
            elif default is not None:
                out.append(_expand(default, env))
            index = end
        elif index == 0 and value.startswith("~/"):
            out.append(_home(env))
            index += 1
        else:
            out.append(value[index])
            index += 1
    return "".join(out)


def _home(env: dict[str, str]) -> str:
    """`$HOME`, from the environment or from the OS.

    The one name that falls back, and it falls back to the same answer: a verb
    run as `env -i python3 -m herdr_team.config env` still has a home
    directory, and `${HOME}` expanding to nothing would point the quota cache at
    `/.claude/cache/pro-quota.json` — a path that is not wrong so much as
    somewhere no Pro window was ever written.
    """
    return env.get("HOME") or str(Path.home())


def _parse_ref(value: str, start: int) -> tuple[int, str, str | None]:
    """`(index past the reference, name, default)` for the `${` at `start`.

    A hand-rolled scan rather than a pattern, because the default may contain a
    reference of its own — `${CLAUDE_CONFIG_DIR:-${HOME}/.claude}` is the one
    this checkout ships — and a pattern that stopped at the first `}` would read
    that default as `${HOME`.
    """
    depth = 0
    index = start + 2
    while index < len(value):
        if value.startswith("${", index):
            depth += 1
            index += 2
            continue
        if value[index] == "}":
            if depth == 0:
                break
            depth -= 1
        index += 1
    name, separator, default = value[start + 2 : index].partition(":-")
    return index + 1, name, default if separator else None


def _deep_expand(node: Any, env: dict[str, str]) -> Any:
    if isinstance(node, str):
        return _expand(node, env)
    if isinstance(node, dict):
        return {key: _deep_expand(value, env) for key, value in node.items()}
    if isinstance(node, list):
        return [_deep_expand(item, env) for item in node]
    return node


# --- the resolved configuration --------------------------------------------


class Config:
    """One resolved configuration: the document, where each value came from,
    every finding, and the provider registry it was checked against."""

    def __init__(
        self,
        document: dict[str, Any],
        sources: dict[str, str],
        findings: list[str],
        registry: dict[str, dict[str, Any]],
        dotfiles: Path,
        env: dict[str, str],
    ) -> None:
        self.document = document
        self.sources = sources
        self.findings = findings
        self.registry = registry
        self.dotfiles = dotfiles
        self.env = env

    # -- lint --------------------------------------------------------------

    def lint(self) -> list[str]:
        return list(self.findings)

    def clean(self) -> None:
        """Refuse to answer while the configuration does not validate."""
        if self.findings:
            raise ConfigError(
                self.sources.get("schema", "the configuration"),
                "%d finding(s), so nothing is resolved from it — run `config "
                "lint`: %s" % (len(self.findings), self.findings[0]),
            )

    # -- reading -----------------------------------------------------------

    def get(self, key: str, default: Any = None) -> Any:
        """A dotted key, expanded. `default` when it is not there."""
        value = document_value(self.document, key)
        if value is None:
            return default
        return _deep_expand(value, self.env)

    def source(self, key: str) -> str:
        return self.sources.get(key, "?")

    def resolved(self) -> dict[str, Any]:
        """The document with every string value expanded."""
        expanded = _deep_expand(self.document, self.env)
        assert isinstance(expanded, dict)
        return expanded

    # -- the shell-facing verbs -------------------------------------------

    def env_pairs(self) -> list[tuple[str, str]]:
        """`(name, value)` for every knob `team.sh` reads, the environment last.

        A name already in the environment is emitted with its own value,
        untouched. That is what keeps `HERDR_TEAM_PRO_FALLBACK_MAX=70%` reaching
        `team.sh`'s own gate instead of being corrected here — the gate that
        exits 6 naming it is the frozen test's, and a reader that quietly fixed
        the value up would make that test pass for the wrong reason.
        """
        self.clean()
        pairs = [(name, _render(self.get(key))) for name, key in _ENV_KEYS]
        guard = self.guard()
        if guard is not None:
            pairs.append(
                ("HERDR_TEAM_PRO_FALLBACK_MAX", _render(guard.get("quota_max_pct")))
            )
            quota = self.registry.get(str(guard.get("credential")), {}).get("quota")
            if isinstance(quota, dict):
                for name, key in (
                    ("HERDR_TEAM_PRO_QUOTA_CACHE", "cache"),
                    ("HERDR_TEAM_PRO_QUOTA_MAX_AGE", "max_age_s"),
                ):
                    if key in quota:
                        pairs.append(
                            (name, _render(_deep_expand(quota[key], self.env)))
                        )
        return [(name, self.env.get(name, value)) for name, value in pairs]

    def env_lines(self) -> list[str]:
        """`KEY=value` lines for `eval`, every value quoted.

        Quoted unconditionally rather than when it looks like it needs it: a
        value can come from a project layer, and a config file that can put an
        unquoted word into `eval` is a config file that can run code.
        """
        return [
            "%s=%s" % (name, shlex.quote(value)) for name, value in self.env_pairs()
        ]

    def guard(self) -> dict[str, Any] | None:
        """The fallback guard the executor tier's own chain carries.

        Found by following `role.exec.profiles` to the first profile with a
        `[fallback.<p>]` guard, rather than by naming `ccd` here: the profile a
        task runs on is a config decision, and a module with that name written
        into it would be one more place a new tier has to be added to.
        """
        roles = self.document.get("role") or {}
        chains = self.document.get("fallback") or {}
        for name in _as_list((roles.get("exec") or {}).get("profiles")):
            body = chains.get(name)
            guard = body.get("guard") if isinstance(body, dict) else None
            if isinstance(guard, dict):
                return guard
        return None

    # -- resolve -----------------------------------------------------------

    def usable(self, name: str) -> str | None:
        """Why a pane may not be launched on `name`, or None when it may.

        Enablement is inherited: a profile is usable when it, its harness and
        its credential are all enabled, because a profile is a composition and
        disabling any part of it disables the whole.
        """
        body = (self.document.get("profile") or {}).get(name)
        if not isinstance(body, dict):
            return "there is no profile %r" % name
        if not body.get("enabled", True):
            return "profile %s is disabled" % name
        harness = (self.document.get("harness") or {}).get(body.get("harness")) or {}
        if isinstance(harness, dict) and not harness.get("enabled", True):
            return (
                "profile %s is disabled by its %s harness — a harness ships "
                "disabled until a pane has been spawned on it by hand"
                % (name, body.get("harness"))
            )
        entry = self.registry.get(str(body.get("credential"))) or {}
        if not provider_enabled(entry):
            return (
                "profile %s is disabled by its %s credential — a provider entry "
                "ships disabled until its launch injection is verified"
                % (name, body.get("credential"))
            )
        return None

    def profile(self, name: str) -> dict[str, str]:
        """One profile, flattened and resolved, ready for `team.sh` to eval.

        Everything a `spawn` needs to decide, in one place, so that no verb has
        to reach for the document a second time: what to launch and with what,
        whether a key probe applies (`key` is set or it is not), where a missing
        one goes, and which credential's window bounds that fallback. What is
        not here is a field nothing reads — an emitted key is a promise that a
        shell reads it, and a promise kept by nothing is the reader's answer
        drifting out of step with the one `team.sh` asks for.
        """
        self.clean()
        why = self.usable(name)
        if why is not None:
            raise ConfigError(name, why)
        body = (self.document.get("profile") or {})[name]
        harness = (self.document.get("harness") or {}).get(body.get("harness")) or {}
        entry = self.registry.get(str(body.get("credential"))) or {}
        chain = (self.document.get("fallback") or {}).get(name) or {}
        guard = chain.get("guard") or {}
        args = list(harness.get("launch_args") or []) + list(
            body.get("launch_args") or []
        )
        # `model` is the profile's own word and nothing else. The registry's
        # `models.default` is what `cc_provider` injects into a launcher's
        # environment; handing it back here as well would put a second copy of
        # one decision on a command line, as `--model deepseek-flash` beside a
        # launcher that already sets it — a flag the profile never asked for.
        return {
            "launch": _expand(
                str(
                    body.get("launch")
                    or harness.get("launch")
                    or harness.get("kind")
                    or ""
                ),
                self.env,
            ),
            "launch_args": " ".join(_expand(str(arg), self.env) for arg in args),
            "model": _expand(str(body.get("model") or ""), self.env),
            "model_arg": str(harness.get("model_arg") or ""),
            "requires_reason": _render(body.get("requires_reason", False)),
            "key": str(entry.get("key") or ""),
            "url": str(entry.get("url") or ""),
            "fallback": " ".join(str(ref) for ref in chain.get("to") or []),
            "fallback_on": " ".join(str(item) for item in chain.get("on") or []),
            "guard_credential": str(guard.get("credential") or ""),
            "quota_max_pct": _render(guard.get("quota_max_pct", "")),
        }

    def profiles_table(self) -> list[str]:
        """Every profile as `name<TAB>credential<TAB>ceiling<TAB>reset`.

        What `resolve profile` cannot answer for a pane that already exists, and
        the reason this verb exists: the ceiling counts panes per *credential* —
        two profiles on one key share a budget — while a pane record names a
        *profile*, so counting one means knowing which profiles share an entry.
        Asking per pane would be a lookup per pane; this is the whole table in
        one call, which `team.sh` reads once and holds. The reset is here for
        the same shape of reason: `settle` holds a record rather than a profile
        and has to know what that record's harness clears with.

        Every profile the inventory defines, disabled ones included. A pane
        spawned before a profile was disabled still holds the credential that
        profile spends and still has the context only that profile's harness
        knows how to clear, and a reader that could not place it would be
        answering for nobody. Tabs and nothing else, because the caller reads
        this with `awk -F'\\t'` rather than with `eval`; an unstated ceiling or
        a harness that names no reset is an empty field, which is the caller's
        to refuse.
        """
        self.clean()
        rows = []
        harnesses = self.document.get("harness") or {}
        for name in sorted(self.document.get("profile") or {}):
            body = (self.document.get("profile") or {})[name]
            if not isinstance(body, dict):
                continue
            credential = str(body.get("credential") or "")
            entry = self.registry.get(credential) or {}
            harness = harnesses.get(body.get("harness"))
            if not isinstance(harness, dict):
                harness = {}
            rows.append(
                "\t".join(
                    (
                        name,
                        credential,
                        _render(entry.get("ceiling", "")),
                        str(harness.get("reset") or ""),
                    )
                )
            )
        return rows

    # -- route -------------------------------------------------------------
    def route(self, row: dict[str, Any]) -> dict[str, str]:
        """`{role, lane, profile}` for a plan row: first matching route wins.

        The row's own `provider` always wins for the profile — that is what the
        field is for — but it does not choose the lane on its own any more: the
        lane is the role's prefix, and the role comes from the table above, with
        the row's provider's own cost as one of the conditions.

        A name no layer defines is refused rather than treated as absent: the
        profile is what a pane record, a ceiling count and half the sentences
        `team.sh` prints are spelled with, so quietly answering the default for
        a name the config does not know is a row running somewhere its author
        did not write. `spawn` refuses the same name with the file to fix, and
        that is where an unknown provider has always been caught.
        """
        self.clean()
        profiles = self.document.get("profile") or {}
        named = str(row.get("provider") or "").strip()
        if named and named not in profiles:
            raise ConfigError(
                "route",
                "the row names %s, and no layer defines a profile of that name — "
                "a provider is a [profile.*] entry in ai/herdr/team.toml, and a "
                "row naming one this config does not know is refused rather than "
                "run on the default" % named,
            )
        profile = named if named in profiles else ""
        cost = (
            str((profiles.get(profile) or {}).get("cost") or "cheap") if profile else ""
        )
        for index, route in enumerate(self.document.get("route") or []):
            if not isinstance(route, dict):
                continue
            if not _matches(route.get("when"), row, cost):
                continue
            role = str(route.get("role") or "")
            chosen = (
                str(route.get("profile") or "") or profile or self._first_usable(role)
            )
            return {"role": role, "lane": self._lane(role), "profile": chosen or "-"}
        # Unreachable with a lint-clean file — `route` refuses to answer while
        # findings exist, and a table with no catch-all is a finding — but an
        # index that cannot be reached is worse than a default that can.
        return {"role": "exec", "lane": "exec", "profile": profile or "-"}

    def _lane(self, role: str) -> str:
        role_body = (self.document.get("role") or {}).get(role) or {}
        prefix = str(role_body.get("prefix") or role)
        return prefix[:-1] if prefix.endswith("-") else prefix

    def _first_usable(self, role: str) -> str:
        body = (self.document.get("role") or {}).get(role) or {}
        names = _as_list(body.get("profiles")) + _as_list(body.get("profile"))
        for name in names:
            if isinstance(name, str) and self.usable(name) is None:
                return name
        return ""

    # -- doctor ------------------------------------------------------------

    def doctor(self) -> tuple[list[str], list[str]]:
        """What this machine would have to be for a spawn to work here.

        `lint` reads the file; this reads the machine the file is about, which
        is why the two are separate verbs and why only one of them can fail on
        a laptop that is simply not set up yet.

        A **finding** is a mismatch this reader is sure of: a harness whose
        `kind` this `herdr` does not offer, a launcher no shell defines, a key
        the environment is supposed to hold and does not with nothing to fall
        back to, an `op://` reference with no `op` to read it. A **note** is a
        question this process could not put to the machine — a `herdr` that
        will not say what kinds it takes, no zsh to ask about a launcher — or
        one whose answer is not this verb's to decide, like a shell whose
        `CC_PROVIDER` is not the orchestrator's. Findings exit 1; notes, and a
        clean machine, exit 0.
        """
        self.clean()
        findings: list[str] = []
        notes: list[str] = []
        harnesses = self.document.get("harness") or {}
        profiles = self.document.get("profile") or {}
        usable = [name for name in sorted(profiles) if self.usable(name) is None]
        if not usable:
            notes.append(
                "no profile is usable, so there is nothing to launch a pane on — "
                "`config lint` says why, profile by profile"
            )

        # The kind, which is one `herdr agent start --help` for all of them: it
        # is the value `spawn` detects a pane by, and a kind this build does not
        # know is a pane that starts and is never seen again.
        wanted: dict[str, list[str]] = {}
        for name in usable:
            kind = str(
                (harnesses.get(profiles[name].get("harness")) or {}).get("kind") or ""
            )
            if kind:
                wanted.setdefault(kind, []).append(name)
        kinds = _herdr_kinds()
        if wanted and kinds is None:
            notes.append(
                "herdr would not say which `--kind` values it takes — ask it "
                "`herdr agent start --help` and check %s by hand"
                % ", ".join(sorted(wanted))
            )
        elif kinds is not None:
            for kind in sorted(wanted):
                if kind not in kinds:
                    findings.append(
                        "profile %s launches a %s harness, and this herdr has no "
                        "`--kind %s` — it takes %s"
                        % (
                            ", ".join(wanted[kind]),
                            profiles[wanted[kind][0]].get("harness"),
                            kind,
                            ", ".join(sorted(kinds)),
                        )
                    )

        # The launcher: the command a pane is started with, which for the
        # Claude profiles is a shell function `ai/claude/providers.zsh` defines
        # and not an executable anywhere. PATH first, one `zsh -ic` for what is
        # left, because that is the shell `spawn` starts a pane in.
        commands: dict[str, list[str]] = {}
        for name in usable:
            body = profiles[name]
            harness = harnesses.get(body.get("harness")) or {}
            written = str(
                body.get("launch") or harness.get("launch") or harness.get("kind") or ""
            )
            words = _expand(written, self.env).split()
            if words:
                commands.setdefault(words[0], []).append(name)
        missing = [name for name in commands if shutil.which(name) is None]
        if missing:
            known = _shell_defines(missing, self.env)
            if known is None:
                notes.append(
                    "no zsh to ask which launchers this machine defines, and %s "
                    "are not executables on PATH — `zsh -ic 'whence -w %s'`"
                    % (", ".join(missing), " ".join(missing))
                )
            else:
                for name in missing:
                    if not known.get(name):
                        findings.append(
                            "profile %s is launched with %s, which is not on PATH "
                            "and not defined by the shell a pane is started in"
                            % (", ".join(commands[name]), name)
                        )

        # The key, and only where a key is what a launch needs: an entry with
        # no `launcher` is not started through `cc_provider` at all (omp reads
        # its own file) or holds a login rather than a key, and flagging either
        # would be a finding on a machine that is working.
        for name in usable:
            body = profiles[name]
            entry = self.registry.get(str(body.get("credential"))) or {}
            if not entry.get("launcher"):
                continue
            key = str(entry.get("key") or "")
            if key.startswith("env:"):
                var = key[len("env:") :]
                if self.env.get(var):
                    continue
                chain = (self.document.get("fallback") or {}).get(name) or {}
                fallback = [str(ref) for ref in chain.get("to") or []]
                if fallback:
                    notes.append(
                        "%s's key %s is not set, so a spawn falls back to %s"
                        % (name, var, ", ".join(fallback))
                    )
                else:
                    findings.append(
                        "%s is launched with %s and %s is not set, and nothing "
                        "falls back from %s — a spawn would have no credential"
                        % (
                            name,
                            (entry.get("launcher") or {}).get("short"),
                            var,
                            name,
                        )
                    )
            elif key.startswith("op://") and shutil.which("op") is None:
                findings.append(
                    "%s's key is %s and `op` is not on PATH, so nothing can read "
                    "it" % (name, key)
                )

        # The orchestrator, which is the one role no spawn starts: the note is
        # that this shell is holding a different credential than the profile the
        # role names, which is worth saying and is not this verb's to refuse.
        orchestrator = (self.document.get("role") or {}).get("orchestrator") or {}
        held = self.env.get("CC_PROVIDER") or ""
        named = str(orchestrator.get("profile") or "")
        if held and named in profiles:
            credential = str(profiles[named].get("credential") or "")
            if credential and credential != held:
                notes.append(
                    "this shell holds CC_PROVIDER=%s and [role.orchestrator] "
                    "names %s (%s)" % (held, named, credential)
                )
        return findings, notes

    # -- show --------------------------------------------------------------

    def show(self, sources: bool = False) -> list[str]:
        """One line per resolved key, and with `sources`, which layer set it.

        Prints `?` for a key no layer set, which is the honest answer for a
        value that came from nowhere: it means no layer wrote it down.
        """
        lines: list[str] = []
        for path, value in flatten(self.resolved()):
            line = "%s = %s" % (path, _render(value))
            if sources:
                line += "  # %s" % self.source(path)
            lines.append(line)
        return lines


def _matches(when: Any, row: dict[str, Any], cost: str) -> bool:
    """Whether a route's `when` accepts a row. No `when` accepts everything."""
    if when is None:
        return True
    if not isinstance(when, dict):
        return False
    for key, want in when.items():
        if key == "provider_cost":
            if cost != want:
                return False
        elif key == "has_blockers":
            if bool(_as_list(row.get("blocks") or [])) is not want:
                return False
        elif key == "has_verify":
            if bool(str(row.get("verify") or "").strip()) is not want:
                return False
        elif key == "needs":
            if str(want) not in _needs(row):
                return False
    return True


def _needs(row: dict[str, Any]) -> list[str]:
    """A row's `needs`, as the individual capabilities a route can match one of."""
    raw = row.get("needs")
    if isinstance(raw, list):
        return [str(item) for item in raw]
    if isinstance(raw, str):
        return [part for part in raw.replace(",", " ").split() if part]
    return []


def flatten(
    node: Any, prefix: str = "", indexed: bool = True
) -> Iterator[tuple[str, Any]]:
    """Every leaf of a document as `(dotted path, value)`.

    Lists of tables — the route table is the one that matters — are indexed so
    that each route is a line of its own; a list of scalars stays one value,
    rendered as JSON, because that is how it was written and how it reads back.
    `indexed=False` is `leaves`: one walk with the one difference the two
    callers need, rather than two walks to keep in step.
    """
    if isinstance(node, dict):
        for key in sorted(node):
            yield from flatten(node[key], "%s%s." % (prefix, key), indexed)
        return
    if (
        indexed
        and isinstance(node, list)
        and node
        and all(isinstance(item, dict) for item in node)
    ):
        for index, item in enumerate(node):
            yield from flatten(item, "%s[%d]." % (prefix[:-1], index), indexed)
        return
    yield prefix[:-1], node


def leaves(node: dict[str, Any]) -> Iterator[str]:
    """The paths a layer wrote, for `sources`: `flatten` with lists unindexed.

    A layer's `[[route]]` array is one leaf — `route` — because that is what the
    layer wrote and what `sources` is keyed by. `show` is the caller that wants
    its entries, and its paths, apart.
    """
    for path, _ in flatten(node, indexed=False):
        yield path


def _render(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(_render(item) for item in value)
    if isinstance(value, dict):
        return json.dumps(value, sort_keys=True)
    return str(value)


# --- the machine ------------------------------------------------------------
#
# The two questions `doctor` puts to something other than the document, both
# through a stub in the test suite the way `herdr` itself is: what kinds this
# `herdr` takes, and which launchers the shell a pane is started in defines.


def _herdr_kinds() -> set[str] | None:
    """The `--kind` values this machine's `herdr` offers, or None.

    Read out of its own help, and only out of the `--kind` option's own block:
    the list of values a flag takes is the flag's, and a second `[possible
    values: …]` elsewhere in the text is another option's. None means this
    `herdr` would not say, which is a note rather than a finding — the shape of
    a help text is not a promise this file can hold it to.
    """
    herdr = shutil.which("herdr")
    if herdr is None:
        return None
    try:
        done = subprocess.run(
            [herdr, "agent", "start", "--help"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    inside = False
    for line in (done.stdout + done.stderr).splitlines():
        if re.match(r"\s*--kind\b", line):
            inside = True
            continue
        if not inside:
            continue
        found = re.search(r"\[possible values:\s*([^\]]*)\]", line)
        if found:
            return {name.strip() for name in found.group(1).split(",") if name.strip()}
    return None


def _shell_defines(names: list[str], env: dict[str, str]) -> dict[str, bool] | None:
    """Which of `names` the shell a pane is started in knows, or None.

    One `zsh -ic`, because that is what `spawn` runs to start a pane: `-i` so
    the rc that defines the launcher functions is read, and the environment the
    caller is working in so the answer is about this machine. `whence -w`
    answers one line per name — `<name>: function`, `: command`, `: none` — and
    answers for every name even when one is unknown, which is why the exit
    status is not consulted.
    """
    zsh = shutil.which("zsh")
    if zsh is None:
        return None
    script = "whence -w -- " + " ".join(shlex.quote(name) for name in names)
    try:
        done = subprocess.run(
            [zsh, "-ic", script], capture_output=True, text=True, env=env, timeout=30
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    answers = {name: False for name in names}
    for line in done.stdout.splitlines():
        name, _, kind = line.partition(":")
        if name.strip() in answers:
            answers[name.strip()] = kind.strip() not in ("", "none")
    return answers


# --- the command line -------------------------------------------------------


def _extract_repo(args: list[str]) -> tuple[list[str], str | None]:
    """Pull a `--repo <path>` out of `args`, if there is one.

    Returns the remaining arguments and the path, so a caller keeps checking
    the rest of its own arguments for anything else it does not recognise —
    `--repo` is not a verb-specific option, and every verb that takes it takes
    it the same way.
    """
    out: list[str] = []
    repo: str | None = None
    i = 0
    while i < len(args):
        if args[i] == "--repo":
            if i + 1 >= len(args):
                raise ConfigError("--repo", "needs a path")
            repo = args[i + 1]
            i += 2
            continue
        out.append(args[i])
        i += 1
    return out, repo


def main(argv: list[str]) -> int:
    if not argv:
        sys.stderr.write("usage: config <env|show|get|lint|resolve|route|doctor>\n")
        return 2
    verb, rest = argv[0], argv[1:]
    try:
        if verb == "lint":
            rest, repo = _extract_repo(rest)
            findings = load(repo=repo).lint()
            for finding in findings:
                print("config: %s" % finding)
            if not findings:
                print("config: ok")
            return 1 if findings else 0
        if verb == "doctor":
            if rest:
                sys.stderr.write("usage: config doctor\n")
                return 2
            findings, notes = load().doctor()
            for finding in findings:
                print("config: %s" % finding)
            for note in notes:
                print("config: note: %s" % note)
            if not findings and not notes:
                print("config: ok")
            return 1 if findings else 0
        if verb == "show":
            rest, repo = _extract_repo(rest)
            unknown = [arg for arg in rest if arg != "--sources"]
            if unknown:
                sys.stderr.write("config show: unknown option %s\n" % " ".join(unknown))
                return 2
            for line in load(repo=repo).show("--sources" in rest):
                print(line)
            return 0
        if verb == "env":
            rest, repo = _extract_repo(rest)
            if rest:
                sys.stderr.write("usage: config env [--repo <path>]\n")
                return 2
            for line in load(repo=repo).env_lines():
                print(line)
            return 0
        if verb == "get":
            rest, repo = _extract_repo(rest)
            if len(rest) != 1:
                sys.stderr.write("usage: config get <dotted.key> [--repo <path>]\n")
                return 2
            config = load(repo=repo)
            config.clean()
            if document_value(config.document, rest[0]) is None:
                sys.stderr.write(
                    "config get: no %s — `config show` lists what there is\n" % rest[0]
                )
                return 1
            print(_render(config.get(rest[0])))
            return 0
        if verb == "resolve":
            if rest == ["profiles"]:
                for line in load().profiles_table():
                    print(line)
                return 0
            if len(rest) != 2 or rest[0] != "profile":
                sys.stderr.write(
                    "usage: config resolve profile <name> | config resolve profiles\n"
                )
                return 2
            for key, value in load().profile(rest[1]).items():
                print("%s=%s" % (key, shlex.quote(value)))
            return 0
        if verb == "route":
            if len(rest) != 1:
                sys.stderr.write("usage: config route '<row-json>'\n")
                return 2
            row = json.loads(rest[0]) if rest[0].strip() not in ("", "-") else {}
            for key, value in load().route(row).items():
                print("%s=%s" % (key, shlex.quote(value)))
            return 0
    except ConfigError as exc:
        sys.stderr.write("config: %s\n" % exc)
        return 1
    except json.JSONDecodeError as exc:
        sys.stderr.write("config route: not JSON: %s\n" % exc)
        return 2
    sys.stderr.write("config: unknown verb %s\n" % verb)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
