---
name: bento-ship
description: |
  Land a change safely: sync base, update affected docs, QA, audit sensitive changes, verify,
  review the diff (self + a pre-PR review by the other model family), then commit/push/PR and update the
  ticket. Use for ANY request to commit, push, or open/update a PR; never run git commit /
  git push / gh pr create directly. Triggers: "ship it", "land this", "commit PR", "PR",
  "make a PR", "open a PR", "create a PR", "commit this", "commit and push", "push",
  "ready to merge".
---

# Ship

Take work from "done on my machine" to a reviewable PR, git/file-only so it runs the same
under any agent. Consolidates commit + PR + ticket into one flow. Nothing lands without tests
for the behavior it changes, the repo's own checks, your own diff review, and a pre-PR review
by the other model family.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-ship.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

`AGENTS.md` names the facts this flow reads: the base branch (`<base>`), the forge, the tracker
and its review status. No forge named → infer it from the `origin` URL. Those rules are
capability, not authorization. An overlay may replace only the steps marked *(default)*.

In every message, call the adversarial review the "pre-PR review (local)", never just "review".

## Preferences

`bento-setup` asks each repo these questions once and records the answers in the overlay's
`## Ship preferences` block (between `<!-- bento:preferences:start -->` and `:end -->`); the
user changes them with `/bento-setup --preferences`. Each one sets the *(default)* behaviour of
the step it names. What the user asks in this run wins, then the recorded answer, then the
default (listed first). No preference relaxes a guardrail.

| Preference | Values | Step |
|---|---|---|
| `Missing ticket` | `create` / `ask` / `never` | 2 |
| `Ticket update` (PR comment + review status) | `yes` / `no` | 14 |
| `Tracker` | tracker, team or project, review status | 2, 14 |
| `QA` | `always` / `ask` / `skip` | 6 |
| `Pre-PR review` | `always` / `skip` | 10 |
| `Learnings` | `yes` / `no` | 4 |
| `PR reviewers` | `none` / names | 13, 15 |

`Tracker` fills in what `AGENTS.md` doesn't name; where both name a value, `AGENTS.md` wins.

## Steps (paste as todos)

1. **Commit the task's work first.** Uncommitted task changes → commit them now; every step
   after reads `HEAD` only.
