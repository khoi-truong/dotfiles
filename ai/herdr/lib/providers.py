"""`ai/providers.toml` — the credential registry, and the checkout's TOML reader.

One entry per *credential*, not per agent CLI and not per model. That is the
distinction the rest of this checkout turns on: the ceiling counts panes per
provider entry, because two profiles that share a key share a budget, and a key
is what an entry describes. ai/herdr/team.toml's profiles name an entry through
their `credential` field and never restate one, so a key moves in one place.

Three readers, none of which parses TOML itself:

  * `herdr_team.config` — lint and doctor, which check a profile's
    `credential` resolves and that the ceiling is a number
  * ai/claude/providers.zsh — through a cache regenerated from here, because a
    shell start may not spend a subprocess on parsing
  * `team.sh` — never directly; `config env` and `config resolve` are the only
    shapes it reads

`read_toml` is shared with `herdr_team.config` rather than duplicated, so a
file that will not parse is reported the same way whichever layer it is:
`<path>:<line>:<column>: <reason>`, which is what makes a broken
`team.local.toml` name its own line instead of failing as a bare traceback.

Run as `python3 -m providers <verb>` with `lib/` on PYTHONPATH:

    get <name>            one entry as `key=value` lines, dotted, shell-quoted
    lint                  schema findings for the registry, one per line
    zsh                   the `cc_provider` calls the launcher cache holds
    launch-args <p> <h>   argv words injecting provider <p> into harness <h>
"""

from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path
from typing import Any

if sys.version_info >= (3, 11):  # pragma: no cover - taken on 3.11 and up
    import tomllib
else:  # pragma: no cover - taken on the 3.9 `/usr/bin/python3` team.sh runs
    from _vendor import tomli as tomllib

__all__ = [
    "ENTRY_KEYS",
    "PROTOCOLS",
    "RegistryError",
    "TOML",
    "get",
    "launch_args",
    "lint",
    "load",
    "main",
    "read_toml",
    "serves",
    "zsh",
]

# This file's own directory, `lib/`, which is also where `_vendor` lives: it is
# the one path every caller already has — `team.sh` sets PYTHONPATH to it,
# pytest's config names the same, and the cache generator in providers.zsh
# passes it explicitly — so the two imports above need no path of their own.
_LIB = Path(__file__).resolve().parent

# ai/providers.toml, two levels up from `lib/`, through `herdr/`.
TOML = _LIB.parents[1] / "providers.toml"

# A url and a key, a url and a key, or neither. `anthropic` and `openai` are
# wire protocols this checkout can inject into a launch; `login` is a
# subscription or an OAuth session held by the CLI itself, which has no url to
# point at and no key to read, and which is also why a `login` entry cannot be
# proxied or fallen back onto from a keyed one.
PROTOCOLS = ("anthropic", "openai", "login")

ENTRY_KEYS = frozenset(
    {
        "protocol",
        "url",
        "key",
        "models",
        "ceiling",
        "quota",
        "launcher",
        "harnesses",
        "enabled",
    }
)

# What a top-level key of the file may be. Nothing else belongs in a registry
# that team.sh reads on every spawn.
ROOT_KEYS = frozenset({"schema", "provider"})

# `key` names where a secret is *read*, never the secret. Both forms here are
# resolvable by a launcher: ai/claude/providers.zsh reads `env:` out of the
# environment and `op://` out of 1Password.
KEY_REFS = ("env:", "op://")

# cc_provider's own rule in ai/claude/providers.zsh, restated here because a
# short that fails it is a launcher that never gets defined.
SHORT_RE = re.compile(r"^[a-z0-9]+$")

_LINE_RE = re.compile(r"\(at line (\d+), column (\d+)\)")


class RegistryError(ValueError):
    """A registry that could not be read, as `path:line:col: reason`.

    One exception for both kinds of failure — a file that will not parse and a
    file that parses but says something impossible — because every caller does
    the same thing with either: refuse to start, and print this. `line` and
    `column` are None for a failure that is not about a position.
    """

    def __init__(
        self, path: Any, reason: str, line: int | None = None, column: int | None = None
    ) -> None:
        self.path = str(path)
        self.reason = reason
        self.line = line
        self.column = column
        where = self.path
        if line is not None:
            where += ":%d" % line
            if column is not None:
                where += ":%d" % column
        super().__init__("%s: %s" % (where, reason))


