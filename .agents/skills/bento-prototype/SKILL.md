---
name: bento-prototype
description: |
  Build a throwaway to make a design decision cheaply. Use when the right approach is unclear
  and you need to try before committing. Triggers: "prototype", "spike", "mock it up", "try
  an approach", "which design/layout", "explore options".
---

# Prototype

You own the design decision, not the code. The prototype is a throwaway instrument — the real
build follows afterward. This is the one place the usual bars invert: **speed over polish,
code quality does not matter, no planning.** The rigor is in picking the right design cheaply.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-prototype.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Scope the decision** the prototype exists to make — which layout, interaction, or (for
   an empirical fork) which behavior/timing/approach. No decision to make → no prototype;
   just build the thing.
2. **Gather references** when the design space is open — prior art, a quick moodboard of
   options; let the user pick directions before building. Skip when the direction is set.
3. **Build throwaway in an isolated scratch dir,** separate from production source. Lightest
   stack that renders the idea (vanilla HTML/CSS/JS, CDN deps) or the smallest script that
   exercises the question. No production framework, no tests, no abstractions.
4. **Put alternatives behind one switcher** (buttons / a keypress), each variant labeled, so
   they're compared side by side.
5. **Verify by observation, not assertion** — screenshot each visual variant; log the
   output/timing for a behavioral one. The observation *is* the test here.
6. **Present variants, tradeoffs, and a recommendation.** The output is the decision plus the
   throwaway artifact — not shippable code. Hand the chosen direction to the real build.

## Guardrails

- Never ship prototype code. Say plainly it's throwaway; the real build starts clean.
- No tests, no abstractions, no production framework — that effort is waste on a throwaway.
- Keep it out of production source (scratch dir) so it can't leak into the real build.
