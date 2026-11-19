
"""Run the PowerShell installer against disposable profiles on Windows."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SOURCE = Path(os.environ.get("RIGOROUS_ADVISOR_TEST_SOURCE", Path(__file__).resolve().parents[1])).resolve()
ENGINE = os.environ.get("RIGOROUS_ADVISOR_TEST_POWERSHELL", "pwsh")
HEADING = "## Decision Rigor & Anti-Sycophancy"
LEGACY = Path(__file__).resolve().parent / "fixtures" / "agents-v2.0.0.md"
UTF8_BOM = b"\xef\xbb\xbf"
START = b"<!-- rigorous-advisor:start -->"
END = b"<!-- rigorous-advisor:end -->"


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="rigorous-advisor-tests-", dir=os.environ.get("RIGOROUS_ADVISOR_TEST_TEMP"))
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name).resolve()
        self.profile = self.root / "profile [sandbox]"
        self.user_root = self.root / "local-user"
        self.target = self.profile / "skills" / "rigorous-advisor"
        self.agents = self.profile / "AGENTS.md"
        self.profile.mkdir()
        self.user_root.mkdir()
        self.env = dict(os.environ, TEMP=str(self.root), TMP=str(self.root))
        self.manager = SOURCE / "scripts" / "manage-codex.ps1"

    def run_manager(self, action, *args, script=None, profile=None, cwd=None):
        return subprocess.run(
            [ENGINE, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-File", str(script or self.manager), "-Action", action, "-HomeDir", str(self.user_root),
             "-CodexHome", str(profile or self.profile), *args],
            cwd=cwd or self.root, env=self.env, capture_output=True, timeout=20,
        )

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))

    def seed(self, version="1.5.0"):
        self.target.mkdir(parents=True)
        (self.target / "SKILL.md").write_text(
            f"---\nname: rigorous-advisor\nmetadata:\n  version: '{version}'\n---\nOLD\n", encoding="utf-8"
        )
        (self.target / "held.txt").write_bytes(b"old lock sentinel")
        (self.target / "other.txt").write_bytes(b"old files intact")
        return {p.name: p.read_bytes() for p in self.target.iterdir()}

    def test_relative_profile_install(self):
        profile = Path(".") / self.profile.name
        self.assert_success(self.run_manager("Install", profile=profile))
        self.assertEqual((self.target / "SKILL.md").read_bytes(), (SOURCE / "SKILL.md").read_bytes())

    def test_skip_other_hosts_and_publish_runtime_only(self):
        (self.user_root / ".claude" / "skills" / "rigorous-advisor").mkdir(parents=True)
        self.assert_success(self.run_manager("Install"))
        self.assertEqual(
            sorted(p.relative_to(self.target).as_posix() for p in self.target.rglob("*") if p.is_file()),
            ["SKILL.md", "references/evaluation-rubric.md"],
        )
        self.assertNotEqual(self.run_manager("Install").returncode, 0)

    def test_upgrade_missing_and_downgrade_rejected(self):
        self.assertNotEqual(self.run_manager("Upgrade").returncode, 0)
        initial = self.seed("9.9.9")
        self.assertNotEqual(self.run_manager("Upgrade").returncode, 0)
        self.assertEqual((self.target / "SKILL.md").read_bytes(), initial["SKILL.md"])

    def test_publish_failure_restores_original(self):
        initial = self.seed()
        self.assertNotEqual(self.run_manager("Upgrade", "-SimulateCopyFailure").returncode, 0)
        self.assertEqual({p.name: p.read_bytes() for p in self.target.iterdir()}, initial)
        backup = next((self.profile / "backups").glob("*.zip"))
        with zipfile.ZipFile(backup) as archived:
            self.assertIsNone(archived.testzip())
            entry = next(name for name in archived.namelist() if name.replace("\\", "/") == "rigorous-advisor/other.txt")
            self.assertEqual(archived.read(entry), initial["other.txt"])

    def test_locked_cleanup_keeps_new_install(self):
        self.seed()
        checkout = self.root / "instrumented-package"
        shutil.copytree(SOURCE, checkout, ignore=shutil.ignore_patterns("__pycache__", ".git"))
        manager = checkout / "scripts" / self.manager.name
        source = manager.read_text(encoding="utf-8-sig")
        pattern = r"(?m)^([ \t]*)Remove-Item -LiteralPath \$rollbackPath -Recurse -Force.*$"
        lock = "$fixtureHandle = [IO.File]::Open((Join-Path $rollbackPath 'held.txt'), 'Open', 'Read', 'Read')"
        source, count = re.subn(pattern, lambda m: m[1] + lock + "\n" + m[0], source)
        self.assertEqual(count, 1)
        manager.write_text(source, encoding="utf-8-sig")
        result = self.run_manager("Upgrade", script=manager)
        self.assert_success(result)
        self.assertEqual((self.target / "SKILL.md").read_bytes(), (SOURCE / "SKILL.md").read_bytes())
        self.assertIn(b"warning", result.stdout.lower())
        self.assert_success(self.run_manager("Upgrade"))
        self.assertTrue(any(self.profile.glob(".rigorous-advisor-retired-*")))

    def test_interrupted_upgrade_restores_then_publishes(self):
        self.seed()
        previous = self.profile / ".rigorous-advisor-previous"
        self.target.rename(previous)
        self.assert_success(self.run_manager("Upgrade"))
        self.assertFalse(previous.exists())
        self.assertEqual((self.target / "SKILL.md").read_bytes(), (SOURCE / "SKILL.md").read_bytes())

    def test_first_publish_failure_can_retry(self):
        self.assertNotEqual(self.run_manager("Install", "-SimulateCopyFailure").returncode, 0)
        self.assertFalse(self.target.exists())
        self.assert_success(self.run_manager("Install"))

    def test_two_supported_roots_require_explicit_upgrade(self):
        self.assert_success(self.run_manager("Install"))
        self.assert_success(self.run_manager("Install", "-InstallRootType", "Agents"))
        self.assertNotEqual(self.run_manager("Upgrade").returncode, 0)
        self.assert_success(self.run_manager("Upgrade", "-InstallRootType", "Agents"))

    def test_upgrade_partial_legacy_installation(self):
        self.target.mkdir(parents=True)
        (self.target / "stale.txt").write_bytes(b"partial legacy install")
        self.assert_success(self.run_manager("Upgrade"))
        self.assertFalse((self.target / "stale.txt").exists())
        self.assertEqual((self.target / "SKILL.md").read_bytes(), (SOURCE / "SKILL.md").read_bytes())

    def test_fenced_heading_is_preserved(self):
        sample = b"# Example\n```markdown\n" + HEADING.encode() + b"\nexample only\n~~~\n```\n## Keep\nKeep this"
        self.agents.write_bytes(sample)
        self.assert_success(self.run_manager("UpdateAnchor"))
        self.assertTrue(self.agents.read_bytes().startswith(sample))
        self.assertIn(START, self.agents.read_bytes())

    def test_unknown_legacy_block_refuses_any_edit(self):
        sample = HEADING.encode() + b"\n- Custom instruction\n  ## Keep\nKeep this"
        self.agents.write_bytes(sample)
        self.assertNotEqual(self.run_manager("UpdateAnchor").returncode, 0)
        self.assertEqual(self.agents.read_bytes(), sample)

    def test_known_legacy_preserves_bom_and_unrelated_bytes(self):
        old = LEGACY.read_bytes().removeprefix(UTF8_BOM).rstrip(b"\r\n")
        old = old.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        prefix = UTF8_BOM + b"# Prefix\nThis is outside the block.\r\n\r\n"
        suffix = b"\r\n\r\n  ## Following\nKEEP_EOF"
        self.agents.write_bytes(prefix + old + suffix)
        self.assert_success(self.run_manager("UpdateAnchor", "-Language", "ZH"))
        after = self.agents.read_bytes()
        self.assertTrue(after.startswith(prefix + START), after[:200])
        self.assertTrue(after.endswith(END + suffix), after[-200:])
        self.assertIn("客观评审与反迎合底线".encode(), after)
        self.assert_success(self.run_manager("UpdateAnchor", "-Language", "ZH"))
        self.assertEqual(after, self.agents.read_bytes())
        backups = list((self.profile / "backups").glob("AGENTS-backup-*.md"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), prefix + old + suffix)

    def test_utf16_file_refused(self):
        sample = (HEADING + "\n- Original").encode("utf-16")
        self.agents.write_bytes(sample)
        self.assertNotEqual(self.run_manager("UpdateAnchor").returncode, 0)
        self.assertEqual(self.agents.read_bytes(), sample)

    def test_append_at_no_final_newline_and_update_in_place(self):
        original = b"## Foreign heading\nexisting content"
        self.agents.write_bytes(original)
        self.assert_success(self.run_manager("UpdateAnchor"))
        english = self.agents.read_bytes()
        self.assertTrue(english.startswith(original + b"\n\n" + START))
        self.assert_success(self.run_manager("UpdateAnchor", "-Language", "ZH"))
        chinese = self.agents.read_bytes()
        self.assertTrue(chinese.startswith(original + b"\n\n" + START))
        self.assertEqual(chinese.count(START), 1)
        self.assertEqual(chinese.count(END), 1)
        self.assertIn("客观评审与反迎合底线".encode(), chinese)

    def test_ambiguous_managed_marker_refused(self):
        original = b"# Notes\n" + START + b"\n" + HEADING.encode() + b"\n- Rule\n\n## Keep\n"
        self.agents.write_bytes(original)
        self.assertNotEqual(self.run_manager("UpdateAnchor").returncode, 0)
        self.assertEqual(self.agents.read_bytes(), original)


if __name__ == "__main__":
    unittest.main(verbosity=2)

