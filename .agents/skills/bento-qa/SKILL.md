---
name: bento-qa
description: |
  Exercise a change end to end on its real surface (a real browser for web UI, else CLI or
  API), then pin every changed behavior with an automated test, bootstrapping the repo's test
  system if it has none. Interactive mode (default) reports defects; ship mode (called by a
  ship flow) scopes itself to the branch, fixes verified defects and returns a QA report.
  Triggers: "QA this", "test the site/app", "visual QA", "find bugs", "does this actually
  work", "smoke test the change", "add tests", "make this testable".
---

# QA

Drive the real surface the way a user would, then leave a test behind. Observation proves the
change works today; the test keeps it working. Every changed behavior ends either tested or
listed as untested with a reason.

Use the [shared evidence contract](references/proof.md) for before/after comparisons,
artifact provenance and reporting omitted checks. Repository-specific capture/upload steps
belong in this skill's overlay; the caller's permissions still govern uploads.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-qa.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Mode

| Mode | When | Defects | Testability changes to product code |
|---|---|---|---|
| **interactive** (default) | the user runs QA directly | report; fix only with `--fix` | propose |
| **ship** | only when called by a ship flow: `bento-ship`, or a repo skill that plays its role | fix verified ones; return the rest as questions | make them when small |

Both modes bootstrap a missing test system and add tests.

## Scope

A scope the caller or user gives is used as is. Otherwise: the branch,
`git diff origin/<base>...HEAD` (after `git fetch -q origin <base>`), plus uncommitted work.
`<base>` is the base branch `AGENTS.md` names, else `origin/HEAD`. The scope changes no
behavior (docs, comments, formatting) → report `QA: no behavior changed` and stop.

## Steps (paste as todos)

1. **Find the test system.** Read the checks `AGENTS.md` names, the manifests (`package.json`
   scripts, `pyproject.toml`, `Makefile`, `go.mod`, `Cargo.toml`) and CI config. Run the suite
   once for a baseline; tests already red are pre-existing, report them as such.
   A command that runs zero tests is no test system. **None → bootstrap the smallest one**
   native to the stack: the stdlib runner first (`python3 -m unittest`, `node --test`,
   `go test`, `cargo test`, a `tests/run.sh` of asserting commands for shell); for a web UI,
   also a headless browser runner (the one the repo already has, else Playwright) that starts
   the app itself. One command runs everything; record it as the checks line in `AGENTS.md`.
   Commit the bootstrap on its own (`test: add <runner> harness`).
2. **List the behaviors the scope changes** — each user-visible path plus its edge cases
   (empty, error, boundary, unauthorized). Map each to the test that covers it, or "none".
3. **Exercise each path on the real surface, end to end.** Name the driver. Capture evidence:
   screenshot, console/network log, exit code, response body.
   - **Web UI → a real browser, always.** Start the app and click through every critical
     journey the scope touches as a user would. Driver: under Claude, the Claude in Chrome MCP
     (`mcp__claude-in-chrome__*`) when connected; otherwise a browser CLI in the environment
     (`agent-browser`, Playwright). Screenshot each key state, and read console and network
     errors on every page. Unit tests alone never verify a UI change.
   - CLI/TUI → run the binary. API → curl/HTTP against the running service. Library → call it
     from a scratch script.
   Save screenshots outside tracked files (a gitignored dir or tmp).
   **A server you start in the background:** before testing against it, confirm the process
   listening on its port is yours (`lsof -nP -iTCP:<port> -sTCP:LISTEN` shows your PID).
   Another workspace's or a stale server on that port means testing the wrong code.
4. **Record defects with evidence.** For each: the steps, expected vs actual, and the captured
   artifact. No repro/artifact → not a confirmed defect.
5. **Pin each behavior with a test** in the repo's layout and style, at the cheapest level
   that catches it (unit before integration before end-to-end). Web UI: each critical journey
   also gets one end-to-end browser test in the runner from step 1. The Chrome MCP explores;
   only a runner test reruns on the next change. See it fail: write it against the defect
   before the fix, or break the code under it once. A test never seen red proves nothing. **Hard to test → the code needs a seam** (inject the clock, randomness or network;
   split logic from I/O). A small, behavior-preserving seam follows the mode table; anything
   larger is a finding: `untestable: <behavior> — needs <seam>`.
6. **Fix defects per the mode.** Root cause (see `bento-investigate`), the pinning test turns
   green, re-run the path on the surface.
7. **Run the full suite.** Green, with the new tests in it. Commit the tests (ship mode, or when
   asked) in conventional style, one logical change per commit.
8. **Report**, blockers first:

   ```
   QA: <pass | defects open | no behavior changed>
   Harness: <existing `<cmd>` | bootstrapped `<cmd>` in <sha>>
   Exercised: <path> — <driver> — <evidence: screenshot paths for web UI>
   Tests added: <file::test> — <behavior>
   Defects: <severity> <path>: expected / actual — <artifact> — <fixed in <sha> | open>
   Untested: <behavior> — <reason>
   Questions (ship mode): <one-line question> (default: <answer>)
   ```

## Guardrails

- A defect claim needs an artifact (screenshot/log/output). "Looks broken" isn't a finding.
- Test behavior, not implementation: assert on outputs and visible state, never on private
  calls or mocks of the unit under test.
- Never weaken, skip or delete an existing test to get green.
- "Untested" needs a reason. A behavior that silently ends up with neither a test nor a reason
  is a QA failure.
- A web UI change isn't verified until a real browser has run its journeys and shown no
  console errors.
- Bootstrap a test runner only: no CI pipeline, coverage gate or test framework beyond it.
- Don't trigger destructive or irreversible actions (deletes, real payments, emails) on the
  real surface. Test them against a fake or sandbox, and list the real path as untested.
