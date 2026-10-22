---
name: bento-adversarial-review
description: |
  Run an adversarial code review of a diff by the other model family, then triage every
  finding against the real code. Under Claude the reviewer is `codex exec` (gpt-6-astra);
  under Codex it is headless `claude -p` (opus). Interactive mode (default) gets explicit
  human sign-off before fixing anything; ship mode (called by a ship flow) fixes verified
  findings itself and returns only the ones that need a human decision. Skips commits it
  already reviewed. Triggers:
  "adversarial review", "codex review", "claude review", "second opinion on my diff",
  "outside review".
---

# Adversarial review

A reviewer that assumes the code is wrong finds issues. You verify each one. The operator
decides what gets fixed; in ship mode, that means anything beyond a verified local fix.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-adversarial-review.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

Three phases, in order. Never merge them, never skip phase 2.

## Mode

| Mode | When | Phase 3 |
|---|---|---|
| **interactive** (default) | the user runs the review directly | present, block, fix only approved numbers |
| **ship** | only when called by a ship flow: `bento-ship`, or a repo skill that plays its role | fix verified findings, return the human-decision ones |

Phases 1 and 2 are identical in both modes.

## Scope

`<base>` is the base branch the repo's `AGENTS.md`/`CLAUDE.md` names; otherwise
`git symbolic-ref --short refs/remotes/origin/HEAD` without the `origin/` prefix. A scope the
caller or user gives explicitly is used as is. Otherwise it is the branch scope, narrowed by
the last recorded review. Every review path uses the same diff command:

| Intent | Diff command (`<SCOPE_CMD>`) |
|---|---|
| default / "review my branch" | branch scope, after the check below |
| "review my working tree" / uncommitted work | the untracked-aware command below |
| "review commit X" | `git show <sha>` |
| "commits since `<sha>`" | `git diff <sha>..HEAD` |

**Branch scope: skip what was already reviewed.** Before phase 1, read the reviewed sha from
`"$(git rev-parse --git-path adversarial-review.head)"`:

- it equals `HEAD` → already reviewed. Ship mode: return "already reviewed" with that sha and
  stop. Interactive: say so, and ask before running a full review.
- it is an ancestor of `HEAD` (`git merge-base --is-ancestor <sha> HEAD`) and
  `git rev-list --merges <sha>..HEAD` is empty → `git diff <sha>..HEAD`.
- otherwise (missing, rebased away, base merged in) → the whole branch,
  `git diff origin/<base>...HEAD`.

Say which case applied and the diff command before phase 1.

Uncommitted diff command, including untracked files. Its exit status is `git diff HEAD`'s; the
untracked part's is dropped, because `--no-index` exits 1 on any difference:

```bash
{ git diff HEAD && { git ls-files -o --exclude-standard -z | xargs -0 -r -n1 git diff --no-index -- /dev/null || true; }; }
```

For the branch scope, run `git fetch -q origin <base>` first. A stale base means re-reviewing
commits that already landed.

## Phase 1 — Produce the findings

**The reviewer is always the other model family.** A different model is the point. The
models below are *(default)*.

| You are | Reviewer | Path |
|---|---|---|
| Claude | Codex `gpt-6-astra` | B |
| Codex (or any non-Claude model) | Claude `opus` | C |

