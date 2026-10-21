#!/usr/bin/env python3
"""Validate or update Fallet's immutable, SHA-pinned Homebrew source formula."""

import argparse
import hashlib
import re
from pathlib import Path

SOURCE = "https://github.com/Shinvitiya/Fallet/archive/refs/tags/"
TAG = re.compile(r"(?:v|source-v)(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*))?\Z")
SHA = re.compile(r"[0-9a-f]{64}\Z")
URL_LINE = re.compile(r'^  url "(https://github\.com/Shinvitiya/Fallet/archive/refs/tags/([^"/]+)\.tar\.gz)"$', re.M)
SHA_LINE = re.compile(r'^  sha256 "([0-9a-f]{64})"$', re.M)


def version(tag: str) -> tuple[int, int, int]:
    parts = tuple(map(int, tag.removeprefix("source-v").removeprefix("v").split(".")))
    return (parts + (0, 0, 0))[:3]


def fields(path: Path) -> tuple[str, str, str, str]:
    content = path.read_text()
    urls = URL_LINE.findall(content)
    hashes = SHA_LINE.findall(content)
    if len(urls) != 1 or len(hashes) != 1 or not TAG.fullmatch(urls[0][1]):
        raise ValueError(f"{path}: expected one Fallet source URL and one SHA-256")
    return content, urls[0][0], urls[0][1], hashes[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("update", "verify", "assert-upgrade"))
    parser.add_argument("formula", type=Path)
    parser.add_argument("tag", nargs="?")
    parser.add_argument("checksum", nargs="?")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    content, url, tag, checksum = fields(args.formula)

    if args.command == "update":
        if not args.tag or not args.tag.startswith("v") or not TAG.fullmatch(args.tag):
            parser.error("update needs a release tag such as v1.6")
        if not args.checksum or not SHA.fullmatch(args.checksum):
            parser.error("update needs a lowercase 64-character SHA-256")
        if version(tag) > version(args.tag):
            parser.error(f"refusing to replace newer formula {tag} with {args.tag}")
        content = content.replace(f'  url "{url}"', f'  url "{SOURCE}{args.tag}.tar.gz"')
        content = content.replace(f'  sha256 "{checksum}"', f'  sha256 "{args.checksum}"')
        args.formula.write_text(content)
        url, tag, checksum = SOURCE + args.tag + ".tar.gz", args.tag, args.checksum
    elif args.command == "assert-upgrade":
        if not args.tag or not args.tag.startswith("v") or not TAG.fullmatch(args.tag):
            parser.error("assert-upgrade needs a release tag such as v1.6")
        if version(tag) > version(args.tag):
            parser.error(f"refusing to replace newer formula {tag} with {args.tag}")
        if args.checksum:
            parser.error("assert-upgrade accepts no checksum")
    elif args.tag or args.checksum:
        parser.error("verify accepts no tag or checksum arguments")

    if args.archive:
        digest = hashlib.sha256()
        with args.archive.open("rb") as archive:
            for block in iter(lambda: archive.read(1024 * 1024), b""):
                digest.update(block)
        actual = digest.hexdigest()
        if actual != checksum:
            parser.error(f"archive SHA-256 mismatch: expected {checksum}, got {actual}")
    print(f"{tag} {checksum} {url}")


if __name__ == "__main__":
    main()
