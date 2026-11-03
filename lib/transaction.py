"""Journal and undo for the changes `link` makes under $HOME.

Run as `python3 -B lib/transaction.py <command> ...`:

    link SRC DST      symlink DST to SRC, moving whatever was at DST aside first
    backup PATH       move PATH aside (replaces `rm -R`)
    restore [ATTEMPT] undo an attempt, newest unrestored by default
    list              show attempts, newest first

An attempt is one top-level setup run (env DOTFILES_ATTEMPT). It lives in
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<attempt>/` as a
`manifest.jsonl` (one JSON object per change, written before the change) and a
`files/` directory holding everything moved aside. The directory is created on
the first real change only, so a run that changes nothing leaves no trace.
Nothing here ever prunes the journal.

Standard library only; must run on the Python 3.9 that ships with macOS.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import time
from typing import Any, Dict, List, Optional

MANIFEST = "manifest.jsonl"
RESTORED = "restored"
FILES = "files"

Entry = Dict[str, Any]


class Failure(Exception):
    """An expected failure: reported without a traceback, exit status 1."""


def warn(message: str) -> None:
    print("  \033[0;33m!\033[0m " + message, file=sys.stderr)


def tilde(path: str) -> str:
    home = os.path.expanduser("~").rstrip("/")
    if home and (path == home or path.startswith(home + "/")):
        return "~" + path[len(home) :]
    return path


def backups_root() -> str:
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(state, "dotfiles", "backups")


def attempt_name() -> str:
    name = os.environ.get("DOTFILES_ATTEMPT")
    if name:
        return name
    return "%s-%d" % (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), os.getpid())


def attempt_dir(name: Optional[str] = None) -> str:
    return os.path.join(backups_root(), name or attempt_name())


def kind_of(path: str) -> str:
    if os.path.islink(path):
        return "symlink"
    if os.path.isdir(path):
        return "dir"
    if os.path.lexists(path):
        return "file"
    return "none"


def move(src: str, dst: str) -> None:
    try:
        os.rename(src, dst)
    except OSError:
        shutil.move(src, dst)


def read_manifest(directory: str) -> List[Entry]:
    path = os.path.join(directory, MANIFEST)
    entries: List[Entry] = []
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    entries.append(json.loads(line))
    except FileNotFoundError:
        pass
    except ValueError as error:
        raise Failure("unreadable manifest %s: %s" % (path, error))
    return entries


def append_entry(directory: str, entry: Entry) -> None:
    os.makedirs(os.path.join(directory, FILES), exist_ok=True)
    with open(os.path.join(directory, MANIFEST), "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def stash(directory: str, dst: str) -> str:
    """Pick a unique name inside the attempt's files/ for the thing at dst."""
    files = os.path.join(directory, FILES)
    os.makedirs(files, exist_ok=True)
    seq = len(read_manifest(directory)) + 1
    while True:
        candidate = os.path.join(files, "%d-%s" % (seq, os.path.basename(dst)))
        if not os.path.lexists(candidate):
            return candidate
        seq += 1


def cmd_link(src: str, dst: str) -> int:
    dst = os.path.abspath(dst)
    if not os.path.lexists(src):
        warn("link: source missing, skipped: " + src)
        return 0
    if os.path.islink(dst) and os.readlink(dst) == src:
        print("\033[0;32m  ✓\033[0m %s -> %s" % (dst, src))
        return 0

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    directory = attempt_dir()
    kind = kind_of(dst)
    backup: Optional[str] = None
    prev_target: Optional[str] = None
    if kind == "symlink":
        prev_target = os.readlink(dst)
    if kind != "none":
        backup = stash(directory, dst)
    append_entry(
        directory,
        {
            "op": "link",
            "dst": dst,
            "src": src,
            "kind": kind,
            "backup": backup,
            "prev_target": prev_target,
        },
    )
    if backup:
        move(dst, backup)
        was = {"symlink": "symlink -> " + tilde(prev_target or ""), "dir": "directory"}
        warn(
            "transaction: replaced %s (was a %s); backup in %s; "
            "undo with scripts/restore.sh"
            % (tilde(dst), was.get(kind, "file"), tilde(directory))
        )

    tmp = "%s.dotfiles-tmp.%d" % (dst, os.getpid())
    if os.path.lexists(tmp):
        os.remove(tmp)
    os.symlink(src, tmp)
    os.replace(tmp, dst)
    print("\033[0;32m  ✓\033[0m %s -> %s" % (dst, src))
    return 0


