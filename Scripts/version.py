#!/usr/bin/env python3
"""Keep the two bundle version fields in sync and validate release tags."""

import argparse
import plistlib
import re
from pathlib import Path

PLIST = Path(__file__).resolve().parents[1] / "Resources" / "Info.plist"
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))?\Z")


def valid(value: str) -> bool:
    return bool(VERSION.fullmatch(value))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("set", "check", "print"))
    parser.add_argument("value", nargs="?")
    args = parser.parse_args()
    with PLIST.open("rb") as stream:
        info = plistlib.load(stream)

    if args.command == "set":
        if not args.value or not valid(args.value):
            parser.error("set requires a numeric version such as 1.6 or 1.10.1")
        info["CFBundleShortVersionString"] = args.value
        info["CFBundleVersion"] = args.value
        with PLIST.open("wb") as stream:
            plistlib.dump(info, stream, sort_keys=False)
        print(args.value)
        return

    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not isinstance(version, str) or not valid(version) or build != version:
        parser.error("CFBundleShortVersionString and CFBundleVersion must be the same valid version")
    if args.command == "check":
        if args.value != f"v{version}":
            parser.error(f"tag must be v{version}; got {args.value or 'none'}")
    elif args.value:
        parser.error("print does not accept a value")
    print(version)


if __name__ == "__main__":
    main()
