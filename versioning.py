#!/usr/bin/env python3
"""Compute and stamp Tokens on Track bundle versions.

Git tags are the source of truth. Development builds use Git's descriptive
form (release, commit distance, abbreviated object ID and dirty state), while
release builds use the exact version that will be tagged.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import plistlib
from pathlib import Path
import re
import subprocess
from typing import Iterable, Sequence


DISPLAY_VERSION_KEY = "TOTDisplayVersion"
RELEASE_TRAIN_KEY = "TOTReleaseTrain"


@dataclass(frozen=True)
class BundleVersion:
    marketing: str
    build: str
    display: str


def development_version(description: str, build: str) -> BundleVersion:
    """Turn `git describe --long --dirty` output into bundle-safe values."""
    match = re.fullmatch(
        r"v(?P<release>\d+\.\d+\.\d+)-(?P<distance>\d+)-g(?P<sha>[0-9a-f]+)(?P<dirty>-dirty)?",
        description.strip(),
    )
    if match is None:
        raise ValueError(f"unexpected git describe output: {description!r}")

    release = match.group("release")
    distance = match.group("distance")
    dirty = match.group("dirty") or ""
    if distance == "0" and not dirty:
        display = release
    else:
        display = f"{release}-{distance}-g{match.group('sha')}{dirty}"
    return BundleVersion(marketing=release, build=build.strip(), display=display)


def next_release_version(
    train: str, tag_names: Iterable[str], build: str
) -> BundleVersion:
    """Return the next patch in a major.minor train from published tag names."""
    match = re.fullmatch(r"(?P<major>\d+)\.(?P<minor>\d+)", train.strip())
    if match is None:
        raise ValueError(f"release train must look like 1.1, got {train!r}")

    prefix = f"{match.group('major')}.{match.group('minor')}"
    pattern = re.compile(rf"^v{re.escape(prefix)}\.(\d+)$")
    patches = [
        int(found.group(1))
        for name in tag_names
        if (found := pattern.fullmatch(name.strip())) is not None
    ]
    patch = max(patches) + 1 if patches else 0
    release = f"{prefix}.{patch}"
    return BundleVersion(marketing=release, build=build.strip(), display=release)


def git_output(repo: Path, args: Sequence[str]) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def version_for_worktree(repo: Path) -> BundleVersion:
    description = git_output(
        repo,
        [
            "describe",
            "--tags",
            "--match",
            "v[0-9]*.[0-9]*.[0-9]*",
            "--long",
            "--dirty",
        ],
    )
    build = git_output(repo, ["rev-list", "--count", "HEAD"])
    return development_version(description, build)


def release_train(plist_path: Path) -> str:
    with plist_path.open("rb") as handle:
        info = plistlib.load(handle)
    train = info.get(RELEASE_TRAIN_KEY)
    if not isinstance(train, str):
        raise ValueError(f"{plist_path} has no string {RELEASE_TRAIN_KEY}")
    return train


def stamp_plist(source: Path, destination: Path, version: BundleVersion) -> None:
    with source.open("rb") as handle:
        info = plistlib.load(handle)
    info["CFBundleShortVersionString"] = version.marketing
    info["CFBundleVersion"] = version.build
    info[DISPLAY_VERSION_KEY] = version.display
    with destination.open("wb") as handle:
        plistlib.dump(info, handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Stamp a development app version.")
    parser.add_argument("source", type=Path, help="template Info.plist")
    parser.add_argument("destination", type=Path, help="assembled app Info.plist")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()

    version = version_for_worktree(args.repo)
    stamp_plist(args.source, args.destination, version)
    print(f"{version.display} ({version.build})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
