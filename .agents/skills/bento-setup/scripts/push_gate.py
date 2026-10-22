#!/usr/bin/env python3
"""Pre-PR review gate: a PreToolUse hook (Claude Code and Codex) on shell commands.

Blocks `git push` and `gh pr create` unless bento-adversarial-review's recorded sha
(`git rev-parse --git-path adversarial-review.head`) is HEAD, or is followed only by that
review's own fix commits. Allowed without a record when the repo's bento-ship overlay says
`- Pre-PR review: skip`, or the command carries `BENTO_PRE_PR_REVIEW=skip` (a review the
user skipped for this run). Not a repo, unreadable input or an unparsable command → allow:
this gate catches a skipped ship flow, it is not a security boundary.

Usage:
  push_gate.py                                  hook: tool-call JSON on stdin, exit 2 blocks
  push_gate.py install <hooks.json>    (Claude settings.json or Codex hooks.json)
  push_gate.py uninstall <hooks.json>
"""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

MESSAGE = "Run bento-ship first: no pre-PR review recorded for HEAD."
BYPASS = "BENTO_PRE_PR_REVIEW=skip"
FIX_SUBJECT = "fix: address adversarial review findings"  # bento-adversarial-review ship mode
GIT_ARG_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
PUNCT = set("();<>|&")


def git_push_repo(tokens: list[str], i: int, here: str) -> str | None:
    """The repo of the `git` at tokens[i] when its subcommand is `push`, else None."""
    repo, j = here, i + 1
    while j < len(tokens) and tokens[j].startswith("-"):
        if tokens[j] == "-C" and j + 1 < len(tokens):
            repo = os.path.join(here, tokens[j + 1])
        j += 2 if tokens[j] in GIT_ARG_OPTS else 1
    return repo if tokens[j:j + 1] == ["push"] else None


def tokenize(command: str) -> tuple[list[str], set[int]] | None:
    """Unquoted tokens, and the indices of shell operators (unquoted punctuation runs)."""
    lex = shlex.shlex(command, posix=False, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        raw = list(lex)
        ops = {i for i, tok in enumerate(raw) if set(tok) <= PUNCT}
        return [tok if i in ops else "".join(shlex.split(tok)) for i, tok in enumerate(raw)], ops
    except ValueError:  # unbalanced quotes, e.g. an apostrophe in a heredoc
        return None


def step_dir(tokens: list[str], i: int, here: str, saved: list[str], op: bool) -> str:
    """The directory after tokens[i]: `cd` changes it, a `( … )` subshell restores it."""
    tok = tokens[i]
    if tok == "cd" and i + 1 < len(tokens):
        return os.path.join(here, os.path.expanduser(tokens[i + 1]))
    for ch in tok if op else "":
        if ch == "(":
            saved.append(here)
        elif ch == ")" and saved:
            here = saved.pop()
    return here


def is_script(tokens: list[str], i: int) -> bool:
    """tokens[i] is a script run by `eval` or `bash -c` (`-lc`, …)."""
    prev = tokens[i - 1] if i else ""
    shell = os.path.basename(tokens[i - 2]) in SHELLS if i > 1 else False
    return prev == "eval" or (shell and re.fullmatch(r"-[a-z]*c", prev) is not None)


def gated_at(tokens: list[str], i: int, here: str) -> list[str]:
    tok = tokens[i]
    if os.path.basename(tok) == "git":
        repo = git_push_repo(tokens, i, here)
        return [repo] if repo else []
    if tok == "gh" and tokens[i + 1:i + 3] == ["pr", "create"]:
        return [here]
    return gated_dirs(tok, here) if is_script(tokens, i) else []


def gated_dirs(command: str, cwd: str) -> list[str]:
    """The directory of each `git push` / `gh pr create` in a shell command, following `cd`."""
    if BYPASS in command:
        return []
    parsed = tokenize(command)
    if parsed is None:  # match the raw text
        return [cwd] if re.search(r"\bgit(\s+-\S+)*\s+push\b|\bgh\s+pr\s+create\b", command) else []
    tokens, ops = parsed
    out: list[str] = []
    here, saved = cwd, list[str]()
    for i in range(len(tokens)):
        here = step_dir(tokens, i, here, saved, i in ops)
        out += gated_at(tokens, i, here)
    return out


def review_skipped(top: str) -> bool:
    """The repo's bento-ship overlay records `Pre-PR review: skip`."""
    overlay = Path(top, ".agents/bento/bento-ship.md")
    return overlay.is_file() and bool(
        re.search(r"^- Pre-PR review:\s*skip\s*$", overlay.read_text(), re.M | re.I))


def reviewed(repo: str) -> bool:
    """True when HEAD needs no further pre-PR review before it leaves this machine."""
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)

    top = git("rev-parse", "--show-toplevel")
    if top.returncode or review_skipped(top.stdout.strip()):
        return True  # not a repo (nothing to push), or the repo opted out
    try:
        sha = Path(repo, git("rev-parse", "--git-path", "adversarial-review.head").stdout.strip()).read_text().strip()
    except OSError:
        return False
    head = git("rev-parse", "HEAD").stdout.strip()
    recorded = git("rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}").stdout.strip()
    if not recorded or recorded == head:
        return bool(recorded)
    if git("merge-base", "--is-ancestor", recorded, "HEAD").returncode:
        return False
    # Fix commits the review made after its recorded sha were triaged from its own findings.
    log = git("log", "--format=%P%x09%s", f"{recorded}..HEAD").stdout.splitlines()
    return all(" " not in parents and subject == FIX_SUBJECT
               for parents, _, subject in (line.partition("\t") for line in log))


