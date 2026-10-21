#!/usr/bin/env python3
"""Offline checks for Fallet's source formula and release publishing."""

import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
import formula  # noqa: E402

FORMULA = ROOT / "Formula" / "fallet.rb"
FORMULA_CLI = ROOT / "Scripts" / "formula.py"
PUBLISH = ROOT / "Scripts" / "publish-formula.sh"


def run_formula(*args: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(FORMULA_CLI), *(str(arg) for arg in args)],
                          capture_output=True, text=True)


def fixture(path: Path, tag: str, checksum: str = "a" * 64) -> None:
    """Copy today's formula layout while pinning an isolated test release."""
    content, url, _, current_checksum = formula.fields(FORMULA)
    content = content.replace(f'  url "{url}"', f'  url "{formula.SOURCE}{tag}.tar.gz"')
    content = content.replace(f'  sha256 "{current_checksum}"', f'  sha256 "{checksum}"')
    path.write_text(content)


class FormulaTests(unittest.TestCase):
    def test_formula_layout_and_source_pin(self):
        content, url, tag, checksum = formula.fields(FORMULA)
        self.assertEqual(url, f"{formula.SOURCE}{tag}.tar.gz")
        self.assertRegex(checksum, r"^[0-9a-f]{64}$")
        self.assertIn('prefix.install "dist/Fallet.app"', content)
        self.assertIn('exec /usr/bin/open "#{opt_prefix}/Fallet.app"', content)
        self.assertIn('bin.install "Scripts/fallet-app-link.py" => "fallet-app-link"', content)
        self.assertIn('(bin/"fallet-uninstall").make_symlink "fallet-app-link"', content)
        self.assertIn('libexec.install ".build/FalletLauncher"', content)
        self.assertNotIn("post_install", content)
        self.assertFalse((ROOT / "TapTemplate" / "Formula" / "fallet.rb").exists())

    def test_archive_checksum_url_and_idempotent_update(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fallet.rb"
            archive = Path(folder) / "source.tar.gz"
            fixture(path, "v1.2")
            archive.write_bytes(b"immutable source archive fixture")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            command = ("update", path, "v1.3", digest, "--archive", archive)
            self.assertEqual(run_formula(*command).returncode, 0)
            first = path.read_bytes()
            self.assertEqual(run_formula(*command).returncode, 0)
            self.assertEqual(path.read_bytes(), first)
            _, url, tag, checksum = formula.fields(path)
            self.assertEqual((tag, checksum), ("v1.3", digest))
            self.assertEqual(url, f"{formula.SOURCE}v1.3.tar.gz")
            self.assertEqual(run_formula("verify", path, "--archive", archive).returncode, 0)
            archive.write_bytes(b"different archive")
            self.assertNotEqual(run_formula("verify", path, "--archive", archive).returncode, 0)
            archive.unlink()
            self.assertNotEqual(run_formula("verify", path, "--archive", archive).returncode, 0)

    def test_invalid_versions_hashes_and_downgrades(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fallet.rb"
            fixture(path, "v1.3")
            original = path.read_bytes()
            for tag in ("v1.02", "v1", "1.4", "v1.4-beta", "v1.2"):
                self.assertNotEqual(run_formula("update", path, tag, "b" * 64).returncode, 0)
                self.assertEqual(path.read_bytes(), original)
            for checksum in ("bad", "A" * 64, "", "b" * 63):
                self.assertNotEqual(run_formula("update", path, "v1.4", checksum).returncode, 0)
            self.assertNotEqual(run_formula("assert-upgrade", path, "v1.2").returncode, 0)
            self.assertEqual(run_formula("assert-upgrade", path, "v1.3").returncode, 0)
            self.assertEqual(run_formula("assert-upgrade", path, "v2.0").returncode, 0)
            content = path.read_text()
            path.write_text(content.replace("https://github.com/Shinvitiya/Fallet", "https://example.com"))
            with self.assertRaises(ValueError):
                formula.fields(path)
            path.write_text(content.replace('sha256 "', 'sha256 "bad'))
            with self.assertRaises(ValueError):
                formula.fields(path)

    def test_bundle_version_must_match_release_tag(self):
        with (ROOT / "Resources" / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        version = info["CFBundleShortVersionString"]
        self.assertEqual(info["CFBundleVersion"], version)
        check = [sys.executable, str(ROOT / "Scripts" / "version.py"), "check"]
        self.assertEqual(subprocess.run(check + [f"v{version}"], capture_output=True).returncode, 0)
        major = int(version.split(".")[0])
        self.assertNotEqual(subprocess.run(check + [f"v{major + 1}.0"],
                                           capture_output=True).returncode, 0)

    def test_both_taps_idempotency_conflicts_and_external_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source.rb"
            tap = root / "tap.rb"
            proposed = root / "proposed.rb"
            for path in (source, tap):
                fixture(path, "v1.2")
            fixture(proposed, "v1.3", "b" * 64)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_gh = fake_bin / "gh"
            fake_gh.write_text('''#!/usr/bin/env python3
import base64
import hashlib
import json
import os
import pathlib
import sys

args = sys.argv[1:]
assert args[0] == "api"
endpoint = next(value for value in args[1:] if value.startswith("repos/"))
repo = "/".join(endpoint.split("/")[1:3])
assert repo in ("Shinvitiya/Fallet", "Shinvitiya/homebrew-fallet")
remote = pathlib.Path(os.environ["FAKE_SOURCE" if repo == "Shinvitiya/Fallet" else "FAKE_TAP"])
if repo == "Shinvitiya/homebrew-fallet" and os.environ.get("FAKE_FAIL_TAP") == "1":
    raise SystemExit(42)
if "--method" in args:
    fields = {}
    for index, value in enumerate(args):
        if value == "-f":
            key, entry = args[index + 1].split("=", 1)
            fields[key] = entry
    assert fields["sha"] == hashlib.sha1(remote.read_bytes()).hexdigest()
    assert fields["branch"] == "main"
    remote.write_bytes(base64.b64decode(fields["content"]))
    counts = pathlib.Path(os.environ["FAKE_COUNTS"])
    values = json.loads(counts.read_text())
    values[repo] += 1
    counts.write_text(json.dumps(values))
elif args[-2:] == ["--jq", ".content"]:
    print(base64.b64encode(remote.read_bytes()).decode())
elif args[-2:] == ["--jq", ".sha"]:
    print(hashlib.sha1(remote.read_bytes()).hexdigest())
else:
    raise SystemExit("unexpected gh command")
''')
            fake_gh.chmod(0o755)
            counts = root / "counts.json"
            counts.write_text(json.dumps({"Shinvitiya/Fallet": 0,
                                          "Shinvitiya/homebrew-fallet": 0}))
            env = os.environ.copy()
            env.update(GH_TOKEN="test-token", FAKE_SOURCE=str(source), FAKE_TAP=str(tap),
                       FAKE_COUNTS=str(counts), PATH=f"{fake_bin}:{env['PATH']}")

            def publish(repo: str, candidate: Path = proposed, tag: str = "v1.3",
                        environment: dict[str, str] = env) -> subprocess.CompletedProcess[bytes]:
                return subprocess.run(["bash", str(PUBLISH), repo, str(candidate), tag],
                                      capture_output=True, env=environment)

            self.assertEqual(publish("Shinvitiya/Fallet").returncode, 0)
            self.assertEqual(publish("Shinvitiya/homebrew-fallet").returncode, 0)
            self.assertEqual(source.read_bytes(), proposed.read_bytes())
            self.assertEqual(tap.read_bytes(), proposed.read_bytes())
            self.assertEqual(publish("Shinvitiya/Fallet").returncode, 0)
            self.assertEqual(publish("Shinvitiya/homebrew-fallet").returncode, 0)
            self.assertEqual(list(json.loads(counts.read_text()).values()), [1, 1])

            tap.write_text(tap.read_text().replace("Floating file shelf", "Modified file shelf"))
            self.assertNotEqual(publish("Shinvitiya/homebrew-fallet").returncode, 0)
            self.assertEqual(json.loads(counts.read_text())["Shinvitiya/homebrew-fallet"], 1)

            fixture(tap, "v1.4")
            self.assertNotEqual(publish("Shinvitiya/homebrew-fallet").returncode, 0)
            self.assertEqual(json.loads(counts.read_text())["Shinvitiya/homebrew-fallet"], 1)

            fixture(tap, "v1.2")
            failed_env = dict(env, FAKE_FAIL_TAP="1")
            self.assertNotEqual(publish("Shinvitiya/homebrew-fallet",
                                        environment=failed_env).returncode, 0)
            self.assertEqual(formula.fields(tap)[2], "v1.2")

    def test_workflow_orders_validation_tap_update_and_release(self):
        workflow = (ROOT / ".github" / "workflows" / "homebrew-release.yml").read_text()
        self.assertLess(workflow.index("needs: validate"), workflow.index("Update dedicated Homebrew tap"))
        self.assertLess(workflow.index("Update dedicated Homebrew tap"),
                        workflow.index("Publish stable release only after both formulas are available"))
        self.assertIn('python3 Scripts/version.py check "$RELEASE_TAG"', workflow)
        self.assertIn('python3 Scripts/formula.py verify "$FORMULA_PATH" --archive "$ARCHIVE_PATH"',
                      workflow)
        self.assertIn('lipo .build/FalletLauncher -verify_arch arm64 x86_64', workflow)


if __name__ == "__main__":
    unittest.main()
