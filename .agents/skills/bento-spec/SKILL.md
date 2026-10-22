---
name: bento-spec
description: |
  Turn a vague intent into a precise, executable spec before building. Use when the ask is
  fuzzy or underspecified and jumping to code would guess wrong; not for an already-clear
  small edit. Requirements define behavior; multi-phase-plan sequences implementation.
  Triggers: "spec this out",
  "write a spec", "nail down requirements", "what exactly should this do".
---

# Spec

Convert "I want X" into a spec precise enough that implementation is mechanical and success is
checkable. Finish the behavior contract before implementation.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-spec.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Delivery follows the request

- **Spec only** (including a direct invocation without an implementation request): write the
  spec and stop. A request to plan or specify is not permission to implement.
- **Preparation inside an implementation request:** write the spec, then return to the
  authorized implementation task without asking for another go-ahead. Stop dependent work
  only for a genuinely unresolved product decision; continue independent work meanwhile.

## Steps (paste as todos)

1. **State the goal and the user** in one or two lines — what changes, for whom, and why now.
2. **Resolve the unknowns.** Settle empirical questions by a quick `bento-prototype`, not by
   guessing. Ask the user only genuine product/preference calls no experiment can settle —
   and offer options. Don't guess an unresolved decision that affects the behavior contract.
3. **Write the behavior contract.** The observable behavior: inputs, outputs, states, and the
   edge cases (empty, error, boundary, unauthorized). Concrete, not aspirational.
4. **Define done as checkable acceptance criteria** — each a condition you could verify on the
   real artifact, naming the automated test that will check it (a screenshot or value only where
   no test can reach). If you can't check it, it's not a criterion. The repo has no test
   system → the first criterion is that one exists (`bento-qa` bootstraps it).
5. **Note constraints and non-goals** — what's explicitly out of scope, and any hard
   limits (perf, compat, data boundaries).
6. **Hand off according to the request.** Write the spec to a file. Spec-only → report the
   path and stop. Implementation already requested → continue from the spec
   (`bento-multi-phase-plan` if large, otherwise directly), keeping any unresolved decisions explicit.

## Guardrails

- Don't mix drafting with coding. Complete the spec first; implement only when the user's
  task already authorizes it, never from a spec-only request.
- Every acceptance criterion must be verifiable on a real artifact; drop vague ones.
- Keep unknowns out of the spec: resolve them (prototype/ask) or list them as explicit open
  questions, never silently assume.
