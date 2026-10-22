import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from push_gate import FIX_SUBJECT, MESSAGE, gated_dirs, hook_command, install, reviewed, uninstall

SCRIPT = Path(__file__).resolve().parent / "push_gate.py"


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


class GatedDirsTest(unittest.TestCase):
    def test_finds_push_and_pr_create(self):
        self.assertEqual(gated_dirs("git push -u origin HEAD", "/r"), ["/r"])
        self.assertEqual(gated_dirs("git -C sub -c x=y push", "/r"), ["/r/sub"])
        self.assertEqual(gated_dirs("cd /a && git status&&gh pr create --fill", "/r"), ["/a"])
        self.assertEqual(gated_dirs("bash -lc git push origin", "/r"), ["/r"])
        self.assertEqual(gated_dirs("git commit -F - <<'EOF'\nIt's done\nEOF\ngit push", "/r"), ["/r"])
        self.assertEqual(gated_dirs('bash -lc "cd sub && git push"', "/r"), ["/r/sub"])
        self.assertEqual(gated_dirs("eval 'gh pr create --fill'", "/r"), ["/r"])
        self.assertEqual(gated_dirs("(cd /tmp); git push", "/r"), ["/r"])
        self.assertEqual(gated_dirs('cd /t && printf "(" && cd /a && printf ")" && git push', "/r"), ["/a"])
        self.assertEqual(gated_dirs('git -C "my dir" push', "/r"), ["/r/my dir"])

    def test_ignores_other_commands_and_the_bypass(self):
        self.assertEqual(gated_dirs('git commit -m "push it"', "/r"), [])
        self.assertEqual(gated_dirs("git log --grep push; gh pr view", "/r"), [])
        self.assertEqual(gated_dirs("BENTO_PRE_PR_REVIEW=skip git push", "/r"), [])


class ReviewedTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        git(self.repo, "init", "-q")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")

    def commit(self, subject):
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", subject)

    def record(self, rev="HEAD"):
        (self.repo / git(self.repo, "rev-parse", "--git-path", "adversarial-review.head")).write_text(
            git(self.repo, "rev-parse", rev) + "\n")

    def test_needs_a_record_of_head(self):
        self.assertFalse(reviewed(str(self.repo)))
        self.record()
        self.assertTrue(reviewed(str(self.repo)))

    def test_only_the_reviews_fix_commits_may_follow(self):
        self.record()
        self.commit(FIX_SUBJECT)
        self.assertTrue(reviewed(str(self.repo)))
        self.commit("feat: unreviewed")
        self.assertFalse(reviewed(str(self.repo)))

    def test_overlay_skip_and_non_repo(self):
        overlay = self.repo / ".agents/bento/bento-ship.md"
        overlay.parent.mkdir(parents=True)
        overlay.write_text("- Pre-PR review: always\n")
        self.assertFalse(reviewed(str(self.repo)))
        overlay.write_text("- Pre-PR review: skip\n")
        self.assertTrue(reviewed(str(self.repo)))
        self.assertTrue(reviewed(tempfile.mkdtemp()))

    def test_hook_blocks_with_exit_2(self):
        patch = json.dumps({"tool_name": "apply_patch", "tool_input": {"command": "+git push"},
                            "cwd": str(self.repo)})
        run = subprocess.run([sys.executable, str(SCRIPT)], input=patch, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)
        event = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push"}, "cwd": str(self.repo)})
        run = subprocess.run([sys.executable, str(SCRIPT)], input=event, capture_output=True, text=True)
        self.assertEqual((run.returncode, run.stderr.strip()), (2, MESSAGE))
        self.record()
        run = subprocess.run([sys.executable, str(SCRIPT)], input=event, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)


class InstallTest(unittest.TestCase):
    def test_idempotent_and_keeps_other_hooks(self):
        path = Path(tempfile.mkdtemp()) / "settings.json"
        other = {"type": "command", "command": "other.sh"}
        stale = {"type": "command", "command": "python3 old/push_gate.py"}
        path.write_text(json.dumps({"model": "x", "hooks": {"PreToolUse": [
            {"matcher": "Bash", "hooks": [other, stale]}]}}))
        self.assertEqual(install(path), "updated")
        self.assertEqual(install(path), "unchanged")
        groups = json.loads(path.read_text())["hooks"]["PreToolUse"]
        self.assertEqual(groups[0], {"matcher": "Bash", "hooks": [other]})
        self.assertEqual(len(groups), 2)
        self.assertEqual(uninstall(path), "removed")
        self.assertEqual(json.loads(path.read_text()),
                         {"model": "x", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [other]}]}})
        self.assertEqual(uninstall(path), "unchanged")
        empty = path.with_name("hooks.json")
        self.assertEqual(install(empty), "added")

    def test_missing_script_warns_without_blocking(self):
        command = hook_command().replace("push_gate.py", "gone.py")
        run = subprocess.run(["bash", "-c", command], input="{}", capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertIn("rerun bento-setup", run.stderr)


if __name__ == "__main__":
    unittest.main()
