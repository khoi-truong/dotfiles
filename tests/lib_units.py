"""Unit tests for lib/transaction.py.

Run: /usr/bin/python3 -B -I tests/lib_units.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from typing import Dict, List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
TRANSACTION = os.path.join(os.path.dirname(HERE), "lib", "transaction.py")


class Case(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = os.path.realpath(tmp.name)
        self.state = os.path.join(self.home, "state")
        self.root = os.path.join(self.state, "dotfiles", "backups")
        self.repo = os.path.join(self.home, "repo")
        os.makedirs(self.repo)

    def run_tx(
        self, *args: str, attempt: Optional[str] = "20260101T000000Z-1"
    ) -> "subprocess.CompletedProcess[str]":
        env: Dict[str, str] = {
            "PATH": os.environ.get("PATH", ""),
            "HOME": self.home,
            "XDG_STATE_HOME": self.state,
        }
        if attempt:
            env["DOTFILES_ATTEMPT"] = attempt
        return subprocess.run(
            [sys.executable, "-B", TRANSACTION] + list(args),
            env=env,
            capture_output=True,
            text=True,
        )

    def src(self, name: str, text: str = "new") -> str:
        path = os.path.join(self.repo, name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def dst(self, *parts: str) -> str:
        return os.path.join(self.home, *parts)

    def write(self, path: str, text: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)

    def read(self, path: str) -> str:
        with open(path) as handle:
            return handle.read()

    def attempts(self) -> List[str]:
        try:
            return sorted(os.listdir(self.root))
        except FileNotFoundError:
            return []

    def manifest(self, attempt: str = "20260101T000000Z-1") -> List[str]:
        with open(os.path.join(self.root, attempt, "manifest.jsonl")) as handle:
            return handle.read().splitlines()

    def ok(self, *args: str, attempt: Optional[str] = "20260101T000000Z-1") -> str:
        proc = self.run_tx(*args, attempt=attempt)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout


class TransactionTests(Case):
    def test_new_link_writes_manifest(self) -> None:
        src, dst = self.src("a"), self.dst("sub", "a")
        self.ok("link", src, dst)
        self.assertEqual(os.readlink(dst), src)
        self.assertEqual(len(self.manifest()), 1)
        self.assertIn('"kind": "none"', self.manifest()[0])

    def test_correct_link_writes_nothing(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        os.symlink(src, dst)
        self.ok("link", src, dst)
        self.assertEqual(self.attempts(), [])

    def test_real_file_backed_up_and_restored(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        data = b"orig\x00\xff bytes"
        with open(dst, "wb") as handle:
            handle.write(data)
        self.ok("link", src, dst)
        self.assertTrue(os.path.islink(dst))
        self.ok("restore")
        self.assertFalse(os.path.islink(dst))
        with open(dst, "rb") as handle:
            self.assertEqual(handle.read(), data)

    def test_real_directory_backed_up_and_restored(self) -> None:
        src = os.path.join(self.repo, "tmpl")
        os.makedirs(src)
        dst = self.dst("cfg", "template")
        self.write(os.path.join(dst, "x"), "hello")
        self.write(os.path.join(dst, "deep", "y"), "world")
        self.ok("link", src, dst)
        self.assertTrue(os.path.islink(dst))
        self.ok("restore")
        self.assertTrue(os.path.isdir(dst) and not os.path.islink(dst))
        self.assertEqual(self.read(os.path.join(dst, "x")), "hello")
        self.assertEqual(self.read(os.path.join(dst, "deep", "y")), "world")

    def test_previous_symlink_restored(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        os.symlink("/elsewhere/target", dst)
        self.ok("link", src, dst)
        self.assertEqual(os.readlink(dst), src)
        self.ok("restore")
        self.assertEqual(os.readlink(dst), "/elsewhere/target")

    def test_dangling_symlink_at_target(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        os.symlink(self.dst("nowhere"), dst)
        self.ok("link", src, dst)
        self.assertEqual(os.readlink(dst), src)
        self.ok("restore")
        self.assertEqual(os.readlink(dst), self.dst("nowhere"))

    def test_replace_warns_for_real_file(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        self.write(dst, "SECRET-CONTENT")
        proc = self.run_tx("link", src, dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("transaction: replaced ~/a (was a file)", proc.stderr)
        self.assertIn("backup in ~/state/dotfiles/backups/", proc.stderr)
        self.assertIn("undo with scripts/restore.sh", proc.stderr)
        self.assertNotIn("SECRET-CONTENT", proc.stderr + proc.stdout)

    def test_replace_warns_for_directory(self) -> None:
        src = os.path.join(self.repo, "tmpl")
        os.makedirs(src)
        dst = self.dst("d")
        self.write(os.path.join(dst, "x"), "hello")
        proc = self.run_tx("link", src, dst)
        self.assertIn("(was a directory)", proc.stderr)

    def test_replace_warns_for_foreign_symlink(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        os.symlink("/elsewhere/target", dst)
        proc = self.run_tx("link", src, dst)
        self.assertIn("(was a symlink -> /elsewhere/target)", proc.stderr)

    def test_no_warning_for_correct_link_or_missing_dst(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        first = self.run_tx("link", src, dst)
        self.assertNotIn("replaced", first.stderr)
        second = self.run_tx("link", src, dst)
        self.assertEqual(second.stderr, "")

    def test_missing_source_warns_and_writes_nothing(self) -> None:
        dst = self.dst("a")
        proc = self.run_tx("link", os.path.join(self.repo, "nope"), dst)
        self.assertEqual(proc.returncode, 0)
        self.assertIn("source missing", proc.stderr)
        self.assertFalse(os.path.lexists(dst))
        self.assertEqual(self.attempts(), [])

    def test_backup_and_restore(self) -> None:
        path = self.dst("tpl")
        self.write(os.path.join(path, "f"), "data")
        self.ok("backup", path)
        self.assertFalse(os.path.exists(path))
        self.ok("restore")
        self.assertEqual(self.read(os.path.join(path, "f")), "data")

    def test_backup_of_missing_path_is_noop(self) -> None:
        self.ok("backup", self.dst("absent"))
        self.assertEqual(self.attempts(), [])

    def test_restore_leaves_user_changes_and_fails(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        self.write(dst, "orig")
        self.ok("link", src, dst)
        os.remove(dst)
        self.write(dst, "user edit")
        proc = self.run_tx("restore")
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self.read(dst), "user edit")

    def test_second_restore_is_noop(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        self.write(dst, "orig")
        self.ok("link", src, dst)
        self.ok("restore")
        out = self.ok("restore")
        self.assertEqual(self.read(dst), "orig")
        self.assertIn("Nothing to restore", out)

    def test_restore_named_attempt(self) -> None:
        a, b = self.src("a"), self.src("b")
        da, db = self.dst("a"), self.dst("b")
        self.write(da, "oa")
        self.write(db, "ob")
        self.ok("link", a, da, attempt="20260101T000000Z-1")
        self.ok("link", b, db, attempt="20260102T000000Z-1")
        self.ok("restore", "20260101T000000Z-1")
        self.assertEqual(self.read(da), "oa")
        self.assertTrue(os.path.islink(db))
        out = self.ok("restore", "20260101T000000Z-1")
        self.assertIn("already restored", out)
        self.ok("restore")
        self.assertEqual(self.read(db), "ob")

    def test_default_restore_takes_newest(self) -> None:
        a, b = self.src("a"), self.src("b")
        da, db = self.dst("a"), self.dst("b")
        self.write(da, "oa")
        self.write(db, "ob")
        self.ok("link", a, da, attempt="20260101T000000Z-1")
        self.ok("link", b, db, attempt="20260102T000000Z-1")
        self.ok("restore")
        self.assertEqual(self.read(db), "ob")
        self.assertTrue(os.path.islink(da))

    def test_two_links_share_one_manifest(self) -> None:
        a, b = self.src("a"), self.src("b")
        self.write(self.dst("x", "same"), "1")
        self.write(self.dst("y", "same"), "2")
        self.ok("link", a, self.dst("x", "same"))
        self.ok("link", b, self.dst("y", "same"))
        self.assertEqual(self.attempts(), ["20260101T000000Z-1"])
        self.assertEqual(len(self.manifest()), 2)
        files = os.listdir(os.path.join(self.root, "20260101T000000Z-1", "files"))
        self.assertEqual(len(files), 2)
        self.ok("restore")
        self.assertEqual(self.read(self.dst("x", "same")), "1")
        self.assertEqual(self.read(self.dst("y", "same")), "2")

    def test_list(self) -> None:
        src, dst = self.src("a"), self.dst("a")
        self.ok("link", src, dst)
        out = self.ok("list")
        self.assertIn("20260101T000000Z-1", out)
        self.assertIn("1 change", out)

    def test_generated_attempt_name(self) -> None:
        self.ok("link", self.src("a"), self.dst("a"), attempt=None)
        names = self.attempts()
        self.assertEqual(len(names), 1)
        self.assertRegex(names[0], r"^\d{8}T\d{6}Z-\d+$")

    def test_unknown_attempt_is_readable_error(self) -> None:
        proc = self.run_tx("restore", "nope")
        self.assertEqual(proc.returncode, 1)
        self.assertNotIn("Traceback", proc.stderr)


if __name__ == "__main__":
    unittest.main()
