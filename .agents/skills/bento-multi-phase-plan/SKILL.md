---
name: bento-multi-phase-plan
description: |
  Plan a large change as a checklist of verifiable units before implementing. Use when work
  spans several dependent units or PRs and the approach isn't a one-shot; not routine small
  edits or requirements discovery (use bento-spec for that). Triggers: "plan this large change",
  "break into phases", "multi-PR", "large change", "roadmap", "how should we sequence".
---

# Multi-phase plan

A checklist an owner runs box by box and an auditor can check from the evidence. Finish the
plan before executing its units.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-multi-phase-plan.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Delivery follows the request

- **Plan only** (including a direct invocation without an implementation request): deliver
  the plan and stop; don't change application code.
- **Preparation inside an implementation request:** finish the plan, then continue the
  authorized work without another go-ahead. Pause dependent work for unresolved product
  decisions; a planning step does not revoke authorization or grant permission to push/PR.

## Steps (paste as todos)

1. **Skip the machinery if small.** One or two files with an obvious approach → a concise
   checklist if the user requested a plan only; otherwise continue the authorized task directly.
2. **Settle unknowns by prototype first** (see `bento-prototype`), not by guessing in the plan.
   Ask the operator only about a product/preference call no experiment can settle — and give
   options. Don't guess an unresolved product decision.
3. **Explore in subagents,** each returning file pointers, conventions, test commands, and
   entry points — not inlined dumps. Keeps the planning context clean.
4. **Lock the architecture before coding.** State the module boundaries, data flow, and the
   key interfaces/contracts the change assumes, and pressure-test them: what breaks at scale,
   which decisions are hard to reverse, where the design fights the existing system? Settle
   these now — a wrong contract discovered mid-build is the expensive kind.
5. **Write the plan as a checklist.** One section per PR; **one PR = one change with its own
   evidence.** Order sections by dependency (independent work first; dependent work after its
   parent).
   For a repeated cleanup/migration, first inventory the affected sites against the actual
   owning rule, group them into batches (for example one screen or module), and state the
   measurable end condition. Record approval and completed batches in the caller's existing
   plan/tracker. A factory worker returns the inventory/plan until execution is authorized;
   then it executes only its assigned batch and returns evidence. No separate campaign hub
   or scheduler is needed, and the worker's scope/delivery restrictions still apply.
6. **Every box names the evidence that checks it** — a file, a log line, a screenshot, a test
   run, or a SHA. A box is checked only when that evidence exists.
7. **State the verification rule per PR:** tests alone are not sufficient. A PR is verified
   only when its unit test, a live run on the real surface, and a regression check vs the
   current baseline all pass. Name the metric/scenario for each. Each PR adds the tests that
   pin its behavior; the repo has no test system → the first PR creates it (`bento-qa`).
8. **Hand back according to the request.** Post the plan path. Plan-only → stop.
   Implementation already requested → execute its units under the named execution flow,
   checking boxes only when their evidence exists. No redundant request to start.

## Guardrails

- Planning alone never authorizes implementation. When implementation is already requested,
  complete the plan first and then continue that task.
- No box is "done" on intent; only on named evidence.
- Keep it a how-to checklist; put reasoning and findings in appendices, not the steps.
