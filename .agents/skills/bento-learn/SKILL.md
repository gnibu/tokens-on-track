---
name: bento-learn
description: Reflect on sessions and optionally requested PR review history, then route each reusable learning to its cheapest correct home (L1 bento or L2 repo). Evolve an existing instruction layer — diff and propose, never regenerate. Idempotent; prove skill edits with the eval harness.
---

# bento learn

The learning engine. Turn what a session surfaced into durable improvements, each routed to
one home. Generalizes a session-learning router to two layers: **L1 (bento, generic)** and
**L2 (this repo, specific)**. This is *improve* — evolve what exists, diff and propose; for a
greenfield repo with no layer, see `bento-init`.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-learn.md` at the repo root; follow it under the
[overlay rules](references/instruction-layer.md#repo-overlays-for-bento-skills).

Paths below are relative to this skill's directory (`<skill>`); `bento-init` is its
sibling, installed alongside it.

## 1. Reflect

**Optional review history.** Only when explicitly asked to learn from PR reviews (or invoked
with `--reviews`), also read [review-history.md](references/review-history.md). Use that
collection as additional evidence for the same Reflect → Route → Propose loop. A request
scoped to reviews alone need not scan local sessions. Ordinary learn/ship calls do not sweep
historical PRs. `--propose-only`, including a factory call, returns concrete proposed diffs
and evidence without applying, committing, creating tickets or waiting for approval; it never
weakens step 3's approval requirement for a later application.

Read **every session that built this branch**, not just this conversation — work often spans
several Claude and Codex sessions. From the consumer repo root run
`python3 "<skill>/scripts/sessions.py"`: it prints each worktree session since the branch was
created (operator turns, failed tool calls, blocking hook errors), oldest first, with its
transcript path. Pass `--since <epoch>` to widen the window. Open a printed transcript only
when a line needs more context.

Scan those sessions, this conversation, and the branch diff for signal, citing the
session/turn/command:

- **Friction** — anything slow, retried, or failed before it worked. Trace the *root cause*.
- **Operator corrections** — a redirect/reminder is a signal even with no error: something you
  should have done or offered yourself. Fix the missing behavior, not the one instance.
- **Surfaced bugs** — code that misbehaved (silent failures, wrong checks, missing guards).
- **Reusable gotchas** — a command, env quirk, or non-obvious pattern the next agent trips on.
- **Repeatable workflows** — a multi-step procedure that will recur.

**Reuse gate (hard filter):** keep a candidate only if you can name a concrete recurring
trigger. Default to dropping. Surfacing nothing is a valid outcome — don't manufacture
learnings. Ignore anything already documented (grep first).

## 2. Route — one destination per learning

Pick the cheapest correct home. Price the sink first (see [instruction-layer.md](references/instruction-layer.md)).

**By kind:**
- Code bug / wrong logic → fix the **source** + a test. The fix is the learning.
- Procedure (how to run, test, release, migrate…) → **a doc**: the existing doc that covers
  the task, else a new `docs/procedures/<verb>-<object>.md` (`run-tests.md`). Add it to the
  root `AGENTS.md` `## Docs` menu ("Before running tests → docs/procedures/run-tests.md").
  See [procedures](references/instruction-layer.md#procedures-how-to-do-what).
- Agent orchestration / tool choice / review behavior → a **skill** (amend the owner; create
  one only if none fits — see `bento-authoring-a-playbook`).
- How a bento skill should run in this repo (an extra step, a different default) → that
  skill's **overlay**, `.agents/bento/<skill-name>.md` (create it if missing). Never edit the
  installed `bento-*` skill.
- Code-scoped gotcha / command / env quirk → the **nearest `AGENTS.md`** to that code; none
  below the root → create `AGENTS.md` in that code's directory, plus a `CLAUDE.md` holding
  `@AGENTS.md` so Claude loads it too.
- Human-facing architecture / decision → **docs** (or an ADR).
- One-off → **drop it.**

**By layer:**
- Generic (helps any repo, any agent) → **L1: bento** — a principle, convention, or playbook.
- Repo-specific → **L2: this repo's** instruction layer.

Never bank a team-useful learning in **private memory** — it's per-operator and reaches no
one else. Private memory is the last resort, only for genuinely personal, cross-project
preferences.

## 3. Propose, then apply

- For each `AGENTS.md`/`CLAUDE.md` you would change, write the proposed text to a temp file
  and run `python3 "<skill>/scripts/check_entries.py" <file> <proposed> [<new doc>...]`, naming
  each doc the proposal creates (`docs/procedures/run-tests.md`). It rejects any new entry over
  one line without a pointer, or over two lines, and an `AGENTS.md` whose `## Docs` menu
  misses a doc. Re-route a rejected entry (step 2), add missing docs to the
  menu; never propose a failing file.
- Show the concrete diff per learning, grouped by destination, **before** touching anything.
- Apply on explicit go-ahead. Leave commits/PRs to the user (or to `bento-ship`, when it called you).
- **Preserve generated-file ownership.** If `.bento-state/baseline.json` lists the
  destination, build a proposal from its last-generated text plus this learning,
  then run `python3 "<skill>/../bento-init/scripts/l2-state.py" --repo . merge <proposal.json>`
  to preview; append `--apply` only after approval. The helper merges current / baseline / proposed and advances the baseline only
  on success. Show the **merged diff**, not just the proposal.
  Never edit a managed file directly or replace its baseline with hand-edited text.
  A conflict writes nothing: revise the proposal for review or leave it unapplied.
  No baseline, or an unlisted destination → ordinary targeted diff-and-propose;
  never invent a baseline for existing L2. See
  `<skill>/../bento-init/references/init.md` for the proposal format and recovery rules.
- **For a skill/playbook edit, prove it:** baseline `claude plugin eval` → apply the edit →
  re-run → keep only on a real lift beyond noise (`--runs 3+`), else revert. Log kept/reverted
  (this is `bento-hillclimb` applied to the instruction layer itself).
  Revert the corresponding baseline change too if a managed-file edit is rejected.

## When to run

No hook runs this — it is a deliberate step, run two ways:

- **At PR time** — the `bento-ship` playbook calls it before final verification and diff review.
  Reflect on the branch's sessions (`sessions.py`) **and** the full branch diff (committed and
  uncommitted), so learnings from earlier Claude and Codex sessions are covered too. Return the
  L2 proposals with their diffs and apply nothing yet: `bento-ship` asks for approval at its
  single stop before pushing, then applies, verifies and commits them separately in that PR.
  Report L1 proposals for a separate bento PR. Do not edit the consumer's installed bento skills
  (`.agents/skills/bento-*`, `.claude/skills/bento-*`) for an L1 learning. Nothing survives the reuse gate
  → say so in one line and let `bento-ship` continue.
- **Manually** — `/bento-learn` (Claude) or `$bento-learn` (Codex), for
  sessions that end without a PR (debugging, investigation). Same steps; committing the
  result is the user's call.
- **Review history, on request** — `bento-learn --reviews` uses the
  [shared review collection](references/review-history.md)
  for a caller-specified PR set/window, or a bounded recent sample. A factory uses
  `bento-learn --reviews --propose-only` and returns proposals for human review; it does not
  turn review text into self-approved standing rules.
