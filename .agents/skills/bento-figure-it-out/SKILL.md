---
name: bento-figure-it-out
description: |
  Fallback for a task no other playbook covers. Use when the request doesn't match an
  existing skill and you'd otherwise improvise. Triggers: an off-catalog task, "there's no
  skill for this", any multi-step work with no matching playbook. Skip routine one-step
  edits and existing-suite runs; use a specialist when its task matches.
---

# Figure it out

Frame unmatched multi-step work, execute it, then decide whether the procedure should recur.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-figure-it-out.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Frame and map.** State the goal, done-condition and proof artifact; inspect the affected
   files and real flow before choosing the change.
2. **Sequence.** Write ordered, checkable todos before acting.
3. **Execute and prove.** Follow the todos and autonomy contract; verify the real artifact.
4. **Capture only a recurring procedure.** Repeated task with a concrete trigger → consult
   `bento-authoring-a-playbook`; one-off → capture nothing.

## Guardrails

- Don't skip mapping to reach a small diff faster — the smallest change in the wrong place
  is a second bug.
- One occurrence is not a pattern. Resist skilling a task you've done once.
