"""Unit tests for scripts/ci/hygiene.py.

Run: python3 -B -I tests/hygiene_units.py   (Python >= 3.11)
"""

from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from types import ModuleType
from typing import List

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(os.path.dirname(HERE), "scripts", "ci", "hygiene.py")


def load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("hygiene", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hygiene = load()


class Case(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = tmp.name
        # Paths are repo-relative, as `git ls-files` prints them.
        old = os.getcwd()
        os.chdir(self.dir)
        self.addCleanup(os.chdir, old)

    def write(self, name: str, content: bytes | str) -> str:
        path = os.path.join(self.dir, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = content.encode() if isinstance(content, str) else content
        with open(path, "wb") as handle:
            handle.write(data)
        return name

    def reasons(self, path: str) -> List[str]:
        return [why for _, _, why in hygiene.check_file(path)]

    def test_jsonc_with_both_comment_kinds_passes(self) -> None:
        path = self.write(
            "vscode/settings.json",
            '{\n  // line\n  "a": 1, /* block\n  spanning */ "b": 2\n}\n',
        )
        self.assertEqual(hygiene.check_file(path), [])

    def test_jsonc_extension_allows_comments(self) -> None:
        path = self.write("x.jsonc", '{"a": 1} // done\n')
        self.assertEqual(hygiene.check_file(path), [])

    def test_slashes_inside_a_string_are_kept(self) -> None:
        path = self.write("vscode/s.json", '{"url": "http://x/*y*/", "q": "a\\"//b"}\n')
        self.assertEqual(hygiene.check_file(path), [])
        self.assertIn(
            '"http://x/*y*/"', hygiene.strip_jsonc('{"url": "http://x/*y*/"}')
        )

    def test_comments_are_not_allowed_in_plain_json(self) -> None:
        path = self.write("a.json", '{"a": 1} // no\n')
        self.assertEqual(len(hygiene.check_file(path)), 1)

    def test_trailing_comma_fails(self) -> None:
        path = self.write("vscode/s.json", '{\n  "a": 1,\n}\n')
        found = hygiene.check_file(path)
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0][1], 2)

    def test_unclosed_brace_fails(self) -> None:
        path = self.write("vscode/s.json", '{"a": 1\n')
        self.assertEqual(len(hygiene.check_file(path)), 1)

    def test_unterminated_block_comment_fails(self) -> None:
        path = self.write("vscode/s.json", '{"a": 1} /* open\n')
        self.assertEqual(len(hygiene.check_file(path)), 1)

    def test_conflict_marker_fails(self) -> None:
        path = self.write("a.txt", "x\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> topic\n")
        found = hygiene.check_file(path)
        self.assertEqual([n for _, n, _ in found], [2, 4, 6])

    def test_oversized_file_fails(self) -> None:
        path = self.write("big.txt", b"a" * (1024 * 1024 + 1))
        self.assertEqual(len(hygiene.check_file(path)), 1)

    def test_oversized_binary_file_fails(self) -> None:
        path = self.write("big.bin", b"\0" + b"a" * (2 * 1024 * 1024))
        self.assertEqual(len(hygiene.check_file(path)), 1)

    def test_jsonc_applies_only_under_repo_root_vscode(self) -> None:
        self.assertTrue(hygiene.is_jsonc("vscode/settings.json"))
        self.assertTrue(hygiene.is_jsonc("./vscode/snippets/sh.json"))
        self.assertTrue(hygiene.is_jsonc("anywhere/x.jsonc"))
        self.assertFalse(hygiene.is_jsonc("ai/vscode/settings.json"))
        self.assertFalse(hygiene.is_jsonc("other/settings.json"))
        self.assertFalse(hygiene.is_jsonc("vscodex/settings.json"))

    def test_setext_underline_is_not_a_conflict_marker(self) -> None:
        path = self.write("a.md", "Title\n=======\n\ntext\n")
        self.assertEqual(hygiene.check_file(path), [])

    def test_file_of_exactly_one_mib_passes(self) -> None:
        path = self.write("ok.txt", b"a" * (1024 * 1024))
        self.assertEqual(hygiene.check_file(path), [])

    def test_binary_file_is_skipped(self) -> None:
        path = self.write("b.json", b"\x00\x01<<<<<<< x\n{")
        self.assertEqual(hygiene.check_file(path), [])

    def test_symlink_and_missing_are_skipped(self) -> None:
        target = self.write("t.json", "{")
        link = os.path.join(self.dir, "l.json")
        os.symlink(target, link)
        self.assertEqual(hygiene.check_file(link), [])
        self.assertEqual(hygiene.check_file(os.path.join(self.dir, "nope.json")), [])

    def test_valid_toml_passes(self) -> None:
        path = self.write("a.toml", '[t]\nk = "v"\n')
        self.assertEqual(hygiene.check_file(path), [])

    def test_invalid_toml_fails(self) -> None:
        path = self.write("a.toml", '[t]\nk = "v"\nk = "w"\n')
        self.assertEqual(len(hygiene.check_file(path)), 1)


if __name__ == "__main__":
    unittest.main()
