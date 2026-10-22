---
name: bento-hillclimb
description: |
  Tune anything measurable — retrieval quality, latency, eval scores, a prompt — by
  disciplined one-variable-at-a-time experiments with a kept/reverted log. Use when:
  (1) improving a metric, (2) tuning retrieval/RAG or performance, (3) iterating on a
  prompt against a dataset. An unexpected failure/regression belongs to bento-investigate
  first; running an existing suite once is not tuning. Triggers: "tune", "improve the score",
  "optimize a metric", "iterate on a measured baseline".
---

# Hillclimb

The failure mode: change three things at once, the number moves, you don't know which
tweak did it — or whether it was noise. Next week it drops and you can't retrace. One
variable at a time, logged, keep-or-revert.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-hillclimb.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Freeze the harness first.** Fix the dataset, the metric, and how it's measured
   *before* touching the thing you're tuning. If the ruler moves, no result means anything.
2. **Record the baseline.** Run the frozen harness once. Write the number down.
3. **Change ONE variable.** One knob per experiment. Never stack untested changes.
4. **Measure against baseline.** Same harness, same input set.
5. **Keep or revert — and log it either way.** Keep only a real gain (significant, not
   noise; re-run if the sample is small). Log the attempt, the delta, and the decision.
   A reverted attempt is still knowledge — write it down so you don't retry it.
6. **New baseline on a keeper**, then back to step 3.
7. **Don't stop on a lucky first hit.** Run enough iterations that one good roll can't
   fool you. State the stop condition up front (target metric, or N no-improvement rounds).

## Guardrails

- Regression check on every keeper: a gain that breaks something else is not a gain.
- If two knobs seem coupled, that's a finding — still change one, note the interaction.
- The log is the deliverable as much as the final number. No log = you learned nothing
  transferable.
