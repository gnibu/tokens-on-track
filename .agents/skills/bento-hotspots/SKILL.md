---
name: bento-hotspots
description: |
  Find the code most worth refactoring in Python, JavaScript and TypeScript, ranked by
  complexity x churn, with import cycles and fan-in/fan-out; or flag what a branch made worse.
  Use to assess code quality or pick refactoring targets; `bento-ship` runs its diff mode on
  every PR. Triggers: "is this code good", "code quality", "code health", "where should we
  refactor", "worst offenders", "hotspots", "technical debt", "what's the messiest code",
  "scheduled refactor", "bento-hotspots unattended mode".
---

# Hotspots

Metrics rank candidates; reading the code decides. A 60-line function can be fine and a
20-line one tangled. Never change code just to move a number.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-hotspots.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

**Run** from inside the repo: `uv run <this skill>/scripts/hotspots.py` (or `pipx run`).
Both read the script's inline `lizard` dependency. If they can't fetch it (offline), run the
script with any Python that already has lizard, such as the repo's `.venv/bin/python`, or
`pip install lizard` first. Never estimate the metrics by hand: if nothing runs, say the scan
didn't run. The script measures, per function: `nloc`, `ccn` (cyclomatic), `cognitive`
(Sonar cognitive complexity), `nesting` and `params`. Its limits are 50 / 10 / 15 / 3 / 5,
plus 500 NLOC per file. Pass paths to narrow the scan. Generated code (`dist/`, `build/`,
`*.min.js`, `*.d.ts`), vendored code, test data (`fixtures/`, `testdata/`) and untracked
files are skipped.

## Scan mode: "where should we refactor?" (paste as todos)

1. **Run the scan:** `hotspots.py [PATH ...] [--top N] [--since "6 months ago"]`. It ranks
   functions by cognitive complexity x (1 + commits touching the file), files by NLOC x
   (1 + churn), lists import cycles and the top fan-in/fan-out modules. Only imports that run
   at load time count: `import type`, dynamic `import()`, `TYPE_CHECKING` and function-local
   imports don't make an edge.
   Drop the entries in the overlay's `## Leave` list.
2. **Read each top entry before judging it.** Give each one verdict:
   - **refactor:** the branching or nesting makes it hard to follow, and you can name the
     target shape: which branches or states go away.
   - **leave:** long but linear, or inherently branchy (a parser, a dispatch table). Say why.
   - **exclude:** generated or vendored code the skip rules missed. Rerun on narrower paths.
3. **Cycles:** for each, name the one import edge that should go and where its code should
   live instead.
4. **Report** a ranked table: location, the metrics, the verdict, a one-line reason, and for
   each **refactor** its target shape. High fan-in modules raise the stakes of a change;
   say so next to them.
5. **Hand off, don't refactor here.** Each target the user picks goes through
   `bento-refactor` as its own change (pin behaviour, reshape, prove), and its rerun of the
   scan shows the metric dropped.

## Diff mode: "did this change make the code worse?" (paste as todos)

1. **Run** `hotspots.py --base origin/<base>`. It compares `HEAD` and the working tree with the
   merge base and reports only functions this branch made worse that are past a limit, files
   that grew past 500 NLOC, and import cycles a new import closed. Exit 1 means findings;
   2 means git failed (a bad `--base`, no repo), with git's message.
2. **For each finding,** read the function and either:
   - **simplify it in this change:** early returns over nested `if`s, a lookup over a branch
     ladder, or extracting a piece that has a name and a reason of its own; or
   - **justify it** in one line (inherent complexity, a test table) for the PR body's
     `## Open review questions`.
3. **Rerun** until it exits 0 or every remaining finding has its justification. Paste the
   final output as proof.

## Unattended mode: one refactor PR per run (paste as todos)

For a scheduled job (README, "Scheduled refactor"). The scheduled prompt is the user's standing
request for at most one draft PR per run. Nobody is there to answer, and nothing is merged.

1. **Start fresh:** `git fetch origin <base>` and work from `origin/<base>`.
2. **Scan,** then drop: the overlay's `## Leave` entries, files an open PR touches, and
   functions that already have a `hotspots`-labelled PR, open or closed (closed means rejected).
3. **Pick one target.** Read the candidates in rank order; the first **refactor** verdict
   wins. Each **leave** or **exclude** verdict on the way becomes a new `## Leave` line.
4. **No target** → open nothing. Report the top entries and the new `## Leave` lines.
5. **Refactor** it with `bento-refactor` on branch `hotspots/<file>-<function>`. It can't be
   pinned with a test → stop, discard the branch and report.
6. **Prove:** the pin green, a rerun of the scan showing the metrics dropped, and diff mode
   against `origin/<base>` exiting 0.
7. **Ship** with `bento-ship`: the new `## Leave` lines in their own commit, a draft PR
   labelled `hotspots` (create the label if missing) with before/after metrics in the body.
   Its single stop gets no reply: decisions keep their defaults and unapplied learnings go
   under `## Open review questions`.

**The `## Leave` list** in the overlay `.agents/bento/bento-hotspots.md` keeps a verdict from
being re-litigated every run. One line per entry, edited by humans or added through an
unattended run's PR:

```markdown
# Acme overlay for bento-hotspots

## Leave
- src/parser.ts: parseExpr: a recursive-descent parser, branchy by nature
- legacy/: vendored, never refactored
```

## Guardrails

- No gaming: splitting a function into one-caller helpers or moving lines elsewhere lowers a
  number and raises reader load. That is a regression.
- The limits flag; they don't fail a build. A finding with a written reason is resolved.
- Scan mode never edits code. Refactoring is `bento-refactor`'s job.
- Unattended mode opens one draft PR at most, never merges, and never refactors a function on
  the `## Leave` list.
