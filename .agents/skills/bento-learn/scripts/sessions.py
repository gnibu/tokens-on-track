#!/usr/bin/env python3
"""Print the learnable part of every Claude and Codex session run in this worktree.

Usage: sessions.py [--repo PATH] [--since EPOCH_SECONDS]

Selects transcripts whose cwd is inside the worktree and that were active since the
current branch was created (its oldest reflog entry; else its merge-base with
origin/HEAD). Conductor-style workspaces reuse directories across branches, so the
time window matters as much as the path. For each session, oldest first, prints the
transcript path, then operator turns (U), failed tool calls (ERR) and blocking hook
errors (HOOK). Those are ~3% of transcript bytes and carry the Reflect signal; open
the printed path when a session needs more context.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

INJECTED = [re.compile(p, re.S) for p in (
    r"<(system_instruction|system-reminder|user-preferences|local-command-stdout|"
    r"environment_context|recommended_plugins|user_instructions)>.*?</\1>",
    r"# AGENTS\.md instructions for [^\n]*\s*<INSTRUCTIONS>.*?</INSTRUCTIONS>",
)]


def clean(text):
    for pattern in INJECTED:
        text = pattern.sub("", text)
    return text.strip()


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def branch_start(repo):
    branch = git(repo, "symbolic-ref", "-q", "HEAD")
    reflog = git(repo, "reflog", "show", "--format=%ct", branch) if branch else ""
    if reflog:
        return int(reflog.splitlines()[-1])
    base = git(repo, "merge-base", "HEAD", "origin/HEAD")
    return int(git(repo, "show", "-s", "--format=%ct", base) or 0) if base else 0


def records(path):
    with path.open(errors="replace") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict):
                yield record


def session_cwd(path):
    for record in records(path):
        cwd = record.get("cwd") or (record.get("payload") or {}).get("cwd")
        if cwd:
            return cwd
    return None


def signal(record):
    """Yield (tag, text) for one Claude or Codex transcript record."""
    kind, payload = record.get("type"), record.get("payload") or {}
    content = (record.get("message") or {}).get("content")
    if kind == "user" and not record.get("isMeta") and isinstance(content, str):
        yield "U", clean(content)[:2000]
    elif kind == "user" and isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result" and item.get("is_error"):
                yield "ERR", str(item.get("content"))[:600]
    elif kind == "attachment" and (record.get("attachment") or {}).get("type") == "hook_blocking_error":
        yield "HOOK", str(record["attachment"])[:600]
    elif kind == "response_item" and payload.get("type") == "message" and payload.get("role") == "user":
        text = "\n".join(c.get("text", "") for c in payload.get("content") or []
                         if isinstance(c, dict) and c.get("type") == "input_text")
        yield "U", clean(text)[:2000]
    elif kind == "response_item" and payload.get("type") == "custom_tool_call_output":
        text = "\n".join(str(c.get("text", "")) for c in payload.get("output") or [] if isinstance(c, dict))
        if re.match(r"(Script failed|Script error:)", text):
            yield "ERR", text[:600]
    elif kind == "event_msg" and payload.get("type") == "item_completed":
        item = payload.get("item") or {}
        if item.get("status") == "failed":
            yield "ERR", str(item.get("aggregated_output") or item.get("stderr") or item)[:600]


def transcripts(root, since):
    claude = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "projects"
    mangled = re.sub(r"[^A-Za-z0-9]", "-", str(root))
    found = [("claude", path) for folder in (claude.iterdir() if claude.is_dir() else [])
             if folder.name == mangled or folder.name.startswith(mangled + "-")
             for path in folder.glob("*.jsonl")]
    codex = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "sessions"
    found += [("codex", path) for path in codex.glob("**/rollout-*.jsonl")]
    for agent, path in sorted(found, key=lambda item: item[1].stat().st_mtime):
        if path.stat().st_mtime < since:
            continue
        cwd = session_cwd(path)
        if cwd and (cwd == str(root) or cwd.startswith(f"{root}/")):
            yield agent, path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--since", type=int, help="epoch seconds (default: branch creation)")
    args = parser.parse_args()
    root = git(args.repo, "rev-parse", "--show-toplevel")
    if not root:
        print(f"sessions.py: not a git worktree: {args.repo}", file=sys.stderr)
        return 1
    root = Path(root).resolve()
    since = branch_start(root) if args.since is None else args.since
    count = 0
    for agent, path in transcripts(root, since):
        lines = [f"{tag}: {text}" for record in records(path) for tag, text in signal(record) if text]
        if any(line.startswith("U: ") for line in lines):
            count += 1
            print(f"=== {agent} session {path}\n" + "\n".join(lines) + "\n")
    print(f"sessions.py: {count} session(s) in {root} since {since}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
