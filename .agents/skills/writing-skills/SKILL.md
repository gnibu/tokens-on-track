---
name: writing-skills
description: How to write a new skill for this project, or fix an existing one — file layout under .agents/skills, the symlink into .claude/skills, frontmatter rules, what belongs in a skill versus a comment or CLAUDE.md, and how to tell a useful skill from a wasted one. Use when asked to "learn this", "make a skill", "remember how to do X", "write this up so it doesn't happen again", or when a mistake is worth not repeating.
---

# Writing a skill

A skill is a note to the next agent, written by the one who just paid for the
lesson. It earns its place by changing what that agent does — not by describing
what the code already says.

## Layout

Skills live in `.agents/skills/`. Claude Code sees all of them through one
directory symlink, `.claude/skills -> ../.agents/skills`, so a new skill needs no
link of its own — don't add one, it would land inside the skill folder:

```sh
mkdir -p .agents/skills/<name>
$EDITOR .agents/skills/<name>/SKILL.md
```

The link is relative — an absolute one breaks the moment the repo is cloned,
moved, or opened in another Conductor workspace. Check it from the repo root:

```sh
ls -l .claude/skills           # -> ../.agents/skills
cat .claude/skills/<name>/SKILL.md | head -3
```

`.agents/` holds the real files so other agent runners can be pointed at the
same directory; `.claude/skills/` is one runner's view of it. Both are committed.

Supporting files sit beside `SKILL.md` in the same directory and are referenced
from it by path — a script to run, a template to copy, a reference table too long
for the body. Anything the skill tells you to run should be a file you can run,
not a snippet to retype.

## Frontmatter

```yaml
---
name: kebab-case-matching-the-directory
description: What it covers, and the situations that should pull it in.
---
```

`description` is the only thing an agent sees before deciding whether to open the
skill, so it is the whole retrieval mechanism. Write it as triggers, not as a
title:

- Name the files, symbols and commands the work would touch.
- Include the words a user would actually type, including vague ones ("looks
  off", "still broken", "make it match").
- Prefer one long, specific sentence over three vague ones.

A description like "UI helpers" is a skill that will never be read.

## What belongs in one

Write a skill when the knowledge is **procedural, reusable and non-obvious**:

- A loop that works — how to drive, observe and verify something in this project.
- A dead end with a proof — what does not work and the evidence that settled it,
  so nobody re-litigates it.
- A rule that was learned the hard way, with the failure that produced it.

Do not write a skill for:

- What the code already states plainly. Comment the code instead.
- A one-off fix with no next time.
- Project-wide conventions that belong in `CLAUDE.md`.
- Anything you have not verified. A confident, wrong skill is worse than none —
  it launders a guess into an instruction.

## How to write it

- **Lead with the rule, then the scar.** The rule is what gets followed; the
  story of the failure is what makes it stick, and it needs to be one paragraph,
  not a post-mortem.
- **Be concrete.** Real commands, real paths, real numbers, real output. If a
  command has a gotcha (`menu bar 1` not `menu bar 2`, `cliclick` not `AXPress`),
  that gotcha *is* the value of the skill.
- **Record the facts already established** as a list the next agent can trust,
  so the expensive parts are not re-derived.
- **Say what to do, in order.** A skill is a procedure with the reasoning
  attached, not an essay with a procedure buried in it.
- **Keep it short enough to be read.** Cut anything that does not change an
  action.

## Updating one

When a skill turns out to be wrong, fix it in place and delete the wrong claim —
do not append a correction underneath it. Two contradicting paragraphs cost the
next agent more than silence would have. If the underlying code moved, check the
skill still names files and symbols that exist before recommending it.
