#!/usr/bin/env python3
"""Preview/apply generated L2 files while preserving edits with git merge-file.

Python 3.9+ and Git; no model, network, or third-party Python dependencies.
See ../references/init.md for the proposal and baseline contract.
"""
import argparse
from contextlib import contextmanager
import difflib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import sys
import tempfile

BASELINE = ".bento-state/baseline.json"
SKIP_DIRS = {".git", ".context", "node_modules", ".venv", "venv",
             "__pycache__", "dist", "build", ".next", "vendor"}


# Installed bento skills (`.agents/skills/bento-*`, `.claude/skills/bento-*`) are L1.
L1_PREFIX = "bento-"


class Invalid(ValueError):
    pass


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True)


def safe_path(repo, name):
    """Never follow symlinks, including parents and the state directory."""
    parts = PurePosixPath(name).parts
    if (not parts or name != str(PurePosixPath(name)) or
            PurePosixPath(name).is_absolute() or ".." in parts or
            "\\" in name or any(ord(c) < 32 for c in name)):
        raise Invalid(f"Not a canonical relative path: {name!r}")
    target = repo
    for part in parts:
        target = target / part
        if target.is_symlink():
            raise Invalid(f"Symlink is not a generated-file target: {name}")
        if target.exists() and target != repo / name and not target.is_dir():
            raise Invalid(f"Parent is not a directory: {name}")
    if target.exists() and (not target.is_file() or target.stat().st_nlink > 1):
        raise Invalid(f"Expected a regular, unlinked file: {name}")
    return target


def managed_path(name):
    if not isinstance(name, str):
        raise Invalid("File paths must be strings")
    p = PurePosixPath(name)
    if any(part.startswith(".") for part in p.parts[:-1]):
        return (len(p.parts) >= 4 and p.parts[:2] in
                ((".claude", "skills"), (".agents", "skills")) and
                not p.parts[2].startswith(L1_PREFIX) and
                all(not part.startswith(".") for part in p.parts[2:]) and p.suffix == ".md")
    return (p.name in {"AGENTS.md", "CLAUDE.md"} or
            (len(p.parts) >= 2 and p.parts[0] == "docs" and p.suffix == ".md"))


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Invalid(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_document(raw):
    doc = json.loads(raw, object_pairs_hook=no_duplicate_keys)
    if (not isinstance(doc, dict) or set(doc) != {"schema_version", "files"} or
            type(doc["schema_version"]) is not int or doc["schema_version"] != 1 or
            not isinstance(doc["files"], dict) or not doc["files"]):
        raise Invalid("Expected schema_version: 1 and a nonempty files object")
    folded = set()
    for name, content in doc["files"].items():
        if not managed_path(name):
            raise Invalid(f"Not an L2 Markdown path: {name!r}")
        if name.casefold() in folded:
            raise Invalid(f"Case-colliding path: {name}")
        folded.add(name.casefold())
        if not isinstance(content, str) or "\0" in content:
            raise Invalid(f"Expected text content (deletions are unsupported): {name}")
    for name in doc["files"]:
        if any(str(parent).casefold() in folded for parent in PurePosixPath(name).parents):
            raise Invalid(f"A file is also another target's parent: {name}")
    return doc["files"]


def encoded(files):
    return (json.dumps({"schema_version": 1, "files": files}, indent=2,
                       ensure_ascii=False, sort_keys=True) + "\n").encode()


def skills_link(path):
    """`.claude/skills -> ../.agents/skills`, the layout bento-setup offers; the walk inspects the target."""
    return (path.name == "skills" and path.parent.name == ".claude" and path.is_symlink() and
            path.resolve() == (path.parent.parent / ".agents" / "skills").resolve())


def greenfield(repo):
    if (repo / ".bento-state").exists() or (repo / ".bento-state").is_symlink():
        raise Invalid("L2 state already exists; use bento-learn, not bento-init")
    tracked = git(repo, "ls-files", "-z")
    if tracked.returncode:
        raise Invalid("Cannot inspect tracked instructions")
    for name in os.fsdecode(tracked.stdout).split("\0"):
        parts = PurePosixPath(name).parts
        if not parts or any(part in SKIP_DIRS for part in parts[:-1]) or skills_link(repo / name):
            continue
        agent_layer = any(parts[i] in {".claude", ".agents"} and
                          parts[i + 1] in {"skills", "commands", "rules"} and
                          not (parts[i + 1] == "skills" and len(parts) > i + 2 and
                               parts[i + 2].startswith(L1_PREFIX))
                          for i in range(len(parts) - 1))
        if parts[-1] in {"AGENTS.md", "CLAUDE.md"} or agent_layer:
            raise Invalid(f"Tracked L2: {name}; use bento-learn (even if deleted locally)")

    def unreadable(error):
        raise Invalid(f"Cannot inspect existing instructions: {error}")

    for directory, dirs, files in os.walk(repo, followlinks=False, onerror=unreadable):
        here = Path(directory)
        for name in ("AGENTS.md", "CLAUDE.md"):
            if name in files or name in dirs:
                raise Invalid(f"Existing L2: {(here / name).relative_to(repo)}; use bento-learn")
        if here.name in {".claude", ".agents"}:
            for name in ("skills", "commands", "rules"):
                if name == "skills" and skills_link(here / name):
                    continue
                if name == "skills" and name in dirs and not (here / name).is_symlink():
                    entries = os.listdir(here / name)
                    if entries and all(entry.startswith(L1_PREFIX) for entry in entries):
                        continue
                if name in dirs or name in files:
                    raise Invalid(f"Existing L2: {(here / name).relative_to(repo)}; use bento-learn")
        # A symlinked agent directory is opaque to os.walk, so fail closed.
        for name in (".claude", ".agents"):
            if (here / name).is_symlink():
                raise Invalid(f"Cannot inspect symlinked {(here / name).relative_to(repo)}; use bento-learn")
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not (here / d).is_symlink()]