def cmd_backup(path: str) -> int:
    path = os.path.abspath(path)
    kind = kind_of(path)
    if kind == "none":
        return 0
    directory = attempt_dir()
    backup = stash(directory, path)
    append_entry(
        directory, {"op": "backup", "dst": path, "kind": kind, "backup": backup}
    )
    move(path, backup)
    warn("backed up %s -> %s" % (path, backup))
    return 0


def restore_entry(entry: Entry) -> bool:
    dst = entry["dst"]
    backup = entry.get("backup")
    if entry["op"] == "link":
        if os.path.islink(dst) and os.readlink(dst) == entry["src"]:
            os.remove(dst)
        elif os.path.lexists(dst):
            warn("changed since setup, left alone: " + dst)
            return False
    elif os.path.lexists(dst):
        warn("exists again, left alone (backup kept at %s): %s" % (backup, dst))
        return False

    if backup:
        if not os.path.lexists(backup):
            warn("backup is gone: " + backup)
            return False
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        move(backup, dst)
        print("  restored %s" % dst)
    elif entry.get("prev_target") is not None:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.symlink(entry["prev_target"], dst)
        print("  restored %s -> %s" % (dst, entry["prev_target"]))
    else:
        print("  removed %s" % dst)
    return True


def attempts() -> List[str]:
    """Attempt names, newest first (names sort chronologically)."""
    try:
        names = os.listdir(backups_root())
    except FileNotFoundError:
        return []
    found = [
        n for n in names if os.path.isfile(os.path.join(backups_root(), n, MANIFEST))
    ]
    return sorted(found, reverse=True)


def cmd_restore(name: Optional[str]) -> int:
    if name is None:
        pending = [
            n
            for n in attempts()
            if not os.path.exists(os.path.join(backups_root(), n, RESTORED))
        ]
        if not pending:
            print("Nothing to restore.")
            return 0
        name = pending[0]
    directory = attempt_dir(name)
    if not os.path.isfile(os.path.join(directory, MANIFEST)):
        raise Failure("no such attempt: " + name)
    if os.path.exists(os.path.join(directory, RESTORED)):
        print("Attempt %s is already restored." % name)
        return 0

    print("Restoring attempt %s" % name)
    failed = 0
    for entry in reversed(read_manifest(directory)):
        try:
            if not restore_entry(entry):
                failed += 1
        except OSError as error:
            warn("could not restore %s: %s" % (entry.get("dst"), error))
            failed += 1
    with open(os.path.join(directory, RESTORED), "w", encoding="utf-8") as handle:
        handle.write("%d failed\n" % failed)
    if failed:
        warn(
            "%d entr%s not restored; backups stay in %s"
            % (failed, "y was" if failed == 1 else "ies were", directory)
        )
        return 1
    return 0


def cmd_list() -> int:
    names = attempts()
    if not names:
        print("No attempts recorded.")
        return 0
    for name in names:
        directory = attempt_dir(name)
        count = len(read_manifest(directory))
        flag = "restored" if os.path.exists(os.path.join(directory, RESTORED)) else "-"
        print("%s  %d change%s  %s" % (name, count, "" if count == 1 else "s", flag))
    return 0


USAGE = "usage: transaction.py link SRC DST | backup PATH | restore [ATTEMPT] | list"


def main(argv: List[str]) -> int:
    if not argv:
        raise Failure(USAGE)
    cmd, args = argv[0], argv[1:]
    if cmd == "link" and len(args) == 2:
        return cmd_link(args[0], args[1])
    if cmd == "backup" and len(args) == 1:
        return cmd_backup(args[0])
    if cmd == "restore" and len(args) <= 1:
        return cmd_restore(args[0] if args else None)
    if cmd == "list" and not args:
        return cmd_list()
    raise Failure(USAGE)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Failure as failure:
        print("transaction: %s" % failure, file=sys.stderr)
        sys.exit(1)
    except OSError as error:
        print("transaction: %s" % error, file=sys.stderr)
        sys.exit(1)