def hook() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("tool_name", "Bash") != "Bash":  # Codex sends apply_patch text as a command
            return 0
        command = event.get("tool_input", {}).get("command")
        if isinstance(command, list):  # an argv, e.g. ["bash", "-lc", "git push"]
            command = " ".join(command)
        dirs = gated_dirs(command, event.get("cwd") or os.getcwd()) if isinstance(command, str) else []
    except (ValueError, AttributeError):  # not a tool-call JSON
        return 0
    if all(reviewed(d) for d in dirs):
        return 0
    print(MESSAGE, file=sys.stderr)
    return 2


def ours(handler: dict) -> bool:
    return "push_gate.py" in handler.get("command", "")


def without_ours(groups: list) -> list:
    """The groups minus this gate's handlers; a group left with no handler is dropped."""
    out = []
    for group in groups:
        kept = [h for h in group.get("hooks", []) if not ours(h)]
        if kept or not group.get("hooks"):
            out.append({**group, "hooks": kept})
    return out


def hook_command() -> str:
    """This script, repo-relative when it lives in the current repo (project scope), else absolute."""
    script = Path(__file__).resolve()
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
    if top and script.is_relative_to(Path(top).resolve()):
        rel = script.relative_to(Path(top).resolve())
        path = f'"${{CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}}/{rel}"'
    else:
        path = shlex.quote(str(script))
    # A missing script must not block every shell command (python3 exits 2 on a file it can't
    # open, which means block): fail with a visible, non-blocking error instead.
    return (f'f={path}; if [ -f "$f" ]; then python3 "$f"; else '
            'echo "bento: pre-PR review gate missing at $f; rerun bento-setup" >&2; exit 1; fi')


def edit(path: Path, change) -> str:
    text = path.read_text() if path.exists() else ""
    data = json.loads(text) if text.strip() else {}
    groups = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
    action = change(groups)
    if not groups:
        del data["hooks"]["PreToolUse"]
    if not data["hooks"]:
        del data["hooks"]
    if action != "unchanged":
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")
    return action


def install(path: Path) -> str:
    entry = {"matcher": "Bash", "hooks": [{"type": "command", "command": hook_command()}]}

    def change(groups: list) -> str:
        others = without_ours(groups)
        if groups == others + [entry]:
            return "unchanged"
        action = "added" if others == groups else "updated"
        groups[:] = others + [entry]
        return action
    return edit(path, change)


def uninstall(path: Path) -> str:
    def change(groups: list) -> str:
        others = without_ours(groups)
        action = "unchanged" if others == groups else "removed"
        groups[:] = others
        return action
    return edit(path, change) if path.exists() else "unchanged"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        return hook()
    if args[0] == "install" and len(args) == 2:
        print(f"bento: {install(Path(args[1]))} pre-PR review gate in {args[1]}")
        return 0
    if args[0] == "uninstall" and len(args) == 2:
        print(f"bento: {uninstall(Path(args[1]))} pre-PR review gate in {args[1]}")
        return 0
    print(__doc__, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