Fall back to Path A only if the reviewer's CLI is missing (`command -v codex` / `command -v
claude`), and say in the result that you did.

### Path A — fallback: your own sub-agents

Gather the diff (the scope command) and the full text of every file it touches. A diff alone
hides the callers and the invariants; most false findings come from reviewing hunks in
isolation.

Fan out one sub-agent per dimension, concurrently (one pass yourself if your host has no
sub-agents). Drop a dimension the diff clearly doesn't touch; add one the user asked for:

- **correctness** — logic errors, off-by-one, wrong branch, error paths, null/undefined,
  async mistakes, transaction and ordering bugs.
- **contracts & callers** — every caller of every changed signature; migrations vs. readers;
  config keys vs. their allow-lists; API/response shape changes.
- **concurrency & state** — races, shared mutable state, idempotency, retries, tenant leakage.
- **reuse & simplicity** — code that duplicates an existing helper, or could be simpler.
- **security & data** — authz gaps, tenant isolation, injection, secrets in logs or args.

Give each the stance explicitly: *assume this diff is broken and find where; a finding you
cannot point at a specific line for is not a finding.* Require the CLI output shape —
`- [P1] Title — path/file.ts:12-15` plus a paragraph of rationale — so phase 2 is identical.

### Paths B and C — the other model family's CLI

The block writes the diff to a file first, so a failed diff command or an empty scope can't
pass as "no findings". Substitute `<SCOPE_CMD>`, `<CUSTOM FOCUS>` (what the user asked to focus on, or
nothing), and `<REVIEWER>` from your path below. Run it in the **background**: a review takes
2–5 minutes and will blow a foreground timeout on a large diff.

```bash
d="$(git rev-parse --git-path adversarial-review.diff)"
x="$(git rev-parse --git-path adversarial-review.exit)"
o="$(git rev-parse --git-path adversarial-review.md)"
l="$(git rev-parse --git-path adversarial-review.log)"
rm -f "$x" "$o"
p="$(cat <<'PROMPT'
You are an adversarial code reviewer. Assume the diff is broken and find where. Report
correctness bugs first, then code that duplicates an existing helper or could be simpler, then
departures from the conventions in the root AGENTS.md/CLAUDE.md and the nearest one to each
changed file. Read the full text of every changed file and the callers of changed signatures,
not just the hunks. Files on disk may be ahead of the diff; where they disagree, the diff is
what is under review. A finding you cannot point at a specific line for is not a finding.
Output only findings, each as '- [P1|P2|P3] Title — path/file:start-end' plus one paragraph of
rationale, or 'no findings'. <CUSTOM FOCUS>
PROMPT
)"
if ! <SCOPE_CMD> > "$d" 2> "$l"; then echo "EXIT=diff-failed" > "$x"
elif [ ! -s "$d" ]; then echo "EXIT=empty-diff" > "$x"; else
<REVIEWER>
echo "EXIT=$?" > "$x"; fi
```

`<REVIEWER>` for **Path B — you are Claude**. Plain `codex exec`, not `codex exec review`:
review mode keeps a bug-only rubric that drops reuse and convention findings.

```bash
codex exec -s read-only -m gpt-6-astra -c model_reasoning_effort='high' \
  -o "$o" "The diff under review is in the file $d. $p" < /dev/null > "$l" 2>&1
```

- `< /dev/null` is required or codex waits on stdin forever.
- `-s read-only` keeps Codex from touching the tree. Never relax it.

`<REVIEWER>` for **Path C — you are Codex**:

```bash
claude -p --model opus --setting-sources "" --tools Read,Grep,Glob --strict-mcp-config \
  --no-session-persistence "The diff under review is on stdin. $p" < "$d" > "$o" 2> "$l"
