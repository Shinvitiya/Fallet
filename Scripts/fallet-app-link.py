#!/usr/bin/env python3
"""Manage Fallet's optional, user-owned Applications shortcut."""

import os
import subprocess
import sys
from pathlib import Path

SHORTCUT_NAME = "Fallet.app"
LSREGISTER = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)


class ShortcutError(Exception):
    pass


def homebrew_app() -> Path:
    try:
        result = subprocess.run(["brew", "--prefix"], check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise ShortcutError("Homebrew is unavailable; install Fallet with Homebrew first") from error
    prefix = Path(result.stdout.strip())
    if not prefix.is_absolute():
        raise ShortcutError("Homebrew returned an invalid installation prefix")
    return prefix / "opt" / "fallet" / SHORTCUT_NAME


def shortcut_state(shortcut: Path, target: Path) -> str:
    if shortcut.is_symlink():
        return "linked" if shortcut.readlink() == target else "conflict"
    return "conflict" if shortcut.exists() else "missing"


def link(target: Path, applications: Path) -> str:
    if not (target / "Contents" / "MacOS" / "Fallet").is_file():
        raise ShortcutError(f"Homebrew Fallet is not installed at {target}")
    if applications.is_symlink() or (applications.exists() and not applications.is_dir()):
        raise ShortcutError(f"Cannot use {applications}; it is not a regular directory")
    applications.mkdir(mode=0o755, parents=True, exist_ok=True)
    if applications.is_symlink():
        raise ShortcutError(f"Cannot use symlinked Applications directory: {applications}")
    shortcut = applications / SHORTCUT_NAME
    state = shortcut_state(shortcut, target)
    if state == "linked":
        return "already linked"
    if state == "conflict":
        raise ShortcutError(f"Preserved existing {shortcut}; move it yourself before linking Fallet")
    try:
        shortcut.symlink_to(target, target_is_directory=True)
    except FileExistsError as error:
        raise ShortcutError(f"Preserved existing {shortcut}; it appeared during setup") from error
    return "linked"


def unlink(target: Path, applications: Path) -> str:
    if applications.is_symlink():
        raise ShortcutError(f"Cannot use symlinked Applications directory: {applications}")
    shortcut = applications / SHORTCUT_NAME
    state = shortcut_state(shortcut, target)
    if state == "missing":
        return "already absent"
    if state == "conflict":
        raise ShortcutError(f"Preserved {shortcut}; it is not Fallet's Homebrew shortcut")
    shortcut.unlink()
    return "unlinked"


def register(shortcut: Path) -> None:
    if not LSREGISTER.is_file():
        return
    result = subprocess.run([str(LSREGISTER), "-f", str(shortcut)], capture_output=True, text=True)
    if result.returncode != 0:
        print("Fallet is linked in Applications; Spotlight registration was unavailable.", file=sys.stderr)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"link", "unlink", "status"}:
        print("Usage: fallet-app-link {link|unlink|status}", file=sys.stderr)
        return 2
    if os.geteuid() == 0:
        print("Run this as your macOS user, without sudo.", file=sys.stderr)
        return 2
    try:
        target = homebrew_app()
        applications = Path.home() / "Applications"
        command = sys.argv[1]
        if command == "link":
            result = link(target, applications)
            if result == "linked":
                register(applications / SHORTCUT_NAME)
        elif command == "unlink":
            result = unlink(target, applications)
        else:
            result = shortcut_state(applications / SHORTCUT_NAME, target)
        print(f"Fallet Applications shortcut: {result} ({applications / SHORTCUT_NAME})")
        return 0 if result != "conflict" else 2
    except (OSError, ShortcutError) as error:
        print(f"Fallet Applications shortcut: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