def read_toml(path: Any) -> dict[str, Any]:
    """The TOML document at `path`, raising `RegistryError` with its position.

    The position matters more than the reason: `team.local.toml` is edited by
    hand, on this machine only, and a caller who is told which line is wrong can
    fix it. `tomli` carries `lineno`/`colno` as attributes; the standard
    library's copy embeds them in the message and only grew attributes in 3.14,
    so both are read here.
    """
    path = Path(path)
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        raise RegistryError(path, "no such file") from None
    except tomllib.TOMLDecodeError as exc:
        line = getattr(exc, "lineno", None)
        column = getattr(exc, "colno", None)
        if line is None:
            found = _LINE_RE.search(str(exc))
            if found:
                line, column = int(found.group(1)), int(found.group(2))
        reason = str(exc).split("(at line")[0].strip() or "invalid TOML"
        raise RegistryError(path, reason, line, column) from None


def load(path: Any = None) -> dict[str, dict[str, Any]]:
    """The `[provider.<name>]` entries at `path`, keyed by name.

    The schema is *not* checked here. A reader that refused an unknown key
    would make `config doctor` fail on a file `config lint` had not yet named,
    and the two are asked separately on purpose: lint is a schema claim, doctor
    is a claim about this machine.
    """
    document = read_toml(TOML if path is None else path)
    unknown = sorted(set(document) - ROOT_KEYS)
    if unknown:
        raise RegistryError(
            TOML if path is None else path,
            "unknown key %s — this file holds only `schema` and `[provider.*]`"
            % ", ".join(unknown),
        )
    entries: dict[str, dict[str, Any]] = document.get("provider") or {}
    return entries


def get(name: str, path: Any = None) -> dict[str, Any]:
    """One entry, or `RegistryError` naming what the registry does hold."""
    entries = load(path)
    if name not in entries:
        raise RegistryError(
            TOML if path is None else path,
            "no provider %r — the registry holds %s"
            % (name, ", ".join(sorted(entries)) or "nothing"),
        )
    return entries[name]


def enabled(entry: dict[str, Any]) -> bool:
    """Whether a pane may be launched on this credential today.

    Absent means enabled: a new entry is usable the moment it is written, and
    the entries whose launch injection is unverified have to say so out loud.
    """
    return bool(entry.get("enabled", True))


def serves(entry: dict[str, Any], harness: str = "claude") -> bool:
    """Whether this credential is one `harness` may be launched on.

    Absent `harnesses` means claude, and only claude: every entry written
    before the field existed is a `cc_provider` launcher, and the ones that
    serve something else say so — `deepseek-omp` is omp's key, `anthropic-pro`
    is the login the plain `claude` command uses. A `harnesses` that is not a
    list falls back to the same default rather than matching a substring of
    whatever was written there; `lint` is what names it.
    """
    harnesses = entry.get("harnesses")
    if not isinstance(harnesses, list):
        harnesses = ["claude"]
    return harness in harnesses


def flatten(entry: dict[str, Any], prefix: str = "") -> list[tuple[str, str]]:
    """An entry as `(dotted key, value)` pairs, in a stable order.

    Dotted rather than nested because the one consumer that is not Python — a
    shell reading `providers get <name>` — has no nesting, and because a flat
    list is what makes the output diffable between two machines.
    """
    pairs: list[tuple[str, str]] = []
    for key in sorted(entry):
        value = entry[key]
        name = "%s%s" % (prefix, key)
        if isinstance(value, dict):
            pairs.extend(flatten(value, "%s." % name))
        elif isinstance(value, list):
            pairs.append((name, " ".join(str(item) for item in value)))
        else:
            pairs.append((name, _scalar(value)))
    return pairs


