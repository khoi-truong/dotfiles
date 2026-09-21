"""Third-party packages vendored into the checkout, imported as `_vendor.<x>`.

`team.sh` runs whatever `python3` is first on PATH, and on macOS that is
`/usr/bin/python3` — 3.9. Six years after the release that added `tomllib`,
that interpreter is still the one a fresh shell reaches, so the TOML reader
this checkout needs at runtime lives here rather than in a dependency: nothing
in this repo is installed, and a `pip install` would be one more step between
a fresh clone and a working verb. `lib/` is already on `PYTHONPATH` for every
verb `team.sh` runs, so `_vendor` needs no path of its own, and the same
import works on 3.9 and on 3.14.

Each vendored package keeps its own LICENSE and its version beside it.
Nothing in here is edited in place: a bump replaces the files.
"""
