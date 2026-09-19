#!/usr/bin/env python3
"""Generate Xcode's Info.plist using the direct release's versioning rules."""
import os
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from versioning import version_for_worktree


def main():
    version = version_for_worktree(ROOT)
    marketing = os.environ.get("STORE_MARKETING_VERSION") or version.marketing
    build = os.environ.get("STORE_BUILD_NUMBER") or version.build
    if not re.fullmatch(r"\d+\.\d+\.\d+", marketing):
        raise ValueError("STORE_MARKETING_VERSION must have three numeric components")
    if not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("STORE_BUILD_NUMBER must be a positive integer")
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info.update({
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleShortVersionString": marketing,
        "CFBundleVersion": build,
        "TOTDisplayVersion": marketing,
        "LSApplicationCategoryType": "public.app-category.developer-tools",
        "NSHumanReadableCopyright": "Copyright © 2026 Benoit Pothier. MIT licensed.",
    })
    output = Path(os.environ["DERIVED_FILE_DIR"]) / "AppStore-Info.plist"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        plistlib.dump(info, stream)
    print(f"Store version {marketing} ({build})")


if __name__ == "__main__":
    main()
