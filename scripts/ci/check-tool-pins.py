#!/usr/bin/env python3
"""Fail when a tool version pinned in CI differs from mise.

mise.toml and mise/global.toml are the source of truth. This reads the
versions the workflows install and compares them. Run by lint.yml's `python`
job and by scripts/ci/lint-local.sh.
"""

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def mise_pins() -> dict[str, str]:
    pins: dict[str, str] = {}
    for name in ("mise.toml", "mise/global.toml"):
        with open(ROOT / name, "rb") as f:
            tools = tomllib.load(f)["tools"]
        for tool in ("ruff", "editorconfig-checker", "uv", "shellcheck"):
            if tool in tools and not (tool == "uv" and name == "mise/global.toml"):
                pins[tool] = tools[tool]
    return pins


# tool -> (workflow file, regex whose group 1 is the pinned version).
# Every match must agree with mise.
SOURCES = {
    "uv": [
        (".github/workflows/lint.yml", r'UV_VERSION:\s*"([^"]+)"'),
        (".github/workflows/test.yml", r'UV_VERSION:\s*"([^"]+)"'),
    ],
    "ruff": [(".github/workflows/lint.yml", r"\bruff@([0-9][^\s]*)")],
    "editorconfig-checker": [
        (
            ".github/workflows/lint.yml",
            r"editorconfig-checker/releases/download/v([^/]+)/",
        )
    ],
    "shellcheck": [(".github/workflows/lint.yml", r'SHELLCHECK_VERSION:\s*"([^"]+)"')],
}


def main() -> int:
    pins = mise_pins()
    bad = 0
    for tool, sources in SOURCES.items():
        want = pins.get(tool)
        if want is None:
            print(f"check-tool-pins: {tool} is not pinned in mise", file=sys.stderr)
            bad += 1
            continue
        for path, pattern in sources:
            found = re.findall(pattern, (ROOT / path).read_text())
            if not found:
                print(f"check-tool-pins: no {tool} pin found in {path}", file=sys.stderr)
                bad += 1
            for got in found:
                if got != want:
                    print(
                        f"check-tool-pins: {tool} is {got} in {path}, mise pins {want}",
                        file=sys.stderr,
                    )
                    bad += 1
    if not bad:
        print("check-tool-pins: workflow pins match mise")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
