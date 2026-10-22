"""Exercise the L2 CLI against real Git repos and merge-file, without an LLM."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).with_name("l2-state.py")
spec = importlib.util.spec_from_file_location("l2_state", SCRIPT)
l2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(l2)


class L2StateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bento-l2-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo with spaces"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.files = {
            "AGENTS.md": "".join(f"Rule {n}\n" for n in range(15)),
            "CLAUDE.md": "@AGENTS.md\n",
            "docs/workflow.md": "# Workflow\n\nRun the checks.\n",
            ".claude/skills/check/SKILL.md": "---\nname: check\n---\nRead docs/workflow.md.\n",
        }

    def proposal(self, files):
        path = self.root / "proposal.json"
        path.write_text(json.dumps({"schema_version": 1, "files": files}))
        return str(path)

    def cli(self, *args, expected=0):
        result = subprocess.run([sys.executable, str(SCRIPT), "--repo", str(self.repo), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def init(self):
        self.cli("init", self.proposal(self.files), "--apply")

    def snapshot(self):
        return {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob("*")
                if p.is_file() and ".git" not in p.relative_to(self.repo).parts}

    def baseline(self):
        return json.loads((self.repo / l2.BASELINE).read_text())["files"]

    def test_preview_is_read_only_then_apply_records_baseline(self):
        before = self.snapshot()
        out = self.cli("init", self.proposal(self.files))
        self.assertIn("proposed/AGENTS.md", out)
        self.assertEqual(before, self.snapshot())
        self.init()
        self.assertEqual(self.baseline(), self.files)
        for name, text in self.files.items():
            self.assertEqual((self.repo / name).read_text(), text)
        self.assertEqual((self.repo / "CLAUDE.md").read_text(), "@AGENTS.md\n")

    def test_reinit_refuses_without_modification(self):
        self.init()
        before = self.snapshot()
        out = self.cli("init", self.proposal(self.files), "--apply", expected=1)
        self.assertIn("bento-learn", out)
        self.assertEqual(before, self.snapshot())

    def test_existing_nested_untracked_l2_refuses(self):
        (self.repo / "src").mkdir()
        (self.repo / "src/AGENTS.md").write_text("Manual instructions\n")
        before = self.snapshot()
        self.cli("check", expected=1)
        self.cli("init", self.proposal(self.files), "--apply", expected=1)
        self.assertEqual(before, self.snapshot())

    def test_existing_skills_refuse(self):
        (self.repo / ".agents/skills").mkdir(parents=True)
        self.cli("check", expected=1)

    def test_tracked_but_deleted_instructions_are_not_greenfield(self):
        path = self.repo / "AGENTS.md"
        path.write_text("Manual instructions\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "AGENTS.md"], check=True)
        path.unlink()
        self.cli("check", expected=1)
        self.cli("init", self.proposal(self.files), "--apply", expected=1)
        self.assertFalse(path.exists())

    def test_existing_claude_rules_refuse(self):
        (self.repo / ".claude/rules").mkdir(parents=True)
        (self.repo / ".claude/rules/testing.md").write_text("Run tests\n")
        self.cli("check", expected=1)

    def test_mcp_config_and_vendored_l1_do_not_block_init(self):
        (self.repo / ".claude").mkdir()
        (self.repo / ".claude/settings.local.json").write_text('{}\n')
        (self.repo / ".mcp.json").write_text('{}\n')
        for agent in (".agents", ".claude"):
            (self.repo / agent / "skills/bento-ship").mkdir(parents=True)
            (self.repo / agent / "skills/bento-ship/SKILL.md").write_text("Shared L1\n")
        self.cli("check")
        self.init()
        self.assertEqual((self.repo / ".agents/skills/bento-ship/SKILL.md").read_text(), "Shared L1\n")
        (self.repo / ".agents/skills/own").mkdir()
        self.cli("check", expected=1)

    def test_claude_skills_dir_link_is_inspected_through_its_target(self):
        (self.repo / ".agents/skills/bento-ship").mkdir(parents=True)
        (self.repo / ".agents/skills/bento-ship/SKILL.md").write_text("Shared L1\n")
        (self.repo / ".claude").mkdir()
        (self.repo / ".claude/skills").symlink_to("../.agents/skills", target_is_directory=True)
        subprocess.run(["git", "-C", str(self.repo), "add", "-A"], check=True)
        self.cli("check")
        (self.repo / ".claude/skills").unlink()
        (self.repo / ".claude/skills").symlink_to("bento-ship", target_is_directory=True)
        self.assertIn(".claude/skills", self.cli("check", expected=1))
        (self.repo / ".claude/skills").unlink()
        (self.repo / ".claude/skills").symlink_to("../.agents/skills", target_is_directory=True)
        self.files[".agents/skills/check/SKILL.md"] = self.files.pop(".claude/skills/check/SKILL.md")
        self.init()
        self.assertIn("name: check", (self.repo / ".claude/skills/check/SKILL.md").read_text())

    def test_existing_doc_is_not_overwritten(self):
        (self.repo / "docs").mkdir()
        (self.repo / "docs/workflow.md").write_text("Manual guide\n")
        before = self.snapshot()
        self.cli("init", self.proposal(self.files), "--apply", expected=1)
        self.assertEqual(before, self.snapshot())

    def test_both_agent_entry_points_required(self):
        self.cli("init", self.proposal({"AGENTS.md": "Only one agent\n"}), "--apply", expected=1)
        self.assertEqual(self.snapshot(), {})

    def test_three_way_merge_preserves_hand_edits_across_updates(self):
        self.init()
        path = self.repo / "AGENTS.md"
        current = self.files["AGENTS.md"].replace("Rule 1\n", "Human rule\n")
        path.write_text(current)
        incoming = self.files["AGENTS.md"].replace("Rule 13\n", "Generated rule\n")
        proposal = self.proposal({"AGENTS.md": incoming})
        before = self.snapshot()
        self.cli("merge", proposal)
        self.assertEqual(before, self.snapshot())
        self.cli("merge", proposal, "--apply")
        self.assertEqual(path.read_text(), current.replace("Rule 13\n", "Generated rule\n"))
        self.assertEqual(self.baseline()["AGENTS.md"], incoming)
        self.assertNotIn("Human rule", self.baseline()["AGENTS.md"])
        self.assertEqual(self.baseline()["CLAUDE.md"], self.files["CLAUDE.md"])
        before = self.snapshot()
        self.assertIn("Applied 0 file(s)", self.cli("merge", proposal, "--apply"))
        self.assertEqual(before, self.snapshot())
        next_incoming = incoming.replace("Generated rule", "Second generated rule")
        self.cli("merge", self.proposal({"AGENTS.md": next_incoming}), "--apply")
        self.assertIn("Human rule", path.read_text())
        self.assertIn("Second generated rule", path.read_text())
        self.assertEqual(self.baseline()["AGENTS.md"], next_incoming)

    def test_unchanged_proposal_keeps_manual_deletions_inside_file(self):
        self.init()
        path = self.repo / "AGENTS.md"
        path.write_text("")
        before = self.snapshot()
        self.cli("merge", self.proposal({"AGENTS.md": self.files["AGENTS.md"]}), "--apply")
        self.assertEqual(before, self.snapshot())

    def test_conflict_writes_neither_clean_files_nor_baseline(self):
        self.init()
        path = self.repo / "AGENTS.md"
        path.write_text(self.files["AGENTS.md"].replace("Rule 1", "Human rule"))
        incoming = self.files["AGENTS.md"].replace("Rule 1", "Agent rule")
        before = self.snapshot()
        out = self.cli("merge", self.proposal({"AGENTS.md": incoming,
                       "docs/workflow.md": "New workflow\n"}), "--apply", expected=1)
        self.assertIn("CONFLICT: AGENTS.md", out)
        self.assertIn("<<<<<<< current", out)
        self.assertIn("||||||| baseline", out)
        self.assertIn(">>>>>>> proposed", out)
        self.assertEqual(before, self.snapshot())

    def test_missing_baseline_does_not_adopt_existing_files(self):
        (self.repo / "AGENTS.md").write_text("Manual\n")
        before = self.snapshot()
        self.cli("merge", self.proposal({"AGENTS.md": "Generated\n"}), "--apply", expected=1)
        self.assertEqual(before, self.snapshot())

    def test_missing_managed_file_is_not_resurrected(self):
        self.init()
        (self.repo / "AGENTS.md").unlink()
        before = self.snapshot()
        self.cli("merge", self.proposal({"AGENTS.md": "Generated\n"}), "--apply", expected=1)
        self.assertEqual(before, self.snapshot())

    def test_unknown_managed_path_is_not_added(self):
        self.init()
        before = self.snapshot()
        self.cli("merge", self.proposal({"docs/new.md": "New\n"}), "--apply", expected=1)
        self.assertEqual(before, self.snapshot())

    def test_diff_discloses_missing_trailing_newline(self):
        self.init()
        out = self.cli("merge", self.proposal({"docs/workflow.md": "No newline"}))
        self.assertIn("+No newline\n\\ No newline at end of file", out)

    def test_file_mode_is_preserved(self):
        self.init()
        path = self.repo / "docs/workflow.md"
        path.chmod(0o600)
        self.cli("merge", self.proposal({"docs/workflow.md": "New workflow\n"}), "--apply")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_unsafe_proposals_write_nothing(self):
        variants = [
            {"../AGENTS.md": "escape"}, {"/tmp/AGENTS.md": "absolute"},
            {"docs/../AGENTS.md": "traversal"}, {"docs//a.md": "noncanonical"},
            {".agents/skills/bento-ship/SKILL.md": "L1"}, {".git/AGENTS.md": "git"},
            {"src/main.py": "code"}, {".claude/settings.json": "settings"},
            {"docs/Foo.md": "a", "docs/foo.md": "b"},
            {"docs/a.md": "a", "docs/a.md/AGENTS.md": "b"},
            {"docs/a.md": None}, {"docs/a.md": "nul\0"},
        ]
        for extra in variants:
            with self.subTest(extra=extra):
                before = self.snapshot()
                self.cli("init", self.proposal(dict(self.files, **extra)), "--apply", expected=1)
                self.assertEqual(before, self.snapshot())

    def test_symlinked_target_parent_and_state_refuse(self):
        outside = self.root / "outside"
        outside.mkdir()
        for name in ["docs", ".bento-state", ".claude"]:
            with self.subTest(name=name):
                path = self.repo / name
                path.symlink_to(outside, target_is_directory=True)
                self.cli("init", self.proposal(self.files), "--apply", expected=1)
                self.assertEqual(list(outside.iterdir()), [])
                path.unlink()
        self.init()
        path = self.repo / "AGENTS.md"
        path.unlink()
        target = outside / "target.md"
        target.write_text("Manual\n")
        path.symlink_to(target)
        self.cli("merge", self.proposal({"AGENTS.md": "Generated\n"}), "--apply", expected=1)
        self.assertEqual(target.read_text(), "Manual\n")

    def test_malformed_or_future_baseline_refuses(self):
        self.init()
        state = self.repo / l2.BASELINE
        for content in ['broken', '{"schema_version":2,"files":{"AGENTS.md":"x"}}',
                        '{"schema_version":1,"files":{"AGENTS.md":"a","AGENTS.md":"b"}}']:
            with self.subTest(content=content):
                state.write_text(content)
                before = self.snapshot()
                self.cli("merge", self.proposal({"AGENTS.md": "Generated\n"}), "--apply", expected=1)
                self.assertEqual(before, self.snapshot())

    def test_lock_prevents_overlapping_writes(self):
        lock = self.repo / ".git/bento-l2.lock"
        lock.write_text("other process\n")
        self.cli("init", self.proposal(self.files), "--apply", expected=1)
        self.assertEqual(self.snapshot(), {})
        self.assertEqual(lock.read_text(), "other process\n")

    def test_changed_snapshot_refuses_whole_write(self):
        path = self.repo / "AGENTS.md"
        path.write_text("New human edit\n")
        with self.assertRaisesRegex(l2.Invalid, "changed during planning"):
            l2.apply_files(self.repo, {"AGENTS.md": b"Generated\n"},
                           {"AGENTS.md": b"Old text\n"})
        self.assertEqual(path.read_text(), "New human edit\n")

    def test_write_failure_rolls_back_files_and_baseline(self):
        self.init()
        before = self.snapshot()
        changes = {"AGENTS.md": b"New\n", l2.BASELINE: b"New state\n"}
        expected = {name: (self.repo / name).read_bytes() for name in changes}
        original = l2.replace_file

        def fail_on_baseline(path, content, mode):
            if path.name == "baseline.json":
                raise OSError("Simulated full disk")
            return original(path, content, mode)

        with mock.patch.object(l2, "replace_file", side_effect=fail_on_baseline):
            with self.assertRaisesRegex(OSError, "full disk"):
                l2.apply_files(self.repo, changes, expected)
        self.assertEqual(before, self.snapshot())

    def test_linked_worktree_uses_its_own_baseline_and_lock(self):
        (self.repo / "README.md").write_text("Project\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "README.md"], check=True)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=Test", "-c",
                        "user.email=test@example.invalid", "commit", "-qm", "Seed"], check=True)
        worktree = self.root / "linked"
        subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "-q", "--detach", str(worktree)], check=True)
        main = self.repo
        self.repo = worktree
        self.init()
        self.assertEqual(self.baseline(), self.files)
        self.assertFalse((main / l2.BASELINE).exists())


if __name__ == "__main__":
    unittest.main()
