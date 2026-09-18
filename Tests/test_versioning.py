import plistlib
from pathlib import Path
import tempfile
import unittest

from versioning import (
    DISPLAY_VERSION_KEY,
    BundleVersion,
    development_version,
    next_release_version,
    stamp_plist,
)


class VersioningTests(unittest.TestCase):
    def test_development_version_uses_standard_git_description(self):
        version = development_version("v1.1.2-3-gabc1234", "31")
        self.assertEqual(
            version,
            BundleVersion("1.1.2", "31", "1.1.2-3-gabc1234"),
        )

    def test_dirty_development_version_keeps_the_marker(self):
        version = development_version("v1.1.2-0-gabc1234-dirty", "28")
        self.assertEqual(version.display, "1.1.2-0-gabc1234-dirty")

    def test_clean_tag_displays_as_an_exact_release(self):
        version = development_version("v1.1.3-0-gabc1234", "32")
        self.assertEqual(version.display, "1.1.3")

    def test_next_release_uses_highest_matching_published_patch(self):
        version = next_release_version(
            "1.1", ["v1.1.0", "v1.1.2", "v2.0.9", "v1.1.beta"], "32"
        )
        self.assertEqual(version, BundleVersion("1.1.3", "32", "1.1.3"))

    def test_stamped_plist_keeps_apple_versions_numeric(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.plist"
            destination = Path(directory) / "destination.plist"
            with source.open("wb") as handle:
                plistlib.dump({"CFBundleName": "Tokens on Track"}, handle)

            stamp_plist(
                source,
                destination,
                BundleVersion("1.1.2", "31", "1.1.2-3-gabc1234"),
            )
            with destination.open("rb") as handle:
                stamped = plistlib.load(handle)

        self.assertEqual(stamped["CFBundleShortVersionString"], "1.1.2")
        self.assertEqual(stamped["CFBundleVersion"], "31")
        self.assertEqual(stamped[DISPLAY_VERSION_KEY], "1.1.2-3-gabc1234")


if __name__ == "__main__":
    unittest.main()