def _scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def lint(
    path: Any = None, entries: dict[str, dict[str, Any]] | None = None
) -> list[str]:
    """Schema findings for the registry, as `provider.<name>: <what>` strings.

    Every rule here is one this checkout would otherwise fail on later, in a
    place that cannot say which file to edit: a launcher that never gets
    defined, a `cc_provider` call with no model, a ceiling that is a string and
    stops comparing as a number.
    """
    if entries is None:
        entries = load(path)
    found: list[str] = []
    for name in sorted(entries):
        entry = entries[name]
        where = "provider.%s" % name
        found.extend("%s: %s" % (where, reason) for reason in _lint_entry(entry))
    return found


def _lint_entry(entry: dict[str, Any]) -> list[str]:
    found: list[str] = []
    unknown = sorted(set(entry) - ENTRY_KEYS)
    if unknown:
        found.append("unknown key %s" % ", ".join(unknown))

    protocol = entry.get("protocol")
    if protocol is None:
        found.append("no protocol — every entry says how it is reached")
    elif protocol not in PROTOCOLS:
        found.append("protocol %r is not one of %s" % (protocol, ", ".join(PROTOCOLS)))

    if protocol == "login":
        # A login has nothing to inject. Saying otherwise would leave a url in
        # the file that no launch reads, which is worse than absent: it reads
        # as a provider that could be proxied or fallen back onto.
        for key in ("url", "key"):
            if entry.get(key):
                found.append(
                    "%s is set on a `login` entry — a login has no url and no "
                    "key to inject; the CLI holds the session" % key
                )
    # A url is not required of a keyed entry, and that is the point of the
    # field being optional: `deepseek-omp` is a credential omp holds and reads
    # through its own config, and what this file records about it is the
    # ceiling, not the plumbing. An entry with no url is simply never emitted
    # as a `cc_provider` call — see the launcher rule below, which is where the
    # three fields are actually required.
    url = entry.get("url")
    if url is not None and (not isinstance(url, str) or not url):
        found.append("url must be a non-empty string")
    ref = entry.get("key")
    if ref is not None and (not isinstance(ref, str) or not ref.startswith(KEY_REFS)):
        found.append(
            "key %r is not a reference — use env:VAR (ai/env.local.zsh) or "
            "op://… (1Password); a secret written here is a secret in git" % ref
        )

    found.extend(_lint_models(entry.get("models")))
    found.extend(_lint_ceiling(entry.get("ceiling")))
    found.extend(_lint_quota(entry.get("quota")))
    found.extend(_lint_launcher(entry))
    found.extend(_lint_harnesses(entry.get("harnesses")))
    if "enabled" in entry and not isinstance(entry["enabled"], bool):
        found.append("enabled must be true or false")
    return found


def _lint_models(models: Any) -> list[str]:
    if models is None:
        return []
    if not isinstance(models, dict):
        return ["models must be a table of name → model id"]
    found = []
    for key in sorted(models):
        if not isinstance(models[key], str) or not models[key]:
            found.append("models.%s must be a model id" % key)
    return found


def _lint_ceiling(ceiling: Any) -> list[str]:
    if ceiling is None:
        return []
    if not _is_executable_int(ceiling) or ceiling < 1:
        return ["ceiling must be a whole number of 1 or more"]
    return []


def _lint_quota(quota: Any) -> list[str]:
    if quota is None:
        return []
    if not isinstance(quota, dict):
        return ["quota must be a table"]
    found = []
    unknown = sorted(set(quota) - {"cache", "max_age_s"})
    if unknown:
        found.append("quota: unknown key %s" % ", ".join(unknown))
    cache = quota.get("cache")
    if not isinstance(cache, str) or not cache:
        found.append("quota.cache must be a path")
    if not _is_executable_int(quota.get("max_age_s")) or quota["max_age_s"] < 1:
        found.append("quota.max_age_s must be a whole number of seconds, 1 or more")
    return found