```

- `--setting-sources ""` loads no hooks, plugins, output style or permission allow-list. It
  still reads the operator's auto-memory, so treat it as a second opinion, not a clean room.
- `--tools Read,Grep,Glob` with `--strict-mcp-config`: it can read the repo and nothing else.
- From a sandboxed host, request escalation: it needs network and writes to the git dir and
  `~/.claude`.

Poll until the `.exit` file exists, then read the findings — and **only** the findings:

```bash
cat "$(git rev-parse --git-path adversarial-review.exit)" "$(git rev-parse --git-path adversarial-review.md)"
```

`EXIT=diff-failed` means the scope command failed (bad ref, missing base); the `.log` has git's
error. `EXIT=empty-diff` means the scope resolved to nothing. Either way stop and report it,
never count it as a clean review. Open the `.log` (thousands of lines of traces) only if the `.md` is empty or the
exit code is non-zero.

The paths come from `git rev-parse --git-path`, not a shell variable or `/tmp`: polling runs in
a different shell call, and parallel worktrees sharing one `/tmp` file would silently triage
each other's diffs. The git dir is per-worktree and can't be committed by a stray `git add .`.

If `-m gpt-6-astra` or `--model opus` fails with an unknown-model error, say so and ask. Don't
switch model, or to Path A, silently.

## Phase 2 — Assess each finding yourself

An adversarial reviewer is confidently wrong maybe a third of the time. Path A findings get no
benefit of the doubt for having come from you. For **every** finding:

1. Read the cited file and lines. Don't trust the quoted snippet.
2. Check what the reviewer couldn't see: the nearest `AGENTS.md`/`CLAUDE.md`, existing
   callers, tests already covering the case, whether the "bug" is deliberate.
3. Assign a verdict:

| Verdict | Meaning |
|---|---|
| **AGREE** | Real defect; you reproduced the reasoning in the code. |
| **PARTLY** | Real issue, but the diagnosis or fix is off — say what the right fix is. |
| **DISAGREE** | Not a bug. Give the specific reason (guarded upstream, intended, test exists, false premise). |
| **NEEDS INFO** | Can't tell without runtime data or a product decision. Say what you'd need. |

Downgrade the priority when the code disagrees with it: a `[P1]` you can't reproduce is not a
P1. Challenging a wrong finding is worth more than politely fixing it.

Mark an AGREE, PARTLY or NEEDS INFO finding **NEEDS HUMAN** when the fix needs a product
decision, changes a public contract (API/response shape, config schema, migration, access
rules), or is a redesign rather than a local fix. These are the operator's call in every mode.

## Phase 3 (interactive) — Present and block

One table, ranked by your assessed severity, not the reviewer's:

```
| # | Sev | Finding | file:line | Verdict | Proposed action |
```

Then the findings you'd act on as a numbered plan, one line each. **Stop. Edit nothing.** Ask
which numbers to apply (`1,3`, `all`, `none`). Touch only the approved items; don't quietly fix
the rest "while you're in there". Report what changed and what you skipped and why.

## Phase 3 (ship) — Fix, then hand back the rest

Being called by a ship flow is standing approval to fix verified defects. It covers nothing
else.

1. Apply every **AGREE**, and every **PARTLY** with your corrected fix. Skip NEEDS HUMAN and
   NEEDS INFO; drop DISAGREE with its reason.
2. Verify with the repo's checks that cover the touched files. A fix you can't get green is
   reverted and goes back as NEEDS HUMAN.
3. Commit the fixes on their own: `fix: address adversarial review findings` (exactly: the
   pre-PR review gate lets only this subject follow the recorded sha). Stage only the hunks
   you changed.
4. Return `<reviewed>` (below), the table with an `Outcome` column (`fixed` / `dropped` /
   `needs human`), and one one-line-answerable question per NEEDS HUMAN or NEEDS INFO finding,
   with the default you'd pick ("keep X or switch to Y? default: keep"). The caller asks them;
   don't guess and don't block.

## Record the review

Before phase 1, note `git rev-parse HEAD` as `<reviewed>`: the last commit the reviewer saw.
For a branch review, or a since-`<sha>` review whose `<sha>` was itself reviewed (the recorded
sha, or a `<reviewed>` a ship flow got back from an earlier run), record it once **no finding
is left open** — every
NEEDS HUMAN / NEEDS INFO question answered or carried into the PR body (in ship mode, by
the ship flow) — so the next run doesn't review the same commits twice:

```bash
echo <reviewed> > "$(git rev-parse --git-path adversarial-review.head)"
```

Record `<reviewed>`, never the current `HEAD`: fix commits made in phase 3 haven't been
reviewed, and the next review must see them. With open findings, delete the marker instead
(`rm -f` the same path), so an earlier review's sha can't mark these commits reviewed; a later run
re-reviews and surfaces them again rather than skipping past a pending decision. Never record
a `diff-failed` or `empty-diff` run, a failed reviewer, a working-tree or single-commit review,
or a since-`<sha>` review starting from an unreviewed commit: earlier commits would be skipped
unreviewed.

## Guardrails

- No line, no finding. A finding you can't anchor to code is dropped, not softened.
- The reviewer never writes: `-s read-only` / read-only tools only. Fixes are yours, after triage.
- Interactive mode edits nothing without an explicit list of approved numbers.
