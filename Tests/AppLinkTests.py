#!/usr/bin/env python3
"""Check Applications setup without touching the user's real Applications folder."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "Scripts" / "fallet-app-link.py"
SPEC = importlib.util.spec_from_file_location("fallet_app_link", SCRIPT)
app_link = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(app_link)


class AppLinkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.prefix = self.root / "brew"
        self.opt = self.prefix / "opt" / "fallet"
        self.opt.parent.mkdir(parents=True)
        self.keg = self.make_keg("1.2")
        self.opt.symlink_to(self.keg, target_is_directory=True)
        self.target = self.opt / "Fallet.app"
        self.applications = self.root / "home" / "Applications"
        self.shortcut = self.applications / "Fallet.app"

    def make_keg(self, version: str) -> Path:
        keg = self.prefix / "Cellar" / "fallet" / version
        executable = keg / "Fallet.app" / "Contents" / "MacOS" / "Fallet"
        executable.parent.mkdir(parents=True)
        executable.write_text(version)
        return keg

    def test_link_is_idempotent_and_survives_upgrade(self):
        self.assertEqual(app_link.link(self.target, self.applications), "linked")
        self.assertTrue(self.applications.is_dir())
        self.assertEqual(self.shortcut.readlink(), self.target)
        self.assertEqual(app_link.link(self.target, self.applications), "already linked")
        upgraded = self.make_keg("1.3")
        next_opt = self.opt.with_name("fallet-next")
        next_opt.symlink_to(upgraded, target_is_directory=True)
        next_opt.replace(self.opt)
        self.assertEqual(self.shortcut.readlink(), self.target)
        self.assertEqual(self.shortcut.resolve(), (upgraded / "Fallet.app").resolve())
        self.assertEqual(app_link.unlink(self.target, self.applications), "unlinked")
        self.assertEqual(app_link.unlink(self.target, self.applications), "already absent")
        self.assertFalse(self.shortcut.is_symlink())
        self.assertTrue(upgraded.exists())

    def test_existing_apps_and_shortcuts_are_preserved(self):
        self.applications.mkdir(parents=True)
        self.shortcut.mkdir()
        marker = self.shortcut / "unrelated.txt"
        marker.write_text("keep")
        with self.assertRaises(app_link.ShortcutError):
            app_link.link(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.unlink(self.target, self.applications)
        self.assertEqual(marker.read_text(), "keep")
        marker.unlink()
        self.shortcut.rmdir()

        self.shortcut.symlink_to(self.root / "missing-other-app")
        with self.assertRaises(app_link.ShortcutError):
            app_link.link(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.unlink(self.target, self.applications)
        self.assertTrue(self.shortcut.is_symlink())

    def test_uninstall_cleanup_never_removes_the_managed_app(self):
        app_link.link(self.target, self.applications)
        app_link.unlink(self.target, self.applications)
        self.assertFalse(self.shortcut.exists())
        self.assertTrue((self.keg / "Fallet.app").is_dir())
        self.assertTrue(self.opt.is_symlink())

    def test_missing_app_and_symlinked_applications_are_rejected(self):
        self.opt.unlink()
        with self.assertRaises(app_link.ShortcutError):
            app_link.link(self.target, self.applications)
        self.opt.symlink_to(self.keg, target_is_directory=True)
        self.applications.parent.mkdir(parents=True)
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.applications.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaises(app_link.ShortcutError):
            app_link.link(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.unlink(self.target, self.applications)
        self.assertFalse((elsewhere / "Fallet.app").exists())

    def test_command_uses_homebrew_prefix_and_reports_status(self):
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        brew = fake_bin / "brew"
        brew.write_text(f"#!/bin/sh\n[ \"$1\" = --prefix ] || exit 1\nprintf '%s\\n' '{self.prefix}'\n")
        brew.chmod(0o755)
        home = self.root / "home"
        home.mkdir()
        env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}", HOME=str(home))
        status = subprocess.run([sys.executable, str(SCRIPT), "status"], env=env,
                                capture_output=True, text=True)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("missing", status.stdout)
        app_link.link(self.target, self.applications)
        status = subprocess.run([sys.executable, str(SCRIPT), "status"], env=env,
                                capture_output=True, text=True)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("linked", status.stdout)


if __name__ == "__main__":
    unittest.main()
