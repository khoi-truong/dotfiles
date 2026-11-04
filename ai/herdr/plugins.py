"""Reader for ai/herdr/plugins.toml, the pinned herdr plugin manifest.

plugins.py rows [--manifest P]: TSV of enabled plugins (id, repo, ref, needs
comma-joined).

plugins.py check [--manifest P]: reads `herdr plugin list` on stdin and prints
drift lines. Exit 0 clean, 1 drift, 2 bad manifest.

--manifest defaults to $DOTFILES_HERDR_PLUGINS, then plugins.toml beside this
file. Needs Python 3.11+ (tomllib).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

KEYS = {"id", "repo", "ref", "needs", "enabled", "why"}
REQUIRED = ("id", "repo", "ref", "why")
REF_RE = re.compile(r"v\d+\.\d+\.\d+")
REPO_RE = re.compile(r"[\w.-]+/[\w.-]+")
LISTED_RE = re.compile(r"^- (\S+) .*\[([^\]]*)\]\s*$")


class ManifestError(Exception):
    pass


@dataclass(frozen=True)
class Plugin:
    id: str
    repo: str
    ref: str
    why: str
    needs: tuple[str, ...] = ()
    enabled: bool = True


if sys.version_info >= (3, 11):
    import tomllib

    def _toml(path: Path) -> dict[str, Any]:
        try:
            with path.open("rb") as handle:
                return tomllib.load(handle)
        except (OSError, tomllib.TOMLDecodeError) as err:
            raise ManifestError(str(err)) from err

else:

    def _toml(path: Path) -> dict[str, Any]:
        raise ManifestError("needs Python 3.11+ (tomllib)")


def _entry(index: int, raw: object) -> Plugin:
    if not isinstance(raw, dict):
        raise ManifestError(f"plugin[{index}]: not a table")
    ident = raw.get("id")
    label = ident if isinstance(ident, str) else f"plugin[{index}]"
    for key in raw:
        if key not in KEYS:
            raise ManifestError(f"{label}: unknown key {key!r}")
    for key in REQUIRED:
        if key not in raw:
            raise ManifestError(f"{label}: missing key {key!r}")
        if not isinstance(raw[key], str) or not raw[key]:
            raise ManifestError(f"{label}: {key!r} must be a non-empty string")
    if not REPO_RE.fullmatch(raw["repo"]):
        raise ManifestError(f"{label}: 'repo' must be owner/name, got {raw['repo']!r}")
    if not REF_RE.fullmatch(raw["ref"]):
        raise ManifestError(
            f"{label}: 'ref' must be a vMAJOR.MINOR.PATCH tag, got {raw['ref']!r}"
        )
    needs = raw.get("needs", [])
    if not isinstance(needs, list) or not all(isinstance(n, str) and n for n in needs):
        raise ManifestError(f"{label}: 'needs' must be a list of command names")
    enabled = raw.get("enabled", True)
    if not isinstance(enabled, bool):
        raise ManifestError(f"{label}: 'enabled' must be a boolean")
    return Plugin(
        id=raw["id"],
        repo=raw["repo"],
        ref=raw["ref"],
        why=raw["why"],
        needs=tuple(needs),
        enabled=enabled,
    )


def load(path: Path) -> list[Plugin]:
    data = _toml(path)
    for key in data:
        if key != "plugin":
            raise ManifestError(f"unknown top-level key {key!r}")
    entries = data.get("plugin", [])
    if not isinstance(entries, list):
        raise ManifestError("'plugin' must be an array of tables")
    plugins: list[Plugin] = []
    seen: set[str] = set()
    for index, raw in enumerate(entries):
        plugin = _entry(index, raw)
        if plugin.id in seen:
            raise ManifestError(f"{plugin.id}: duplicate id")
        seen.add(plugin.id)
        plugins.append(plugin)
    return plugins


def parse_listed(text: str) -> dict[str, tuple[str, str]]:
    listed: dict[str, tuple[str, str]] = {}
    for line in text.splitlines():
        match = LISTED_RE.match(line)
        if not match:
            continue
        source = match.group(2)
        repo, ref = "", ""
        if source.startswith("github:") and "@" in source:
            repo, ref = source[len("github:") :].split("@", 1)
        listed[match.group(1)] = (repo, ref)
    return listed


def drift(plugins: list[Plugin], listed: dict[str, tuple[str, str]]) -> list[str]:
    lines: list[str] = []
    for plugin in plugins:
        if not plugin.enabled:
            continue
        if plugin.id not in listed:
            lines.append(f"{plugin.id}: not installed")
            continue
        repo, ref = listed[plugin.id]
        if (repo, ref) != (plugin.repo, plugin.ref):
            lines.append(
                f"{plugin.id}: installed {repo}@{ref}, "
                f"manifest {plugin.repo}@{plugin.ref}"
            )
    return lines


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="plugins.py")
    parser.add_argument("command", choices=("rows", "check"))
    parser.add_argument(
        "--manifest",
        default=os.environ.get("DOTFILES_HERDR_PLUGINS")
        or str(Path(__file__).resolve().with_name("plugins.toml")),
    )
    args = parser.parse_args(argv)
    try:
        plugins = load(Path(args.manifest))
    except ManifestError as err:
        print(f"plugins.toml: {err}", file=sys.stderr)
        return 2
    if args.command == "rows":
        for plugin in plugins:
            if plugin.enabled:
                print(
                    "\t".join(
                        (plugin.id, plugin.repo, plugin.ref, ",".join(plugin.needs))
                    )
                )
        return 0
    problems = drift(plugins, parse_listed(sys.stdin.read()))
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
