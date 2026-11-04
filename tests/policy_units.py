"""Unit tests for scripts/gen-policy.py.

Run: python3 -B -I tests/policy_units.py   (Python >= 3.11)
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from types import ModuleType
from typing import Any, Dict, List

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "scripts", "gen-policy.py")
FIXTURE = os.path.join(HERE, "fixtures", "claude-deny-v1.txt")


def load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("gen_policy", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gen = load()

TINY = (
    'readers = ["cat", "cp"]\n'
    'setup_shells = ["bash"]\n'
    "[[command]]\n"
    'run = "sudo"\n'
    'copilot = "shell(sudo)"\n'
    'why = "x"\n'
    "[[command]]\n"
    'run = "git push"\n'
    'flags = ["--force", "+"]\n'
    'why = "x"\n'
    "[[command]]\n"
    'run = "rm"\n'
    'flags = ["-rf"]\n'
    'targets = ["/", "~/*"]\n'
    'copilot = "shell(rm)"\n'
    'why = "x"\n'
    "[[secret]]\n"
    'path = "~/.tok.json"\n'
    "[[read]]\n"
    'glob = "**/.env"\n'
    "[[raw]]\n"
    'rule = "Bash(curl * | sh)"\n'
)


class Case(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = tmp.name

    def write(self, name: str, content: str) -> str:
        path = os.path.join(self.dir, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)
        return path

    def policy(self, text: str = TINY) -> Dict[str, Any]:
        return gen.load(self.write("policy.toml", text))  # type: ignore[no-any-return]

    def render(self, text: str = TINY, modules: List[str] | None = None) -> List[str]:
        return gen.render_claude(self.policy(text), modules or [])  # type: ignore[no-any-return]

    def root(self, settings: str = '{"a": 1}\n') -> str:
        with open(os.path.join(ROOT, gen.POLICY), encoding="utf-8") as handle:
            self.write(gen.POLICY, handle.read())
        self.write(gen.SETTINGS, settings)
        return self.dir

    def run_main(self, *args: str) -> int:
        with (
            contextlib.redirect_stderr(io.StringIO()),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            return int(gen.main(list(args)))

    def test_no_flags(self) -> None:
        self.assertEqual(self.render()[:2], ["Bash(sudo)", "Bash(sudo *)"])

    def test_flags(self) -> None:
        self.assertEqual(
            self.render()[2:6],
            [
                "Bash(git push --force*)",
                "Bash(git push * --force*)",
                "Bash(git push +*)",
                "Bash(git push * +*)",
            ],
        )

    def test_flags_targets(self) -> None:
        self.assertEqual(
            self.render()[6:14],
            [
                "Bash(rm -rf /)",
                "Bash(rm * -rf /)",
                "Bash(rm -rf * /)",
                "Bash(rm * -rf * /)",
                "Bash(rm -rf ~/*)",
                "Bash(rm * -rf ~/*)",
                "Bash(rm -rf * ~/*)",
                "Bash(rm * -rf * ~/*)",
            ],
        )

    def test_secret(self) -> None:
        rules = self.render()
        self.assertEqual(
            rules[14:17],
            ["Read(~/.tok.json)", "Bash(cat *.tok.json*)", "Bash(cp *.tok.json*)"],
        )

    def test_raw(self) -> None:
        self.assertIn("Bash(curl * | sh)", self.render())
        self.assertIn("Read(**/.env)", self.render())

    def test_one_star_bash_only(self) -> None:
        self.assertEqual(gen.one_star("Bash(a ** b)"), "Bash(a * b)")
        self.assertEqual(gen.one_star("Read(**/.env)"), "Read(**/.env)")

    def test_dedupe_keeps_first(self) -> None:
        text = TINY + '[[raw]]\nrule = "Bash(sudo)"\n[[raw]]\nrule = "Bash(zzz)"\n'
        rules = self.render(text)
        self.assertEqual(rules.count("Bash(sudo)"), 1)
        self.assertEqual(rules[0], "Bash(sudo)")
        self.assertIn("Bash(zzz)", rules)

    def test_setup_discovery(self) -> None:
        for name in ("a/setup.sh", "b/setup.sh", "c/x.sh", ".hid/setup.sh"):
            self.write(name, "")
        self.assertEqual(gen.discover_modules(self.dir), ["a", "b"])
        rules = self.render(modules=["a", "b"])
        self.assertIn("Bash(a/setup.sh*)", rules)
        self.assertIn("Bash(b/setup.sh*)", rules)
        self.assertNotIn("Bash(c/setup.sh*)", rules)
        self.assertIn("Bash(bash *setup.sh*)", rules)

    def test_covers(self) -> None:
        self.assertTrue(gen.covers("Bash(git push -f*)", "Bash(git push -f *)"))
        self.assertFalse(gen.covers("Bash(git push --force*)", "Bash(git push -f *)"))
        self.assertFalse(gen.covers("Read(git push -f*)", "Bash(git push -f *)"))
        self.assertFalse(gen.covers("Bash(a[b]*)", "Bash(ab)"))
        self.assertTrue(gen.covers("Bash(a[b]*)", "Bash(a[b]c)"))
        self.assertFalse(gen.covers("Bash(a?)", "Bash(ab)"))

    def test_floor_superset(self) -> None:
        policy = gen.load(os.path.join(ROOT, gen.POLICY))
        rules = gen.render_claude(policy, gen.discover_modules(ROOT))
        with open(FIXTURE, encoding="utf-8") as handle:
            floor = handle.read().splitlines()
        self.assertEqual(len(floor), 78)
        lost = [r for r in floor if not any(gen.covers(g, r) for g in rules)]
        self.assertEqual(lost, [])

    def test_write_touches_only_deny(self) -> None:
        before = (
            '{\n  "z": [1],\n  "permissions": {"defaultMode": "auto"},\n  "a": 1\n}\n'
        )
        root = self.root(before)
        self.assertEqual(self.run_main("--root", root), 0)
        path = os.path.join(root, gen.SETTINGS)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        data = json.loads(text)
        self.assertEqual(list(data), ["z", "permissions", "a"])
        self.assertEqual(data["z"], [1])
        self.assertEqual(data["permissions"]["defaultMode"], "auto")
        self.assertGreater(len(data["permissions"]["deny"]), 10)
        self.assertTrue(text.endswith("}\n"))
        self.assertIn('\n  "z": [\n    1\n  ]', text)

    def test_check_detects_drift(self) -> None:
        root = self.root()
        path = os.path.join(root, gen.SETTINGS)
        with open(path, encoding="utf-8") as handle:
            stale = handle.read()
        self.assertEqual(self.run_main("--check", "--root", root), 1)
        with open(path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), stale)
        self.assertFalse(os.path.exists(os.path.join(root, gen.COPILOT)))
        self.assertEqual(self.run_main("--root", root), 0)
        self.assertEqual(self.run_main("--check", "--root", root), 0)

    def test_missing_why_rejected(self) -> None:
        root = self.root()
        self.write(gen.POLICY, '[[command]]\nrun = "sudo"\n')
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            code = gen.main(["--check", "--root", root])
        self.assertEqual(code, 2)
        self.assertIn("sudo", buf.getvalue())

    def test_copilot_wrapper(self) -> None:
        self.assertEqual(
            gen.render_copilot(self.policy()),
            "# Generated by scripts/gen-policy.py from ai/profiles/policy.toml. Do not edit.\n"
            "copilot() {\n"
            "  command copilot \\\n"
            "    --deny-tool='shell(sudo)' \\\n"
            "    --deny-tool='shell(rm)' \\\n"
            '    "$@"\n'
            "}\n",
        )


if __name__ == "__main__":
    unittest.main()
