"""Parse checks for tracked files: conflict markers, size, JSON(C) and TOML.

Usage: hygiene.py PATH...

Prints `path:line: reason` for each finding and exits 1 when there is one.
Symlinks, missing paths and binary files are skipped.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import List, Optional, Tuple

MAX_BYTES = 1024 * 1024
Finding = Tuple[str, int, str]


def strip_jsonc(text: str) -> str:
    """Blank out // and /* */ comments outside strings, keeping line numbers."""
    out: List[str] = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("unterminated /* comment")
            for ch in text[i : end + 2]:
                out.append("\n" if ch == "\n" else " ")
            i = end + 2
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def is_jsonc(path: str) -> bool:
    parts = path.replace(os.sep, "/").split("/")
    return path.endswith(".jsonc") or (len(parts) >= 2 and parts[-2] == "vscode")


def check_json(path: str, text: str) -> Optional[Tuple[int, str]]:
    try:
        json.loads(strip_jsonc(text) if is_jsonc(path) else text)
    except json.JSONDecodeError as exc:
        return exc.lineno, "invalid JSON: %s" % exc.msg
    except ValueError as exc:
        return 1, "invalid JSON: %s" % exc
    return None


if sys.version_info >= (3, 11):
    import tomllib

    def check_toml(text: str) -> Optional[Tuple[int, str]]:
        try:
            tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            found = re.search(r"line (\d+)", str(exc))
            return (int(found.group(1)) if found else 1), "invalid TOML: %s" % exc
        return None

else:

    def check_toml(text: str) -> Optional[Tuple[int, str]]:
        raise RuntimeError("tomllib needs Python >= 3.11")


def conflict_markers(text: str) -> List[Tuple[int, str]]:
    found: List[Tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), 1):
        if (
            line.startswith("<<<<<<< ")
            or line.rstrip() == "======="
            or line.startswith(">>>>>>> ")
        ):
            found.append((number, "conflict marker"))
    return found


def check_file(path: str) -> List[Finding]:
    if os.path.islink(path) or not os.path.isfile(path):
        return []
    with open(path, "rb") as handle:
        data = handle.read()
    if b"\0" in data[:8192]:
        return []
    if len(data) > MAX_BYTES:
        return [(path, 1, "file is over 1 MiB (%d bytes)" % len(data))]
    text = data.decode("utf-8", errors="replace")
    found = [(path, n, why) for n, why in conflict_markers(text)]
    problem: Optional[Tuple[int, str]] = None
    if path.endswith((".json", ".jsonc")):
        problem = check_json(path, text)
    elif path.endswith(".toml"):
        problem = check_toml(text)
    if problem:
        found.append((path, problem[0], problem[1]))
    return found


def main(argv: List[str]) -> int:
    if sys.version_info >= (3, 11):
        findings: List[Finding] = []
        for path in argv:
            findings.extend(check_file(path))
        for path, line, why in findings:
            print("%s:%d: %s" % (path, line, why))
        return 1 if findings else 0
    sys.stderr.write("hygiene: Python >= 3.11 required\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
