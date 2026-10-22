#!/usr/bin/env python3
"""Reject instruction-file entries that belong somewhere else.

Usage: check_entries.py CURRENT PROPOSED [NEW_DOC...]

CURRENT is the instruction file as it is now (AGENTS.md or CLAUDE.md, at any depth; it may
not exist yet), PROPOSED the full text bento-learn wants to write there. Only entries that
are new or changed in PROPOSED are checked, so an old file never blocks a new learning.
An entry (a bullet, a paragraph or a code block) must fit on one line, or on two when it
carries a pointer (a path or a link) to where the detail lives. An AGENTS.md is also the
menu of the docs/**/*.md beside it, on disk or proposed in the same change (NEW_DOC, relative
to the AGENTS.md's directory): its `## Docs` section must name each one, by its path or a
folder below docs/ that holds it ("Design briefs → docs/briefs/"). Exits 1 and names each
rejected entry and each doc missing from the menu.
"""
import re
import sys
from pathlib import Path

LINE = 100  # the wrap width of a "line"
BULLET = re.compile(r"\s*([-*+]|\d+\.)\s")
# ponytail: a path-shaped token counts as a pointer, resolved or not; check existence if
# entries start pointing at files that are never written.
POINTER = re.compile(r"\]\(|https?://|\w/[\w.*]|[\w-]\.(md|py|sh|js|ts|tsx|json|toml|ya?ml)\b")


def entries(text):
    """Bullets, paragraphs and code blocks, whitespace-collapsed. Headings and comments are skipped."""
    blocks, current, fenced = [], [], False

    def flush():
        if current:
            blocks.append(" ".join(" ".join(current).split()))
            current.clear()

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("```"):
            if not fenced:
                flush()
            current.append(stripped)
            fenced = not fenced
            if not fenced:
                flush()
        elif fenced:
            current.append(stripped)
        elif not stripped or stripped.startswith(("#", "<!--")):
            flush()
        else:
            if BULLET.match(line):
                flush()
            current.append(stripped)
    flush()
    return blocks


def problem(entry):
    if len(entry) <= LINE:
        return None
    if len(entry) > 2 * LINE:
        return "over two lines: keep the trigger and a pointer, move the detail to a doc or the code"
    if not POINTER.search(entry):
        return "over one line without a pointer: name the file or link where the detail lives"
    return None


def check(current, proposed):
    old = set(entries(current))
    return [(entry, reason) for entry in entries(proposed)
            if entry not in old and (reason := problem(entry))]


def menu_section(text):
    """The body of the `## Docs` section, up to the next heading of level 1 or 2."""
    match = re.search(r"^## Docs[ \t]*\n(.*?)(?=^#{1,2} |\Z)", text, re.M | re.S)
    return match.group(1) if match else ""


def menu_gaps(root, proposed, new_docs=()):
    """Docs under root/docs, plus new_docs, that the proposed `## Docs` menu doesn't name."""
    docs = {doc.relative_to(root).as_posix() for doc in (root / "docs").rglob("*.md")}
    docs |= {Path(doc).as_posix() for doc in new_docs}
    menu = menu_section(proposed)
    gaps = []
    for doc in sorted(docs):
        folders = [f"{folder.as_posix()}/" for folder in Path(doc).parents if len(folder.parts) > 1]
        # A name counts only as a whole target: `docs/a/b.md` doesn't name the folder `docs/a/`.
        if not any(re.search(re.escape(name) + r"(?![\w/-]|\.\w)", menu) for name in [doc, *folders]):
            gaps.append(doc)
    return gaps


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    current_path = Path(sys.argv[1])
    current = current_path.read_text() if current_path.exists() else ""
    proposed = Path(sys.argv[2]).read_text()
    rejected = check(current, proposed)
    for entry, reason in rejected:
        print(f"{current_path}: {entry[:70]}…: {reason}")
    gaps = (menu_gaps(current_path.parent, proposed, sys.argv[3:])
            if current_path.name == "AGENTS.md" else [])
    for doc in gaps:
        print(f"{current_path}: menu misses {doc}: add \"- <when you need it> → {doc}\" under ## Docs")
    sys.exit(1 if rejected or gaps else 0)


if __name__ == "__main__":
    main()
