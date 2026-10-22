---
name: bento-eval-blind
description: |
  Compare two models, prompts, or variants without letting bias leak into the verdict.
  Use when: (1) deciding which model/prompt to ship, (2) grading A vs B outputs,
  (3) any "is the new version better" comparison. Triggers: "compare models",
  "which prompt is better", "compare variants", "A/B", "blind judge". Running an existing
  evaluation/test suite once is not a comparison and does not trigger this skill.
---

# Blind eval

Framing leaks into verdicts. If the judge knows which side is "the new one" — or if you
grade the candidate's own claim instead of its behavior — you measure the framing, not the
quality. Blind it.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-eval-blind.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Name the decision.** One sentence: what are you choosing between, on what metric?
2. **Neutralize labels.** Rename the two arms to `A/` and `B/` — no `gpt5_run` /
   `new_prompt` / `v2`. Strip model/variant names from dir names, file names, and any
   text the judge will see. Keep the A↔B mapping in a separate note you don't show anyone.
3. **Freeze the input set.** Same prompts/dataset for both arms. Record it.
4. **Collect behavior, not claims.** Capture what each arm actually did — transcripts,
   files touched, outputs. Discard any "I handled this correctly" self-report.
5. **One blind judge over both sets.** A separate pass (fresh context, or a human) scores
   A and B on the *same* scale, having never been told which is which.
6. **Unblind last.** Only after scores are locked, reveal the mapping and read the result.
7. **Record the verdict + the mapping** so the decision is reproducible.

## Guardrails

- If the judge can infer the arm from anything (a stray filename, a version string, tone),
  it isn't blind — fix and rerun.
- Grade the same observable for both. Different rubrics per arm = not a comparison.
- Ties are a result. Don't reach for the arm you hoped would win.
