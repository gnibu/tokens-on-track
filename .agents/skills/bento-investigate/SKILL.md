---
name: bento-investigate
description: |
  Evidence-first root-cause debugging. Use when something is broken, erroring, or behaving
  wrong and you need the cause, not a symptom patch. Diagnose an unexpected regression here;
  use bento-hillclimb to improve a measured baseline through experiments. Triggers:
  "why is this broken", "debug this", "500 error", "it fails when", "find the root cause".
---

# Investigate

A bug report names a symptom. Find the cause and fix it where all callers route through, so
no sibling path stays broken.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-investigate.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Reproduce first.** Get a deterministic repro before theorizing. Can't reproduce →
   gather evidence (logs, trace, inputs) until you can. No repro, no fix.
2. **Capture the evidence.** Exact error, stack, inputs, the failing values. Write down what
   you observe vs what you expected.
3. **Locate the shared point.** Find the function that misbehaves, then `grep` every caller.
   The cause usually lives where they converge, not in the one path the report named.
4. **Form one hypothesis and test it.** Change nothing else. Confirm the hypothesis explains
   the observed evidence before fixing.
5. **Fix at the source.** One guard/fix in the shared function beats a patch in every
   caller — smaller diff, and it fixes the siblings too.
6. **Prove it.** Re-run the repro → gone. Add or adjust a test that fails without the fix,
   so it can't regress.

## Guardrails

- Don't patch the symptom on the named path and stop — the other callers are still broken.
- A "this is fine / expected" conclusion is valid only if the same observable can't also be
  the failure. If a genuinely broken state looks identical, keep digging.
- Don't stack speculative fixes; one variable at a time (see `bento-hillclimb`).
