#!/usr/bin/env python3
"""Fail when a tool version pinned in CI differs from mise.

mise.toml and mise/global.toml are the source of truth for tools, and
pyproject.toml's dev group for pytest. This reads the versions the workflows
and lint-local.sh install and compares them. Run by lint.yml's `python` job and
by scripts/ci/lint-local.sh.
"""

import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(
        "check-tool-pins: needs Python 3.11+ (tomllib); run it under mise's python"
    )

ROOT = Path(__file__).resolve().parents[2]


def load(name: str) -> dict:
    with open(ROOT / name, "rb") as f:
        return tomllib.load(f)


def pins() -> dict[str, str]:
    found: dict[str, str] = {}
    # Global first, so the repo's mise.toml wins, as it does for mise itself.
    for name in ("mise/global.toml", "mise.toml"):
        found.update(load(name).get("tools", {}))
    for dep in load("pyproject.toml")["dependency-groups"]["dev"]:
        name, sep, version = dep.partition("==")
        if sep:
            found[name] = version
    return found


# tool -> (workflow file, regex whose group 1 is the pinned version).
# Every match must agree with mise.
SOURCES = {
    "uv": [
        (".github/workflows/lint.yml", r'UV_VERSION:\s*"([^"]+)"'),
        (".github/workflows/test.yml", r'UV_VERSION:\s*"([^"]+)"'),
    ],
    "ruff": [
        (".github/workflows/lint.yml", r"\bruff@([0-9][^\s]*)"),
        ("scripts/ci/lint-local.sh", r"\bruff@([0-9][^\s]*)"),
    ],
    "editorconfig-checker": [
        (
            ".github/workflows/lint.yml",
            r"editorconfig-checker/releases/download/v([^/]+)/",
        ),
        ("scripts/ci/lint-local.sh", r"^EC_VERSION=v(\S+)"),
    ],
    "shellcheck": [(".github/workflows/lint.yml", r'SHELLCHECK_VERSION:\s*"([^"]+)"')],
    "shfmt": [(".github/workflows/lint.yml", r'SHFMT_VERSION:\s*"([^"]+)"')],
    "stylua": [
        (".github/workflows/lint.yml", r'STYLUA_VERSION:\s*"([^"]+)"'),
        ("scripts/ci/lint-local.sh", r"^STYLUA_VERSION=(\S+)"),
    ],
    "rumdl": [
        (".github/workflows/lint.yml", r"\brumdl@([0-9][^\s]*)"),
        ("scripts/ci/lint-local.sh", r"\brumdl@([0-9][^\s]*)"),
    ],
    "gitleaks": [
        (".github/workflows/secrets.yml", r"GITLEAKS_VERSION:\s*\"?([0-9][^\s\"]*)")
    ],
    "pytest": [
        (".github/workflows/test.yml", r"\bpytest@([0-9][^\s]*)"),
        (".github/workflows/lint.yml", r"\bpytest==([0-9][^\s]*)"),
        ("scripts/ci/lint-local.sh", r"\bpytest==([0-9][^\s]*)"),
        ("scripts/ci/lint-local.sh", r"\bpytest@([0-9][^\s]*)"),
    ],
}


def main() -> int:
    pinned = pins()
    bad = 0
    for tool, sources in SOURCES.items():
        want = pinned.get(tool)
        if want is None:
            print(
                f"check-tool-pins: {tool} is not pinned in mise or pyproject.toml",
                file=sys.stderr,
            )
            bad += 1
            continue
        for path, pattern in sources:
            found = re.findall(pattern, (ROOT / path).read_text(), re.MULTILINE)
            if not found:
                print(
                    f"check-tool-pins: no {tool} pin found in {path}", file=sys.stderr
                )
                bad += 1
            for got in found:
                if got != want:
                    print(
                        f"check-tool-pins: {tool} is {got} in {path}, the source pins {want}",
                        file=sys.stderr,
                    )
                    bad += 1
    if not bad:
        print("check-tool-pins: workflow pins match mise and pyproject.toml")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