def _lint_launcher(entry: dict[str, Any]) -> list[str]:
    launcher = entry.get("launcher")
    if launcher is None:
        return []
    if not isinstance(launcher, dict):
        return ["launcher must be a table"]
    found = []
    unknown = sorted(set(launcher) - {"short", "label"})
    if unknown:
        found.append("launcher: unknown key %s" % ", ".join(unknown))
    short = launcher.get("short")
    if short is None:
        return found
    if not isinstance(short, str) or not SHORT_RE.match(short):
        return found + ["launcher.short %r is not [a-z0-9]+" % short]
    # A `cc_provider` call needs all three of url, key and model, so an entry
    # with a launcher and any of them missing is a launcher this file promises
    # and nothing will ever define. Checked here rather than discovered as a
    # missing command in a shell.
    for key, why in (
        ("url", "cc_provider has nowhere to point"),
        ("key", "cc_provider has no key ref to resolve"),
    ):
        if not entry.get(key):
            found.append("launcher.short %s needs a %s — %s" % (short, key, why))
    models = entry.get("models")
    default = models.get("default") if isinstance(models, dict) else None
    if not default:
        found.append(
            "launcher.short %s needs models.default — cc_provider requires a model"
            % short
        )
    return found


def _lint_harnesses(harnesses: Any) -> list[str]:
    if harnesses is None:
        return []
    if not isinstance(harnesses, list) or not all(
        isinstance(item, str) and item for item in harnesses
    ):
        return ["harnesses must be a list of agent CLI names"]
    return []


def zsh(path: Any = None) -> str:
    """The `cc_provider` calls that define the launchers, as shell source.

    This is the launcher cache, and why it exists at all: a shell start may not
    spend a subprocess reading TOML, so ai/claude/providers.zsh compares mtimes
    and calls `providers.py zsh` only when the registry or this generator moved.
    What comes out therefore has to be exactly what the hand-written calls at
    the bottom of that file used to be — one call per provider, nothing else —
    and the two readers of the registry (this file and that cache) get their
    definition from the same place instead of from two copies.

    Emitted: every enabled entry with a `launcher`, in file order, because the
    file's order is one a human chose and `cc-providers` lists providers in it.
    Skipped: a disabled entry, whose launcher deliberately does not exist yet,
    and an entry that defines no launcher at all — `deepseek-omp` and
    `anthropic-pro` are credentials nothing launches through `cc_provider`, and
    `deepseek-omp` has no `url` to be injected through anyway. An entry that has
    a launcher and cannot be turned into a working call raises instead of being
    written out: the cache is sourced by every new shell, and a `cc_provider`
    line that reports a missing field on every start is worse than the one
    warning the caller prints when this fails.
    """
    entries = load(path)
    where = TOML if path is None else path
    lines = [
        "# Generated by `python3 -m providers zsh` — do not edit.",
        "# One `cc_provider` call per enabled launcher in ai/providers.toml, in",
        "# the order that file lists them. ai/claude/providers.zsh rewrites this",
        "# file whenever the registry or the generator is newer than it.",
        "#",
    ]
    for name, entry in entries.items():
        call = _launcher_call(name, entry, where)
        if call is not None:
            lines.append(call)
    return "\n".join(lines) + "\n"


def _launcher_call(name: str, entry: dict[str, Any], where: Any) -> str | None:
    """One `cc_provider` line, or None for an entry that defines no launcher.

    The lint rules are the ones applied here, not a second set: what a launcher
    needs — a url, a key ref and a model — is the same claim `lint` makes, and
    a launcher that cannot be written is a command this file would otherwise
    promise to a shell and never define.
    """
    launcher = entry.get("launcher")
    if not enabled(entry) or not isinstance(launcher, dict):
        return None
    short = launcher.get("short")
    if not short:
        return None
    if not serves(entry, "claude"):
        # A launcher is a `cc_provider` call, and `cc_provider` defines claude
        # commands. An entry for another harness has no url to inject anyway.
        return None
    findings = _lint_entry(entry)
    if findings:
        raise RegistryError(
            where,
            "provider.%s cannot be a launcher: %s" % (name, "; ".join(findings)),
        )
    fields: list[tuple[str, Any]] = [("url", entry["url"]), ("key", entry["key"])]
    # `models.default` is the field `cc_provider` calls `model`; any other key
    # in the table passes through under its own name, which is how `small` and
    # `pro` reach `_cc_run` without this file keeping a second vocabulary.
    models = entry.get("models")
    for key, value in (models if isinstance(models, dict) else {}).items():
        fields.append(("model" if key == "default" else key, value))
    if launcher.get("label"):
        fields.append(("label", launcher["label"]))
    fields.append(("short", short))
    return "cc_provider %s %s" % (
        name,
        " ".join("%s=%s" % (key, shlex.quote(str(value))) for key, value in fields),
    )


