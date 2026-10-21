#!/usr/bin/env python3
"""Install a discoverable app that opens the current Homebrew Fallet."""

import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

APP_NAME = "Fallet.app"
LAUNCHER_ID = "dev.local.fallet.launcher"
LAUNCHER_VERSION = "2"
EXECUTABLE_NAME = "FalletLauncher"
MARKER_NAME = "HomebrewTarget"
SYSTEM_APPLICATIONS = Path("/Applications")
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
    return prefix / "opt" / "fallet" / APP_NAME


def launcher_files(shortcut: Path) -> tuple[Path, Path, Path, Path]:
    contents = shortcut / "Contents"
    return (contents / "Info.plist", contents / "MacOS" / EXECUTABLE_NAME,
            contents / "Resources" / "Fallet.icns", contents / "Resources" / MARKER_NAME)


def launcher_binary() -> Path:
    root = Path(__file__).resolve().parent.parent
    for candidate in (root / "libexec" / EXECUTABLE_NAME,
                      root / ".build" / EXECUTABLE_NAME):
        if candidate.is_file():
            return candidate
    raise ShortcutError("Fallet's native Applications launcher is missing; reinstall Fallet")


def launcher_state(shortcut: Path, target: Path) -> str:
    if shortcut.is_symlink():
        return "legacy link" if shortcut.readlink() == target else "conflict"
    if not shortcut.exists():
        return "missing"
    if not shortcut.is_dir():
        return "conflict"
    info_path, executable, icon, marker = launcher_files(shortcut)
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        if info.get("CFBundleIdentifier") != LAUNCHER_ID:
            return "conflict"
        if info.get("FalletHomebrewTarget") != marker.read_text():
            return "conflict"
        if not executable.is_file() or not icon.is_file() or not marker.is_file():
            return "conflict"
        signature = shortcut / "Contents" / "_CodeSignature" / "CodeResources"
        expected_files = {info_path, executable, icon, marker, signature}
        actual_files = {path for path in shortcut.rglob("*") if path.is_file() or path.is_symlink()}
        if not {info_path, executable, icon, marker}.issubset(actual_files) or actual_files - expected_files:
            return "conflict"
        return "installed" if marker.read_text() == str(target) and info.get("CFBundleVersion") == LAUNCHER_VERSION else "outdated"
    except (OSError, ValueError, plistlib.InvalidFileException):
        return "conflict"


def build_launcher(shortcut: Path, target: Path, binary: Path) -> None:
    info_path, executable, icon, marker = launcher_files(shortcut)
    executable.parent.mkdir(parents=True)
    icon.parent.mkdir(parents=True)
    info = {
        "CFBundleDisplayName": "Fallet",
        "CFBundleExecutable": EXECUTABLE_NAME,
        "CFBundleIconFile": "Fallet.icns",
        "CFBundleIdentifier": LAUNCHER_ID,
        "CFBundleName": "Fallet",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": LAUNCHER_VERSION,
        "FalletHomebrewTarget": str(target),
        "LSMinimumSystemVersion": "13.0",
    }
    with info_path.open("wb") as stream:
        plistlib.dump(info, stream)
    shutil.copy2(binary, executable)
    executable.chmod(0o755)
    shutil.copy2(target / "Contents" / "Resources" / "Fallet.icns", icon)
    marker.write_text(str(target))


