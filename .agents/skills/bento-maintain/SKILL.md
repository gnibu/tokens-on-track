---
name: bento-maintain
description: |
  Make one evidenced maintenance change: code improvement, agent-instruction upkeep,
  documentation upkeep, dependency-security repair, or a monitoring-driven bug fix.
  Use for "maintenance pass", "maintain this repo", "clean up stale instructions",
  "fix docs navigation", or a factory maintenance assignment. Args: task [scope]
  [--factory]. Use bento-hotspots for complexity ranking and bento-investigate for a named bug.
---

# Maintain

One target, one reviewable diff, proof, then return. A no-op is useful when nothing qualifies.
This skill works directly for a human or as a worker inside an existing factory.
When wiring a factory or replacing copied tasks, read [factory adoption](references/factory-adoption.md).

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists,
`.agents/bento/bento-maintain.md`, under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).
Read nested instructions before editing their area. No profile file is required.
`bento-setup` discovers repository tools into this overlay. Tasks consume those capabilities;
they do not assume a documentation system, tracker or monitoring provider. Missing setup
is not itself a blocker when the caller/instructions supply the facts.

## Tasks

Read only the requested procedure. No task named → select one from the user's stated
problem; unclear intent → clarify before changing files.

| Task | Procedure | Existing owner used for the change |
|---|---|---|
| `code-improvement` | [One small behavior-preserving improvement](references/code-improvement.md) | `bento-refactor` |
| `instructions-upkeep` | [Accurate, lean agent instructions](references/instructions-upkeep.md) | `bento-learn` placement conventions |
| `docs-upkeep` | [Documentation navigation and factual drift](references/docs-upkeep.md) | `bento-docs` |
| `security-fix` | [One dependency-security batch](references/security-fix.md) | Repository dependency skill, when available |
| `error-fix` | [One monitoring-driven regression fix](references/error-fix.md) | `bento-investigate` |

## Steps (paste as todos)

1. **Establish the assignment.** Record the task, scope, allowed edits, required checks and
   capabilities from the caller, instructions and overlay. Repository commands, paths,
   monitoring providers and tracker policy come from those sources, never a guessed stack.
   A caller's permissions only narrow repository policy. Check assignment-wide requirements
   before selection, including advisory/monitoring access and a shell for required code checks.
   Missing required input/tool → `failed`; a missing optional tool is a stated verification gap.
2. **Pick one target** using the procedure. Check available open PRs and tracker ownership
   before picking; skip overlapping work, including earlier maintenance PRs. Follow repository
   pagination rules. If ownership cannot be checked when required, report a blocker rather
   than assuming there is no overlap. No eligible target → `no_op`, with the checked candidates
   and reasons. Existing behavior, docs or conventions must justify the target by `file:line`.
3. **Make the bounded change.** Delegate with the same scope, permissions and **work-only**
   context: return edits and evidence; no commits, branch changes, shipping or tracker writes.
   Follow-ups stay in the report. A target needing a larger migration goes through
   `bento-multi-phase-plan`: inventory the affected sites, propose independently verifiable
   batches, and return the plan if execution is not already authorized. The caller owns
   approval and batch state; execute only its assigned, authorized batch.
4. **Verify and review.** Run the repository's checks covering the changed area, plus the
   procedure's proof, using [the shared evidence contract](../bento-qa/references/proof.md).
   Re-read each changed line against its evidence; include renamed references and callers.
   Check every edited, created, deleted and renamed path against the assigned scope and
   protected paths. Do not alter the policy to make the diff pass. If a check fails, fix it
   within scope or undo only this task's edits and report `failed`; preserve pre-existing work.
5. **Return the result** below. This skill never commits, pushes, opens a PR or merges.
   A direct caller can subsequently use `bento-ship` when delivery was requested.

## Factory calls

`--factory` (or an explicit factory assignment) means there is no interactive operator.
Honor the factory's tool limits, allowed paths and network policy, including in delegated
skills. Do not fetch, switch branches, change the index/history, create tickets, edit factory
configuration or invoke `bento-ship`. The factory or its repository adapter owns tracker
writes and delivery. Missing shell access can be valid for a read/edit-only documentation
assignment: do the prescribed source checks and state which build was not run.

Never wait for an answer or invent a decision. Once the assignment-wide requirements in
step 1 are met, skip candidates needing an unresolved product/public-contract decision,
a prohibited change or an unavailable candidate-specific environment. If none remain,
return `no_op` with the disqualified candidates and reasons. Failed required verification
is `failed`, never an empty sweep. Return any proposed
rule, larger plan or blocked change as a finding for the caller; do not apply it while
also presenting it as an open question.

## Result contract

Return report Markdown, `outcome` (`completed`, `no_op`, `failed`) and a one-line factual
`summary`. Respect a caller's required report prefix and output package names. Include:

- **Target:** what and why, with source references and the candidates skipped.
- **Changes:** each changed file and the evidence justifying it; none for a no-op.
- **Proof / Checks:** exact commands and results or linked artifacts; clearly distinguish
  source inspection from an executed build, and list any required check that could not run.
- **Review:** scope, behavior/contract impact, and any unresolved findings or follow-ups.

`completed` requires a change, passing required checks and proof. `no_op` means a successful
inspection found no eligible work, or returned a plan/proposal without code changes (say
which). `failed` means the assignment or required verification could not be completed; return
the blocker and rollback status. Never label an unverified code change completed.
