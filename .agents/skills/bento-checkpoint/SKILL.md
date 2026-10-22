---
name: bento-checkpoint
description: |
  Capture in-progress state so work survives a context reset or handoff. Use when pausing,
  saving progress, or before a long/risky step. Triggers: "save progress", "checkpoint",
  "pause here", "resume later", "hand this off".
---

# Checkpoint

Leave a shared artifact a fresh session can resume from.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-checkpoint.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Inspect state.** Check the diff and dirty files; note half-applied work and any running
   process you know about. Distinguish observed facts from unchecked assumptions.
2. **Record the goal and progress.** State the done-condition, completed work and decisions with file,
   commit or PR pointers; identify blockers and unresolved decisions.
3. **Name the next action.** Give the exact command or file:line to resume from.
4. **Write the handoff** in the requested location, the repo's checkpoint location, or a shared
   task file. Keep it out of private memory and reusable docs; inspect it against checked state.

## Guardrails

- Keep only what affects resuming. Don't assert a clean tree or no running processes without evidence.
- Don't checkpoint secrets or production data — pointers, not payloads.