def sign_launcher(shortcut: Path) -> None:
    result = subprocess.run(["codesign", "--force", "--sign", "-", str(shortcut)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise ShortcutError(f"Could not sign Fallet's Applications launcher: {result.stderr.strip()}")


def prepare_applications(applications: Path) -> None:
    if applications.is_symlink() or (applications.exists() and not applications.is_dir()):
        raise ShortcutError(f"Cannot use {applications}; it is not a regular directory")
    applications.mkdir(mode=0o755, parents=True, exist_ok=True)
    if applications.is_symlink():
        raise ShortcutError(f"Cannot use symlinked Applications directory: {applications}")


def install(target: Path, applications: Path) -> str:
    if not (target / "Contents" / "MacOS" / "Fallet").is_file():
        raise ShortcutError(f"Homebrew Fallet is not installed at {target}")
    if not (target / "Contents" / "Resources" / "Fallet.icns").is_file():
        raise ShortcutError(f"Fallet icon is missing at {target}")
    prepare_applications(applications)
    shortcut = applications / APP_NAME
    state = launcher_state(shortcut, target)
    if state == "installed":
        return "already installed"
    if state == "conflict":
        raise ShortcutError(f"Preserved existing {shortcut}; move it yourself before installing Fallet")

    binary = launcher_binary()
    with tempfile.TemporaryDirectory(prefix=".Fallet-install-", dir=applications) as folder:
        staged = Path(folder) / APP_NAME
        build_launcher(staged, target, binary)
        sign_launcher(staged)
        backup = Path(folder) / "previous.app"
        if state != "missing":
            shortcut.rename(backup)
        try:
            staged.rename(shortcut)
        except OSError:
            if state != "missing":
                backup.rename(shortcut)
            raise
    return "installed"


def uninstall(target: Path, applications: Path) -> str:
    if applications.is_symlink():
        raise ShortcutError(f"Cannot use symlinked Applications directory: {applications}")
    shortcut = applications / APP_NAME
    state = launcher_state(shortcut, target)
    if state == "missing":
        return "already absent"
    if state == "conflict":
        raise ShortcutError(f"Preserved {shortcut}; it is not Fallet's managed launcher")
    if state == "legacy link":
        shortcut.unlink()
    else:
        shutil.rmtree(shortcut)
    return "uninstalled"


def register(shortcut: Path) -> None:
    if not LSREGISTER.is_file():
        return
    result = subprocess.run([str(LSREGISTER), "-f", str(shortcut)], capture_output=True, text=True)
    if result.returncode != 0:
        print("Fallet is installed in Applications; Spotlight registration was unavailable.", file=sys.stderr)


def unregister(shortcut: Path) -> None:
    if LSREGISTER.is_file():
        subprocess.run([str(LSREGISTER), "-u", str(shortcut)], capture_output=True, text=True)


def managed_state(shortcut: Path, target: Path) -> str:
    state = launcher_state(shortcut, target)
    if state == "conflict":
        raise ShortcutError(f"Preserved {shortcut}; it is not Fallet's managed launcher")
    return state


def remove_managed(target: Path, applications: Path) -> str:
    state = managed_state(applications / APP_NAME, target)
    if state != "missing":
        unregister(applications / APP_NAME)
    return uninstall(target, applications)


def install_default(target: Path, system_applications: Path, user_applications: Path) -> str:
    # Do not remove the old entry until the replacement is safely installed.
    result = install(target, system_applications)
    register(system_applications / APP_NAME)
    old = user_applications / APP_NAME
    if old != system_applications / APP_NAME and launcher_state(old, target) in {
        "legacy link", "installed", "outdated"
    }:
        remove_managed(target, user_applications)
    return result


def unlink_default(target: Path, system_applications: Path, user_applications: Path) -> str:
    paths = [system_applications]
    if user_applications != system_applications:
        paths.append(user_applications)
    states = [(path, launcher_state(path / APP_NAME, target)) for path in paths]
    removed = False
    for path, state in states:
        if state == "conflict":
            print(f"Preserved unrelated {path / APP_NAME}", file=sys.stderr)
            continue
        if state != "missing":
            remove_managed(target, path)
            removed = True
    return "uninstalled" if removed else "already absent"


def running_fallet_pids() -> list[int]:
    result = subprocess.run(["/bin/ps", "-axo", "pid=,uid=,comm="],
                            capture_output=True, text=True, check=True)
    pids = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(maxsplit=2)
        if (len(fields) == 3 and int(fields[1]) == os.getuid() and
                fields[2].endswith("/Fallet.app/Contents/MacOS/Fallet")):
            pids.append(int(fields[0]))
    return pids


def quit_fallet() -> None:
    pids = running_fallet_pids()
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not any(pid in running_fallet_pids() for pid in pids):
            return
        time.sleep(0.1)
    if pids:
        raise ShortcutError("Quit Fallet from its menu bar icon, then run fallet-uninstall again")


def remove_owned_data(home: Path) -> None:
    library = home / "Library"
    owned = [
        library / "Application Support" / "Fallet",
        library / "Caches" / "dev.local.fallet",
        library / "Preferences" / "dev.local.fallet.plist",
        library / "Saved Application State" / "dev.local.fallet.savedState",
        library / "HTTPStorages" / "dev.local.fallet",
        library / "WebKit" / "dev.local.fallet",
    ]
    # Flush cfprefsd's copy so a deleted preferences file is not recreated.
    subprocess.run(["/usr/bin/defaults", "delete", "dev.local.fallet"],
                   capture_output=True, text=True)
    for path in owned:
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)


def full_uninstall(target: Path, system_applications: Path,
                   user_applications: Path, home: Path) -> str:
    quit_fallet()
    unlink_default(target, system_applications, user_applications)
    result = subprocess.run(["brew", "uninstall", "fallet"], capture_output=True, text=True)
    if result.returncode != 0:
        raise ShortcutError(f"Homebrew uninstall failed: {result.stderr.strip()}")
    remove_owned_data(home)
    for command in (["brew", "cleanup", "--scrub", "Shinvitiya/fallet/fallet"],
                    ["brew", "untap", "Shinvitiya/fallet"]):
        cleanup = subprocess.run(command, capture_output=True, text=True)
        if cleanup.returncode != 0:
            print(f"Optional Homebrew cleanup failed: {' '.join(command)}: "
                  f"{cleanup.stderr.strip()}", file=sys.stderr)
    return "uninstalled app, launchers, and Fallet data"


def main() -> int:
    called_as_uninstaller = Path(sys.argv[0]).name == "fallet-uninstall"
    command = "uninstall" if called_as_uninstaller and len(sys.argv) == 1 else (
        sys.argv[1] if len(sys.argv) >= 2 else "")
    user_only = len(sys.argv) == 3 and sys.argv[2] == "--user"
    if (called_as_uninstaller and len(sys.argv) != 1) or (
        not called_as_uninstaller and (command not in {"link", "unlink", "status"}
                                       or len(sys.argv) not in {2, 3} or
                                       (len(sys.argv) == 3 and not user_only))
    ):
        print("Usage: fallet-app-link {link|unlink|status} [--user] or fallet-uninstall", file=sys.stderr)
        return 2
    if os.geteuid() == 0:
        print("Run this as your macOS user, without sudo.", file=sys.stderr)
        return 2
    try:
        target = homebrew_app()
        user_applications = Path.home() / "Applications"
        applications = user_applications if user_only else SYSTEM_APPLICATIONS
        if command == "link":
            if user_only:
                result = install(target, applications)
                register(applications / APP_NAME)
            else:
                result = install_default(target, applications, user_applications)
        elif command == "unlink":
            result = (remove_managed(target, applications) if user_only else
                      unlink_default(target, applications, user_applications))
        elif command == "uninstall":
            result = full_uninstall(target, applications, user_applications, Path.home())
        else:
            result = launcher_state(applications / APP_NAME, target)
        print(f"Fallet Applications launcher: {result} ({applications / APP_NAME})")
        return 0 if result != "conflict" else 2
    except (OSError, ShortcutError) as error:
        print(f"Fallet Applications launcher: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