def merge_text(current, base, proposed):
    if current == base or current == proposed:
        return proposed, False
    if proposed == base:
        return current, False
    with tempfile.TemporaryDirectory(prefix="bento-merge-") as directory:
        paths = []
        for name, content in (("current", current), ("baseline", base), ("proposed", proposed)):
            path = Path(directory) / name
            path.write_bytes(content.encode())
            paths.append(str(path))
        result = subprocess.run(
            ["git", "merge-file", "-p", "--diff3", "-L", "current", "-L", "baseline",
             "-L", "proposed", *paths], capture_output=True)
        if not 0 <= result.returncode <= 127:
            raise Invalid("git merge-file failed: " + result.stderr.decode(errors="replace"))
        return result.stdout.decode(), result.returncode != 0


@contextmanager
def lock(repo):
    result = git(repo, "rev-parse", "--git-path", "bento-l2.lock")
    if result.returncode:
        raise Invalid("Cannot locate Git directory")
    path = Path(os.fsdecode(result.stdout).strip())
    if not path.is_absolute():
        path = repo / path
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise Invalid(f"Another L2 operation holds {path}; inspect it before retrying") from None
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(str(os.getpid()) + "\n")
        yield
    finally:
        path.unlink()


def replace_file(path, content, mode):
    fd, temporary = tempfile.mkstemp(prefix=".bento-write-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply_files(repo, changes, expected):
    # Preflight every path before writing any file. The lock serializes this helper;
    # this comparison also catches ordinary editor changes since planning.
    for name, previous in expected.items():
        path = safe_path(repo, name)
        actual = path.read_bytes() if path.exists() else None
        if actual != previous:
            raise Invalid(f"File changed during planning; preview again: {name}")
    written, created_dirs = [], []
    try:
        for name, content in changes.items():
            path = safe_path(repo, name)
            missing = []
            parent = path.parent
            while not parent.exists():
                missing.append(parent)
                parent = parent.parent
            for parent in reversed(missing):
                parent.mkdir()
                created_dirs.append(parent)
            mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
            replace_file(path, content, mode)
            written.append((name, mode))
    except (OSError, Invalid):
        # Roll back normal I/O failures; a process/machine crash is not a
        # multi-file transaction. The baseline is deliberately written last.
        for name, mode in reversed(written):
            path = repo / name
            if expected[name] is None:
                path.unlink()
            else:
                replace_file(path, expected[name], mode)
        for parent in reversed(created_dirs):
            parent.rmdir()
        raise


def plan(repo, operation, proposed):
    state = safe_path(repo, BASELINE)
    expected = {BASELINE: state.read_bytes() if state.exists() else None}
    base = {}
    if operation == "init":
        greenfield(repo)
        if not {"AGENTS.md", "CLAUDE.md"} <= proposed.keys():
            raise Invalid("Initialization requires AGENTS.md and CLAUDE.md for both agents")
    else:
        if expected[BASELINE] is None:
            raise Invalid("No generated baseline; use ordinary bento-learn diffs, never invent a baseline")
        base = parse_document(expected[BASELINE])
        for name in base:
            safe_path(repo, name)
        if proposed.keys() - base.keys():
            raise Invalid("Merge only accepts existing baseline paths; add new hand-authored files separately")
    changes, conflicts = {}, []
    for name, incoming in sorted(proposed.items()):
        path = safe_path(repo, name)
        expected[name] = path.read_bytes() if path.exists() else None
        if operation == "init":
            if expected[name] is not None:
                raise Invalid(f"Refusing to overwrite an existing file: {name}")
            current, merged, conflict = "", incoming, False
        else:
            if expected[name] is None:
                raise Invalid(f"Managed file was deleted: {name}; resolve manually")
            current = expected[name].decode()
            merged, conflict = merge_text(current, base[name], incoming)
        if conflict:
            conflicts.append(name)
            print(f"CONFLICT: {name}\n{merged}")
        elif expected[name] != merged.encode():
            changes[name] = merged.encode()
            diff = difflib.unified_diff(current.splitlines(keepends=True), merged.splitlines(keepends=True),
                                        fromfile="current/" + name, tofile="proposed/" + name)
            for line in diff:
                print(line, end="")
                if not line.endswith("\n"):
                    print("\n\\ No newline at end of file")
    if conflicts:
        raise Invalid("Conflicts found; no files or baseline were written")
    next_state = encoded(dict(base, **proposed))
    if next_state != expected[BASELINE]:
        changes[BASELINE] = next_state
        print(f"Baseline: record generated content for {len(proposed)} file(s)")
    return changes, expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", type=Path)
    commands = parser.add_subparsers(dest="operation", required=True)
    commands.add_parser("check", help="Refuse initialization if an L2 already exists")
    for name in ("init", "merge"):
        sub = commands.add_parser(name, help="Preview by default; --apply writes the reviewed proposal")
        sub.add_argument("proposal", type=Path)
        sub.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        repo = args.repo.resolve(strict=True)
        top = git(repo, "rev-parse", "--show-toplevel")
        if top.returncode or Path(os.fsdecode(top.stdout).strip()).resolve() != repo:
            raise Invalid("--repo must be the root of a Git worktree")
        if args.operation == "check":
            greenfield(repo)
            print("Greenfield check passed; inspect sources before generating an L2")
            return 0
        proposed = parse_document(args.proposal.read_bytes())
        with lock(repo):
            changes, expected = plan(repo, args.operation, proposed)
            if args.apply:
                apply_files(repo, changes, expected)
                print(f"Applied {len(changes)} file(s), including baseline changes")
            else:
                print("Preview only; nothing written. Review before using --apply.")
        return 0
    except (Invalid, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"bento L2: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
