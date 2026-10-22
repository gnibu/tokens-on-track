---
name: bento-authoring-a-playbook
description: |
  How to write a new bento playbook (a bento skill). Use when adding or editing a
  playbook, turning a repeated task into one, or customising a bento skill for one repo.
  Triggers: "add a playbook", "new skill for bento", "capture this as a skill", "write a
  SKILL.md", "add a repo rule to a bento skill", "bento overlay", "customise bento for this
  repo", "make bento-<skill> also do X".
---

# Authoring a playbook

A bento playbook is a triggered skill that opens with a pasteable checklist and proves its
work on a real artifact. Keep them few and earned.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-authoring-a-playbook.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Repo rule or new playbook?

- **A repo-specific extra step or different default for an existing bento skill** → that
  skill's overlay `.agents/bento/<skill>.md`, under the overlay rules: add steps, change only
  steps marked *(default)*, never relax a guardrail. Never edit the installed skill.
- **Generic behaviour any repo would want** → change the bento skill itself (an L1 PR to bento).
- **A new repeatable task no skill covers** → a new playbook: the rest of this skill.

**Overlay format.** Title `# <Repo> overlay for <skill>`, then one `##` section per rule, each
naming its trigger, action and approval. Link a repo skill or doc instead of copying it.

```markdown
# Acme overlay for bento-ship

## Greptile label
- Trigger: the user asks for a review.
- Action: add the `greptile` label to the PR.
- Approval: the user's review request.

## Lint (adds to the repo checks in step 7)
- Trigger: step 7, Security, then the repo's own checks.
- Action: also run `ruff check .`; see [docs/lint.md](../../docs/lint.md).
- Approval: none, local and read-only.
```

## Gate first — should it exist?

Check existing playbooks first. If one owns the task, amend that owner (or its repo overlay)
instead of adding a competing skill.

Add a playbook only when the same task shape has recurred (≥2–3 times) and you can name a
concrete trigger. One occurrence → do it inline via `bento-figure-it-out`, don't skill it.
Speculative playbooks are cost paid by every future reader. Default to not adding.

## Steps (paste as todos)

1. **Name the trigger.** When does this fire? Write it as the `description` with concrete
   trigger phrases — that's what makes the skill auto-invoke.
2. **Write the checklist.** Numbered, ordered, checkable steps the agent pastes as todos.
   Lead with them; prose is secondary.
3. **Demand proof.** Include a step that verifies on a real artifact (transcript, test,
   file, before/after) — never a self-report.
4. **Add guardrails.** The 2–3 failure modes this playbook prevents.
5. **Keep it generic.** bento playbooks must help in any repo. Repo/org-specific detail
   belongs in that repo's L2 or overlay, not here.
6. **Prove it lifts.** Add a `claude plugin eval` case (with/without arm) and run
   `claude plugin eval` — keep the playbook only if it changes behavior. No lift → don't ship.

## Guardrails

- Fix the principle, not the example. Minimal GOOD/BAD pairs; add a BAD example only when
  the instruction alone isn't enough.
- No verbatim production data, no dates/history in the body — state current scope only.
- Shorter is better: if the explanation is longer than the steps, cut the explanation.
