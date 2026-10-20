#!/usr/bin/env python3
"""Offline checks for the source-build formula and its release updater."""

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
import formula  # noqa: E402


class FormulaTests(unittest.TestCase):
    def test_source_and_tap_seed_match(self):
        source = ROOT / "Formula" / "fallet.rb"
        template = ROOT / "TapTemplate" / "Formula" / "fallet.rb"
        self.assertEqual(source.read_bytes(), template.read_bytes())
        _, url, tag, checksum = formula.fields(source)
        self.assertEqual(url, f"{formula.SOURCE}{tag}.tar.gz")
        self.assertRegex(checksum, r"^[0-9a-f]{64}$")
        self.assertIn('exec /usr/bin/open "#{opt_prefix}/Fallet.app"', source.read_text())

    def test_update_is_idempotent_and_checksum_is_verified(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fallet.rb"
            archive = Path(folder) / "source.tar.gz"
            path.write_bytes((ROOT / "Formula" / "fallet.rb").read_bytes())
            archive.write_bytes(b"immutable source archive fixture")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            command = [sys.executable, str(ROOT / "Scripts" / "formula.py"),
                       "update", str(path), "v1.10", digest, "--archive", str(archive)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            first = path.read_bytes()
            subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(path.read_bytes(), first)
            _, url, tag, checksum = formula.fields(path)
            self.assertEqual(tag, "v1.10")
            self.assertEqual(url, "https://github.com/Shinvitiya/Fallet/archive/refs/tags/v1.10.tar.gz")
            self.assertEqual(checksum, digest)
            archive.write_bytes(b"different archive")
            failed = subprocess.run([sys.executable, str(ROOT / "Scripts" / "formula.py"),
                                     "verify", str(path), "--archive", str(archive)],
                                    capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)

    def test_rejects_wrong_source_and_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fallet.rb"
            text = (ROOT / "Formula" / "fallet.rb").read_text()
            path.write_text(text.replace("https://github.com/Shinvitiya/Fallet", "https://example.com"))
            with self.assertRaises(ValueError):
                formula.fields(path)
            path.write_text(text.replace('sha256 "', 'sha256 "bad'))
            with self.assertRaises(ValueError):
                formula.fields(path)

    def test_formula_publication_updates_once_and_refuses_downgrade(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            remote = root / "remote.rb"
            remote.write_bytes((ROOT / "Formula" / "fallet.rb").read_bytes())
            proposed = root / "proposed.rb"
            proposed.write_bytes(remote.read_bytes())
            subprocess.run([sys.executable, str(ROOT / "Scripts" / "formula.py"), "update",
                            str(proposed), "v1.6", "a" * 64], check=True, capture_output=True)

            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_gh = fake_bin / "gh"
            fake_gh.write_text('''#!/usr/bin/env python3
import base64
import hashlib
import os
import pathlib
import sys

args = sys.argv[1:]
assert args[0] == "api"
remote = pathlib.Path(os.environ["FAKE_REMOTE_FORMULA"])
if "--method" in args:
    fields = {}
    for index, value in enumerate(args):
        if value == "-f":
            key, entry = args[index + 1].split("=", 1)
            fields[key] = entry
    assert fields["sha"] == hashlib.sha1(remote.read_bytes()).hexdigest()
    assert fields["branch"] == "main"
    remote.write_bytes(base64.b64decode(fields["content"]))
    count = pathlib.Path(os.environ["FAKE_WRITE_COUNT"])
    count.write_text(str(int(count.read_text()) + 1))
elif args[-2:] == ["--jq", ".content"]:
    print(base64.b64encode(remote.read_bytes()).decode())
elif args[-2:] == ["--jq", ".sha"]:
    print(hashlib.sha1(remote.read_bytes()).hexdigest())
else:
    raise SystemExit("unexpected gh command")
''')
            fake_gh.chmod(0o755)
            writes = root / "writes.txt"
            writes.write_text("0")
            env = os.environ.copy()
            env.update(GH_TOKEN="test-token", FAKE_REMOTE_FORMULA=str(remote),
                       FAKE_WRITE_COUNT=str(writes), PATH=f"{fake_bin}:{env['PATH']}")
            publish = ["bash", str(ROOT / "Scripts" / "publish-formula.sh"),
                       "Shinvitiya/homebrew-fallet", str(proposed), "v1.6"]
            subprocess.run(publish, check=True, capture_output=True, env=env)
            self.assertEqual(remote.read_bytes(), proposed.read_bytes())
            subprocess.run(publish, check=True, capture_output=True, env=env)
            self.assertEqual(writes.read_text(), "1")

            remote.write_text(remote.read_text().replace("Floating file shelf", "Modified file shelf"))
            conflict = subprocess.run(publish, capture_output=True, env=env)
            self.assertNotEqual(conflict.returncode, 0)
            self.assertEqual(writes.read_text(), "1")

            old_formula = root / "old.rb"
            old_formula.write_bytes((ROOT / "Formula" / "fallet.rb").read_bytes())
            subprocess.run([sys.executable, str(ROOT / "Scripts" / "formula.py"), "update",
                            str(old_formula), "v1.5", "b" * 64], check=True, capture_output=True)
            downgrade = subprocess.run(["bash", str(ROOT / "Scripts" / "publish-formula.sh"),
                                        "Shinvitiya/homebrew-fallet", str(old_formula), "v1.5"],
                                       capture_output=True, env=env)
            self.assertNotEqual(downgrade.returncode, 0)
            self.assertEqual(writes.read_text(), "1")


if __name__ == "__main__":
    unittest.main()
