---
name: bento-refactor
description: |
  Change structure while holding behavior constant. Use when cleaning up, restructuring, or
  reducing complexity without adding features or fixing bugs. Triggers: "refactor", "clean
  up", "restructure", "reduce complexity", "tidy this".
---

# Refactor

**Work-only caller.** When called by maintenance or a factory that reserves git delivery,
keep its scope and permissions throughout this checklist. Return verified edits and the
suggested commit slices at step 8; do not commit, change branches, invoke ship or write to a
tracker. A caller's narrower permissions also apply to any delegated work.

You own the contract. The structure changes; the behavior does not. If the cleanup reveals a
missing feature or a real bug, split it out and ship the structural change first against the
pinned contract.

No target named ("clean up this repo") → run `bento-hotspots` in scan mode and let the user
pick from its ranked list.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-refactor.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Pin the behavior first.** Before moving anything, capture current behavior: a
   characterization test, a snapshot, or an equivalence harness. No coverage in the area →
   write the pin first. Type-check and lint are *not* a pin.
2. **Name the target shape.** State what the module layout, types, and call graph should be
   if built today. The reshape must delete branches or invalid states, not add indirection.
3. **Subtract before you add.** Delete dead code, collapse one-caller wrappers, drop
   redundant validators before introducing the new shape. Smallest change that reaches the
   target ships; a speculative "might help" cleanup gets reverted.
4. **Move in small behavior-preserving steps,** each keeping the pin green. For an API
   reshape, migrate every caller and delete the old API in the same step — no compat shims,
   no parallel old-and-new paths.
5. **Grep every rename.** Renames silently miss usages in strings, prose, config, and
   back-references. Spot-check against the actual files.
6. **Prove behavior unchanged on the real artifact** — the pin green, or an equivalence
   check (diff old-vs-new outputs / replay a recorded baseline). Not "it compiles."
7. **Keep only if it lowers reader load.** If the diff doesn't make the code easier to read
   somewhere, revert it.
8. **Commit in small ordered slices** — subtraction, then reshape, then follow-on cleanup;
   each slice green before the next.

## Guardrails

- Refactor ≠ new behavior (that's a feature) ≠ correcting behavior (that's a bug fix). If
  you find one, split it out; don't smuggle it into the structural change.
- No compatibility shims or parallel code paths "for safety" — migrate and delete.