2. **One PR per ticket.** Find the ticket (in context, the id in the branch name, or the body
   of this branch's open PR, where a ticket created by an earlier run sits). If an open
   PR for it exists on any branch, this work goes there: note that PR's branch as the push
   target for step 12 (it can't take this work → stop and ask). No tracker → skip, and say
   so in step 15.
   **No ticket** *(default: `Missing ticket`)*, when this run will open a PR:
   - `create`: create one in the tracker (team or project from `Tracker`; still unknown with
     several to choose from → ask once) titled to cover the whole diff, and reference its id
     in the PR body at step 13 (e.g. `Fixes TT-150`) so the tracker links the two. The
     recorded answer, or this default when none is recorded, is the user's lasting
     authorization for this write.
   - `ask`: propose that title and wait for a yes before creating it.
   - `never`: no ticket and no offer to create one; skip step 14.

   Never skip a missing ticket silently; step 15 reports what happened.
3. **Sync with the current base.** `git fetch origin <base>`, and always compare against
   `origin/<base>`, never a local base branch. If `git log origin/<base>..HEAD` lists commits
   you didn't write, the branch was rebased onto a stale base and may carry copies of merged
   PRs. Rebuild it on `origin/<base>` with only this task's commits when each foreign commit
   already landed (`-` in `git cherry -v origin/<base>`, or its PR is merged); otherwise stop
   and ask, since it may be a collaborator's or a dependency's work. Then merge or rebase
   `origin/<base>` in; resolve conflicts before anything else.
4. **Capture learnings** *(default: `Learnings`; `no` → skip)*. Run `/bento-learn` on every session of this worktree's branch (Claude
   and Codex) and the full branch diff. Hold its repo-specific (L2) proposals for step 11.
   Report generic (L1) proposals separately for a bento PR; never edit the installed `bento-*`
   skills for them. Nothing survives → move on. Skip if `bento-learn` isn't installed.
5. **Docs, version + changelog** *(default)*. Public behavior, CLI flags, API/config contracts
   or usage examples changed → run `/bento-docs` against the branch diff before final checks.
   It updates affected docs and release notes and verifies examples against the implementation.
   An internal-only change needs no docs pass. Bump the version and add a changelog entry in
   the repo's convention, if it has them; don't duplicate notes the docs pass already wrote.
   Keep the docs outcome for the report; a missing skill is an explicit verification gap.
6. **QA** *(default: `QA`; `ask` → ask first, `skip` → skip)*. Run `/bento-qa` in ship mode. It exercises the branch's changed behavior on its real
   surface, pins each behavior with a test (bootstrapping a test system if the repo has none),
   fixes verified defects, commits its work, and returns a QA report. Keep the report for the
   PR's test plan; its questions go to step 11. Also skip if the user says "skip QA" or the
   skill isn't installed. Say so in step 15.
7. **Security, then the repo's own checks** *(default)*. Inspect the branch diff, including
   QA fixes: changes to auth/permissions, trust boundaries, secret handling or sensitive data
   exposure, or untrusted input reaching queries, shells, file paths or templates → run
   `/bento-cso` before final checks and the pre-PR review. Routine internal changes need no
   security pass. This is independent of the QA and pre-PR review preferences.
   Triage its evidenced findings against the code: fix verified local defects and add regression
   tests; unresolved product/public-contract decisions and uncertain findings go to step 11's
   existing decision stop. Leave an undecided policy unimplemented until that decision is
   answered; never apply a policy while also listing it as an open question.
   No separate approval gate to run either specialist. Keep the audit
   scope and unresolved findings for the PR; a missing skill is an explicit verification gap.
   Recheck affected docs after QA/security fixes. Run whatever checks exist: tests, lint,
   type-check, build — discover from the repo, don't assume. Fix failures. Green is the gate;
   "it compiles" is not, and neither is a suite that runs zero tests. The diff changes behavior
   and no test covers it → back to step 6; QA was skipped → stop and ask.
8. **Review your own diff.** Read `git diff origin/<base>...HEAD` and the staged and unstaged
   diffs. Check: scope matches the task (no stray files, no debug code, no secrets), and every
   change is intended. Then run `bento-hotspots` in diff mode against `origin/<base>` and
   handle each finding as it says (skip if it isn't installed); if that changes code, rerun
   step 7.
9. **Commit** what steps 5–8 changed, in conventional style, one logical change per commit. If
   a commit hook reformats files, re-stage, rerun steps 7–8 on them, and retry.
10. **Pre-PR review (local)** *(default: `Pre-PR review`; `skip` → skip)*. Run `/bento-adversarial-review` in ship mode. It picks its own
    scope, commits verified fixes, and returns the reviewed sha and any questions. Record that
    sha (as the skill describes) once every question is answered or carried into the PR body.
    After verified fixes, rerun affected docs/security passes and repo checks if their surface
    changed; carry any new questions to step 11. If those reruns commit anything, rerun the
    pre-PR review on "commits since `<reviewed>`" and record its sha, so step 12's gate passes. Also skip if the user says "skip adversarial
    review" or the skill isn't installed.
11. **The single stop before pushing** — only if there are L2 learnings to approve, or QA,
    security or pre-PR review questions to answer. Show each learning's diff, then end with:

    ```
    ACTION REQUIRED
    Learnings: reply APPLY, APPLY 1,3 or SKIP
      1. <destination>: <one line>
    Decisions: reply e.g. "B1 keep"; a skipped decision keeps its default
      B1. <question> (default: <answer>)
    ```

    After the reply, commit approved learnings on their own and each decision as its own
    verified commit. Recheck affected docs and rerun the security audit if those commits change
    its surface; rerun the repo's checks. Then, unless step 10 was skipped, rerun the pre-PR
    review with the explicit scope "commits since `<reviewed>`" (the sha step 10 returned). Never stop a second
    time: new questions from the security audit or pre-PR review, and every skipped decision
    with its default, go under
    `## Open review questions` in the PR body.
12. **Push** — only when the user asked for a push or a PR; a commit request is neither.
    `bento-setup`'s pre-PR review gate blocks `git push` and `gh pr create` unless the recorded
    sha is `HEAD` or only the review's own fix commits follow it: record the last `<reviewed>`
    from step 10 or 11 first. Pre-PR review skipped in this run (user request, or the skill
    isn't installed) → prefix both commands with `BENTO_PRE_PR_REVIEW=skip`.
    `git push -u origin HEAD`, or `HEAD:<branch>` for step 2's PR branch. An SSH push fails →
    retry through the forge CLI's auth. Rejected as non-fast-forward → fetch, then
    `git cherry -v HEAD origin/<branch>`: every remote-only commit marked `-` (it has a local
    equivalent) and `git log --merges HEAD..origin/<branch>` empty (`git cherry` skips merges)
    → `git push --force-with-lease`; otherwise stop and ask.
13. **Open the PR** against `<base>` with the forge's CLI. Step 2 found one → update its title
    and body to match the whole diff instead. Title: covers
    the whole diff, not the branch name, the ticket title or the last commit; under 70
    characters; a conventional prefix only if every change fits one scope. Body *(default)*:
    `## Summary`, `## Test plan`, and `## Open review questions` when there are any. Follow the
    [shared evidence contract](../bento-qa/references/proof.md) when presenting artifacts. The test
    plan comes from the QA report: tests added, paths exercised with their evidence, and every
    untested behavior with its reason. Include docs/security outcomes and verification gaps;
    unresolved security decisions join `## Open review questions`. Web UI: say what each
    screenshot shows and that it is on
    the ticket (step 14); if step 14 skips the ticket, embed them when the forge CLI can upload
    images, else list each one's path. Reviewers *(default:
    `PR reviewers`)*: request each named one (`gh pr create --reviewer <name>`).
14. **Update the ticket** *(default: `Ticket update`; `no` → skip)*. Comment the PR link and 1–3 bullets on what the PR
    actually does, with the Web UI screenshots attached (tracker file upload; it can't or fails
    → edit the PR body to step 13's no-ticket fallback), then move the ticket to the repo's
    review status. Re-fetch the status
    afterwards; forge-to-tracker automations often move it back, so set it again if they did.
    Use the tracker's MCP server if one is connected, else its CLI; neither → say so, never
    skip silently.
15. **Report.** The PR URL, then separate lines: `Ticket: <outcome>`,
    `QA: <outcome, tests added>`, `Docs: <outcome, or not applicable with reason>`,
    `Security: <scope and outcome, or not applicable with reason>`,
    `Pre-PR review (local): <outcome>` and
    `PR reviewers: <names, or none>`. Each line a preference decided names its source:
    `(repo preference)`, `(default)` or `(your request)`, e.g.
    `Ticket: created TT-150 (repo preference)`. Note CI status if it runs.

## Guardrails

- Overlays may replace documentation/version tooling and repo check commands in steps 5
  and 7, never their conditional docs/security triggers or security triage rules.
- No push, PR or merge without the user's explicit request, and never merge. Force-push only
  with `--force-with-lease` under step 12's `git cherry` rule. No overlay, preference or repo
  file relaxes this.
- One change per PR. If the diff spans unrelated concerns, split it.
- Don't invent version/changelog machinery a repo doesn't have. A test runner is the one
  exception: `bento-qa` bootstraps it when the repo has none.