def launch_args(name: str, harness: str = "claude", path: Any = None) -> list[str]:
    """The argv words that inject provider `name` into a launch of `harness`.

    One pair is answered, and it is the pair that exists today: a provider
    served to Claude Code, whose injection is the `ANTHROPIC_*` environment
    `_cc_run` exports from this same entry. So the answer is no words at all —
    the environment is the whole injection, and a caller appends what it gets
    to the command line it already has. `cc_provider` and this function read
    one entry, so a launch and a key probe cannot disagree about an endpoint.

    Every other pair refuses. What each remaining harness would take is written
    down in the plan (codex's dotted `-c model_providers.…`, opencode's
    `OPENCODE_CONFIG_CONTENT`, omp's second `--config`) and every one of those
    is marked unverified there; an argument guessed here is a launch pointed at
    an endpoint nobody has tried, which in an unattended pane fails as a hang
    rather than as an error. Refusing is also what keeps `enabled = false` on
    those entries meaningful: nothing can launch on one by accident.
    """
    entry = get(name, path)
    where = TOML if path is None else path
    if not enabled(entry):
        raise RegistryError(
            where,
            "provider %s is disabled — no launcher for it is defined, and "
            "turning one on is a spike plus a one-word edit, not a thing to "
            "arrange here" % name,
        )
    harnesses = entry.get("harnesses")
    if not serves(entry, harness):
        raise RegistryError(
            where,
            "provider %s does not serve %s — it serves %s"
            % (
                name,
                harness,
                ", ".join(str(item) for item in harnesses) if harnesses else "claude",
            ),
        )
    if harness != "claude":
        raise RegistryError(
            where,
            "provider %s serves %s, but nothing here records how %s is given a "
            "provider: only claude is injected, through the ANTHROPIC_* "
            "environment, and the rest of that plumbing is unverified upstream"
            % (name, harness, harness),
        )
    return []


def _is_executable_int(value: Any) -> bool:
    """True for an int, and for a bool-free int only.

    `isinstance(True, int)` is True in Python, and TOML has no `true = 1`, so a
    ceiling written as `ceiling = true` would compare as 1 and read as a limit
    nobody set. It is excluded here rather than at each comparison.
    """
    return isinstance(value, int) and not isinstance(value, bool)


def main(argv: list[str]) -> int:
    if not argv:
        sys.stderr.write(__doc__ or "")
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "get":
        if len(rest) != 1:
            sys.stderr.write("usage: providers get <name>\n")
            return 2
        try:
            entry = get(rest[0])
        except RegistryError as exc:
            sys.stderr.write("providers: %s\n" % exc)
            return 1
        for key, value in flatten(entry):
            print("%s=%s" % (key, shlex.quote(value)))
        return 0
    if verb == "lint":
        findings = lint()
        for finding in findings:
            print("providers: %s" % finding)
        if not findings:
            print("%s: ok" % TOML)
        return 1 if findings else 0
    if verb == "zsh":
        if rest:
            sys.stderr.write("usage: providers zsh\n")
            return 2
        try:
            sys.stdout.write(zsh())
        except RegistryError as exc:
            sys.stderr.write("providers: %s\n" % exc)
            return 1
        return 0
    if verb == "launch-args":
        if len(rest) not in (1, 2):
            sys.stderr.write("usage: providers launch-args <name> [<harness>]\n")
            return 2
        try:
            words = launch_args(rest[0], rest[1] if len(rest) == 2 else "claude")
        except RegistryError as exc:
            sys.stderr.write("providers: %s\n" % exc)
            return 1
        # Shell-quoted words, one line, empty when there is nothing to inject:
        # the caller is building a command line, and `get` already answers in
        # the same form.
        print(" ".join(shlex.quote(word) for word in words))
        return 0
    sys.stderr.write("providers: unknown verb %s\n" % verb)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
