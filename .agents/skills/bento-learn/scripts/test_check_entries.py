"""Tests for check_entries.py: which new instruction-file entries are rejected."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from check_entries import check, entries, menu_gaps

SCRIPT = Path(__file__).with_name("check_entries.py")
LONG = "Run the full suite with the database container up, then the browser tests, " \
       "then the linter, and only then the type checker, because"


class CheckEntriesTests(unittest.TestCase):
    def test_splits_bullets_paragraphs_and_code_blocks(self):
        text = "# Title\n\n- one\n  wrapped\n- two\n\npara\ngraph\n<!-- note -->\n```\nmake\n- x\n```\n"
        self.assertEqual(entries(text), ["- one wrapped", "- two", "para graph", "``` make - x ```"])

    def test_short_fact_passes_without_pointer(self):
        self.assertEqual(check("", "- Base branch: `main`.\n"), [])

    def test_two_lines_need_a_pointer(self):
        bare = f"- **Testing:** {LONG}.\n"
        self.assertEqual(len(check("", bare)), 1)
        self.assertEqual(check("", f"- **Testing:** {LONG[:60]}. See docs/procedures/run-tests.md.\n"), [])
        self.assertEqual(check("", f"- **Testing:** {LONG[:60]}. See [guide](guide).\n"), [])

    def test_over_two_lines_rejected_even_with_pointer(self):
        rejected = check("", f"- **Testing:** {LONG} {LONG}. See docs/procedures/run-tests.md.\n")
        self.assertIn("over two lines", rejected[0][1])

    def test_procedure_code_block_rejected(self):
        block = "```sh\n" + "\n".join(f"step-{i} --with-a-flag --and-another" for i in range(6)) + "\n```\n"
        self.assertEqual(len(check("", block)), 1)

    def test_only_new_or_changed_entries_are_checked(self):
        old = f"- {LONG} {LONG}\n"
        self.assertEqual(check(old, old + "- Base branch: `main`.\n"), [])
        self.assertEqual(len(check(old, old.replace("Run", "Start"))), 1)

    def test_menu_names_every_doc_by_file_or_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("docs/procedures/run-tests.md", "docs/briefs/a.md", "docs/briefs/b.md",
                         "docs/DEPLOY.md"):
                Path(root, name).parent.mkdir(parents=True, exist_ok=True)
                Path(root, name).write_text("x")
            menu = "## Docs\n\n- Running tests → docs/procedures/run-tests.md\n- Briefs → docs/briefs/\n"
            self.assertEqual(menu_gaps(root, menu), ["docs/DEPLOY.md"])
            self.assertEqual(menu_gaps(root, "See docs/ for everything."), [
                "docs/DEPLOY.md", "docs/briefs/a.md", "docs/briefs/b.md", "docs/procedures/run-tests.md"])
            # A file link doesn't name its folder, and a proposed doc must be listed too.
            self.assertEqual(menu_gaps(root, menu + "- Deploying → docs/DEPLOY.md\n",
                                       ["docs/procedures/release.md"]), ["docs/procedures/release.md"])

    def test_only_the_docs_section_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "docs").mkdir()
            Path(tmp, "docs", "DEPLOY.md").write_text("x")
            self.assertEqual(menu_gaps(Path(tmp), "- Deploy per docs/DEPLOY.md.\n"), ["docs/DEPLOY.md"])
            menu = "## Docs\n\n- Deploying → docs/DEPLOY.md.\n\n## Other\n"
            self.assertEqual(menu_gaps(Path(tmp), menu), [])
            self.assertEqual(menu_gaps(Path(tmp), "## Docs\n\n## Other\n- docs/DEPLOY.md\n"),
                             ["docs/DEPLOY.md"])

    def test_no_docs_dir_still_checks_proposed_docs(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(menu_gaps(Path(tmp), "- x\n"), [])
            self.assertEqual(menu_gaps(Path(tmp), "- x\n", ["docs/procedures/run-tests.md"]),
                             ["docs/procedures/run-tests.md"])

    def test_cli_exit_codes_and_missing_current_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            proposed = Path(tmp, "proposed.md")
            missing = Path(tmp, "pkg", "AGENTS.md")
            proposed.write_text("- Base branch: `main`.\n")
            run = lambda: subprocess.run([sys.executable, SCRIPT, missing, proposed],
                                         capture_output=True, text=True)
            self.assertEqual(run().returncode, 0)
            proposed.write_text(f"- {LONG} {LONG}\n")
            result = run()
            self.assertEqual(result.returncode, 1)
            self.assertIn("over two lines", result.stdout)
            Path(tmp, "docs").mkdir()
            Path(tmp, "docs", "DEPLOY.md").write_text("x")
            agents = Path(tmp, "AGENTS.md")
            proposed.write_text("- Base branch: `main`.\n")
            result = subprocess.run([sys.executable, SCRIPT, agents, proposed], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("menu misses docs/DEPLOY.md", result.stdout)


if __name__ == "__main__":
    unittest.main()
