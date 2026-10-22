"""Fixture tests for sessions.py: worktree/time selection and both transcript shapes."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).with_name("sessions.py")


class SessionsTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="bento sessions ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / "work tree"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.top = subprocess.check_output(["git", "-C", str(self.repo), "rev-parse", "--show-toplevel"],
                                           text=True).strip()
        self.env = {**os.environ, "CLAUDE_CONFIG_DIR": str(self.root / "claude"),
                    "CODEX_HOME": str(self.root / "codex")}
        self.claude_dir = self.root / "claude/projects" / "".join(
            c if c.isalnum() else "-" for c in self.top)

    def write(self, path, rows, age=0):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))
        stamp = time.time() - age
        os.utime(path, (stamp, stamp))
        return path

    def run_script(self, since=None):
        args = [sys.executable, str(SCRIPT), "--repo", str(self.repo)]
        if since is not None:
            args += ["--since", str(since)]
        return subprocess.run(args, env=self.env, capture_output=True, text=True, check=True).stdout

    def test_selects_worktree_sessions_from_both_agents(self):
        cwd = {"cwd": self.top}
        self.write(self.claude_dir / "a.jsonl", [
            {"type": "user", **cwd, "message": {"content": "fix it<system-reminder>noise</system-reminder>"}},
            {"type": "user", "isMeta": True, "message": {"content": "meta"}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": True, "content": "boom"}]}},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "assistant-only"}]}},
        ])
        self.write(self.claude_dir.with_name(self.claude_dir.name + "-sub") / "b.jsonl", [
            {"type": "user", "cwd": self.top + "/src", "message": {"content": "nested"}}])
        self.write(self.claude_dir.with_name(self.claude_dir.name + "-other") / "c.jsonl", [
            {"type": "user", "cwd": self.top + "-other", "message": {"content": "sibling worktree"}}])
        self.write(self.root / "codex/sessions/2026/09/23/rollout-x.jsonl", [
            {"type": "session_meta", "payload": {"cwd": self.top}},
            {"type": "response_item", "payload": {"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": "# AGENTS.md instructions for x\n<INSTRUCTIONS>rules</INSTRUCTIONS>"}]}},
            {"type": "response_item", "payload": {"type": "message", "role": "user", "content": [
                {"type": "input_text", "text": "codex ask"}]}},
            {"type": "event_msg", "payload": {"type": "item_completed",
                                              "item": {"status": "failed", "stderr": "exit 1"}}},
        ])
        out = self.run_script(since=0)
        self.assertIn("U: fix it\nERR: boom", out)
        self.assertIn("U: nested", out)
        self.assertIn("U: codex ask\nERR: exit 1", out)
        for absent in ("noise", "meta", "assistant-only", "sibling worktree", "rules"):
            self.assertNotIn(absent, out)
        self.assertEqual(out.count("=== "), 3)

    def test_sessions_before_since_are_skipped(self):
        self.write(self.claude_dir / "old.jsonl",
                   [{"type": "user", "cwd": self.top, "message": {"content": "old branch"}}], age=3600)
        self.write(self.claude_dir / "new.jsonl",
                   [{"type": "user", "cwd": self.top, "message": {"content": "this branch"}}])
        out = self.run_script(since=int(time.time()) - 60)
        self.assertIn("this branch", out)
        self.assertNotIn("old branch", out)


if __name__ == "__main__":
    unittest.main()
