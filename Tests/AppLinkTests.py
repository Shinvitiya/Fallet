#!/usr/bin/env python3
"""Check the Applications launcher without touching the user's real folder."""

import importlib.util
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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
        self.system_applications = self.root / "Applications"
        self.binary = self.root / "FalletLauncher"
        self.binary.write_bytes(b"native launcher fixture")
        self.binary.chmod(0o755)
        binary_patch = mock.patch.object(app_link, "launcher_binary", return_value=self.binary)
        signer_patch = mock.patch.object(app_link, "sign_launcher")
        binary_patch.start()
        signer_patch.start()
        self.addCleanup(binary_patch.stop)
        self.addCleanup(signer_patch.stop)

    def make_keg(self, version: str) -> Path:
        keg = self.prefix / "Cellar" / "fallet" / version
        executable = keg / "Fallet.app" / "Contents" / "MacOS" / "Fallet"
        icon = keg / "Fallet.app" / "Contents" / "Resources" / "Fallet.icns"
        executable.parent.mkdir(parents=True)
        icon.parent.mkdir(parents=True)
        executable.write_text(version)
        icon.write_text("icon")
        return keg

    def test_real_launcher_is_idempotent_and_survives_upgrade(self):
        self.assertEqual(app_link.install(self.target, self.applications), "installed")
        self.assertTrue(self.shortcut.is_dir())
        self.assertFalse(self.shortcut.is_symlink())
        self.assertEqual(app_link.launcher_state(self.shortcut, self.target), "installed")
        info_path, executable, icon, marker = app_link.launcher_files(self.shortcut)
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], app_link.LAUNCHER_ID)
        self.assertEqual(info["FalletHomebrewTarget"], str(self.target))
        self.assertNotIn("LSUIElement", info)
        self.assertEqual(executable.read_bytes(), self.binary.read_bytes())
        self.assertTrue(os.access(executable, os.X_OK))
        self.assertEqual(icon.read_text(), "icon")
        self.assertEqual(marker.read_text(), str(self.target))
        self.assertEqual(app_link.install(self.target, self.applications), "already installed")

        upgraded = self.make_keg("1.3")
        next_opt = self.opt.with_name("fallet-next")
        next_opt.symlink_to(upgraded, target_is_directory=True)
        next_opt.replace(self.opt)
        self.assertEqual(app_link.launcher_state(self.shortcut, self.target), "installed")
        self.assertEqual(self.target.resolve(), (upgraded / "Fallet.app").resolve())
        self.assertEqual(app_link.uninstall(self.target, self.applications), "uninstalled")
        self.assertEqual(app_link.uninstall(self.target, self.applications), "already absent")
        self.assertTrue((upgraded / "Fallet.app").exists())

    def test_existing_legacy_link_is_migrated(self):
        self.applications.mkdir(parents=True)
        self.shortcut.symlink_to(self.target, target_is_directory=True)
        self.assertEqual(app_link.launcher_state(self.shortcut, self.target), "legacy link")
        self.assertEqual(app_link.install(self.target, self.applications), "installed")
        self.assertFalse(self.shortcut.is_symlink())
        self.assertEqual(app_link.launcher_state(self.shortcut, self.target), "installed")

    def test_global_install_migrates_managed_user_launcher_only_after_success(self):
        self.applications.mkdir(parents=True)
        self.shortcut.symlink_to(self.target, target_is_directory=True)
        with mock.patch.object(app_link, "register"), mock.patch.object(app_link, "unregister"):
            with mock.patch.object(app_link, "sign_launcher", side_effect=app_link.ShortcutError("signing failed")):
                with self.assertRaises(app_link.ShortcutError):
                    app_link.install_default(self.target, self.system_applications, self.applications)
            self.assertTrue(self.shortcut.is_symlink())
            self.assertEqual(app_link.install_default(self.target, self.system_applications,
                                                      self.applications), "installed")
        self.assertTrue((self.system_applications / "Fallet.app").is_dir())
        self.assertFalse(self.shortcut.exists())

    def test_complete_uninstall_removes_owned_data_but_preserves_other_files(self):
        with mock.patch.object(app_link, "register"), mock.patch.object(app_link, "unregister"):
            app_link.install_default(self.target, self.system_applications, self.applications)
            home = self.root / "home"
            support = home / "Library" / "Application Support" / "Fallet"
            cache = home / "Library" / "Caches" / "dev.local.fallet"
            preferences = home / "Library" / "Preferences" / "dev.local.fallet.plist"
            homebrew_log = home / "Library" / "Logs" / "Homebrew" / "fallet"
            crash_folder = home / "Library" / "Logs" / "DiagnosticReports"
            crash_report = crash_folder / "Fallet-2026-10-21.ips"
            other_report = crash_folder / "AnotherApp-2026-10-21.ips"
            crash_marker = (home / "Library" / "Application Support" / "CrashReporter" /
                            "Fallet_ABC.plist")
            support.mkdir(parents=True)
            cache.mkdir(parents=True)
            preferences.parent.mkdir(parents=True)
            homebrew_log.mkdir(parents=True)
            crash_folder.mkdir(parents=True)
            crash_marker.parent.mkdir(parents=True)
            (support / "shelf.json").write_text("shelf")
            (cache / "cache.db").write_text("cache")
            preferences.write_text("settings")
            (homebrew_log / "build.log").write_text("log")
            crash_report.write_text("crash")
            other_report.write_text("keep")
            crash_marker.write_text("marker")
            other = home / "Library" / "Application Support" / "Another App"
            other.mkdir()
            (other / "data").write_text("keep")
            with mock.patch.object(app_link, "quit_fallet"), mock.patch.object(
                app_link.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)
            ) as run:
                result = app_link.full_uninstall(self.target, self.system_applications,
                                                 self.applications, home)
            self.assertIn("uninstalled", result)
            self.assertIn(mock.call(["brew", "uninstall", "fallet"], capture_output=True, text=True),
                          run.call_args_list)
        self.assertFalse((self.system_applications / "Fallet.app").exists())
        self.assertFalse(support.exists())
        self.assertFalse(cache.exists())
        self.assertFalse(preferences.exists())
        self.assertFalse(homebrew_log.exists())
        self.assertFalse(crash_report.exists())
        self.assertFalse(crash_marker.exists())
        self.assertEqual(other_report.read_text(), "keep")
        self.assertEqual((other / "data").read_text(), "keep")

    def test_failed_signing_preserves_legacy_link(self):
        self.applications.mkdir(parents=True)
        self.shortcut.symlink_to(self.target, target_is_directory=True)
        with mock.patch.object(app_link, "sign_launcher", side_effect=app_link.ShortcutError("signing failed")):
            with self.assertRaises(app_link.ShortcutError):
                app_link.install(self.target, self.applications)
        self.assertTrue(self.shortcut.is_symlink())
        self.assertEqual(self.shortcut.readlink(), self.target)

    def test_existing_apps_shortcuts_and_modified_launchers_are_preserved(self):
        self.applications.mkdir(parents=True)
        self.shortcut.mkdir()
        marker = self.shortcut / "unrelated.txt"
        marker.write_text("keep")
        with self.assertRaises(app_link.ShortcutError):
            app_link.install(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.uninstall(self.target, self.applications)
        self.assertEqual(marker.read_text(), "keep")
        marker.unlink()
        self.shortcut.rmdir()

        self.shortcut.symlink_to(self.root / "missing-other-app")
        with self.assertRaises(app_link.ShortcutError):
            app_link.install(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.uninstall(self.target, self.applications)
        self.shortcut.unlink()

        app_link.install(self.target, self.applications)
        extra = self.shortcut / "keep.txt"
        extra.write_text("keep")
        with self.assertRaises(app_link.ShortcutError):
            app_link.uninstall(self.target, self.applications)
        self.assertEqual(extra.read_text(), "keep")

    def test_missing_app_and_symlinked_applications_are_rejected(self):
        self.opt.unlink()
        with self.assertRaises(app_link.ShortcutError):
            app_link.install(self.target, self.applications)
        self.opt.symlink_to(self.keg, target_is_directory=True)
        self.applications.parent.mkdir(parents=True)
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.applications.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaises(app_link.ShortcutError):
            app_link.install(self.target, self.applications)
        with self.assertRaises(app_link.ShortcutError):
            app_link.uninstall(self.target, self.applications)
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
        status = subprocess.run([sys.executable, str(SCRIPT), "status", "--user"], env=env,
                                capture_output=True, text=True)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("missing", status.stdout)
        app_link.install(self.target, self.applications)
        status = subprocess.run([sys.executable, str(SCRIPT), "status", "--user"], env=env,
                                capture_output=True, text=True)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("installed", status.stdout)


if __name__ == "__main__":
    unittest.main()
