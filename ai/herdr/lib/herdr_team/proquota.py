"""The reader of the Pro 5h window `spawn` decides a fallback against.

The same cache `ai/claude/quota-advice.sh` advises from, read by the same rule
stated as a rule rather than as one comparison that happens to hold. Every
answer is a number or "unknown": no cache, an unreadable cache and a stale one
all answer unknown, because the absence of a number is not headroom.
"""

from __future__ import annotations

import json
import sys
import time
from typing import Any

__all__ = ["cache_window_used", "window_used", "main"]


def window_used(data: Any, now: float, max_age: int) -> int | None:
    """The used percentage of the cached 5h window, or None when it is not one.

    `now` and `max_age` arrive rather than being read here so the three
    refusals — a window already reset, a cache stamped in the future, and a
    cache older than the caller allows — are decided from arguments a test can
    state, instead of from this machine's clock.
    """
    try:
        five = data["rate_limits"]["five_hour"]
        used = float(five["used_percentage"])
        reset = float(five["resets_at"])
        cached = float(data["cached_at"])
    except (ValueError, KeyError, TypeError):
        return None
    age = now - cached
    if reset <= now or age < 0 or age > max_age:
        return None
    return int(used)


def cache_window_used(path: str, max_age: int) -> int | None:
    """`window_used` over the cache at `path`, or None when there is none."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return window_used(data, time.time(), max_age)


def main(argv: list[str]) -> int:
    # A limit that is not a number is not a limit. `spawn` gates on this before
    # it gets here; answering "unknown" is the same refusal from the other
    # side, and the only one this reader can make on its own.
    try:
        path, max_age = argv[0], int(argv[1])
    except ValueError:
        return 0
    used = cache_window_used(path, max_age)
    if used is not None:
        print(used)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
