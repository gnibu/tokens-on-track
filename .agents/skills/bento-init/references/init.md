# Generating and evolving L2

`../SKILL.md` is the generation workflow: `/bento-init` in Claude, `$bento-init`
in Codex. Both use `scripts/l2-state.py` (Python 3.9+ and Git). No model SDK,
API key, or new service is needed by the helper.

Use potion off-the-shelf until its generation workflow is outgrown. This bento
workflow provides reviewed phases and a generated baseline for repos that need
subsequent updates to preserve hand edits. Inspiration: [potion](https://github.com/aureliensibiril/potion),
not copied implementation.

## Source collection and checkpoints

The agent collects and interprets sources; the helper never invokes an LLM or
executes commands found in a document. Keep an evidence table in the conversation:

| Source | Evidence | Proposed rule / gap |
|---|---|---|
| Code | Path, symbol, CI job or manifest script | Observed convention and relevant trigger |
| Docs | Guide and section | Existing procedure to link, contradiction to resolve |
| Merged PR reviews | PR and comment URL | Recurring gotcha corroborated in current code |

Collect merged PR reviews using the shared
[review-history procedure](../../bento-learn/references/review-history.md), starting with
20 recently merged PRs and verifying the feedback against current code. `bento-learn`
reuses that collection only when historical review input is requested. A missing remote,
forge access, or empty sample must be reported in the phase-1 checkpoint. Ask whether to
proceed with other sources or gather more; do not infer approval from silence.

The checkpoints are **evidence → file design → exact generated diff → handoff**.
The user can reject or revise any phase. The JSON helper's `--apply` is not a
substitute for these human checkpoints. No background hook initializes an L2.

## File and baseline contract

`<skill>` is the installed `bento-init` skill directory (e.g.
`.agents/skills/bento-init` or `~/.claude/skills/bento-init`). The examples below run from the target repo root;
`proposal` points to a temporary JSON file outside that repo. The helper requires
`--repo` to be a Git worktree root.

```json
{
  "schema_version": 1,
  "files": {
    "AGENTS.md": "# Project instructions\n\n- **Changing code:** run the checks in README.md before handoff.\n",
    "CLAUDE.md": "@AGENTS.md\n"
  }
}
```

Replace the example with instructions grounded in the target's evidence. Values
are complete UTF-8 text, not patches. Allowed targets are `AGENTS.md`/`CLAUDE.md`
at the root or in ordinary subdirectories, Markdown under `docs/`, and Markdown
under `.agents/skills/<name>/` (Claude reads it through the `.claude/skills` link;
a real `.claude/skills/<name>/` is allowed only in repos without that link). No source code,
settings, hooks, credentials, or bento's vendored L1 files are generated.

```sh
python3 "<skill>/scripts/l2-state.py" --repo . check
python3 "<skill>/scripts/l2-state.py" --repo . init "$proposal"
# Only after the user approves the displayed diff:
python3 "<skill>/scripts/l2-state.py" --repo . init "$proposal" --apply
```

`check` and `init` refuse existing root/nested instruction files, agent skills or
commands/rules, or `.bento-state/`, including untracked and locally deleted tracked
instructions. They skip `.git`,
installed `bento-*` skills, `.context`, and common dependency/build directories. A
`.claude/skills` link to `.agents/skills` is inspected through its target. If a repo
keeps an L2 in another excluded dependency directory or uses a different instruction
format, identify it during inspection and stop rather than treating it as greenfield.
Existing MCP settings alone are not an L2. `init` requires both root entry points
and refuses to overwrite **any** proposed target, including existing docs.

The committed `.bento-state/baseline.json` uses the same version-1 format. Its
`files` map contains the **last generated text**, not a snapshot of later manual
edits. Commit this file alongside generated L2 files in the consuming repo; do not
store it inside an installed bento skill or Git's private directories.
No raw PR dumps, credentials, timestamps, or machine-specific paths belong in it.

## Updates with bento-learn

For files in the baseline, build an incoming proposal from their **baseline
text**, applying only the approved learning. Do not copy current hand-edited
files into the proposal or regenerate the whole L2 from scratch. A proposal can
include only the affected baseline paths; untouched entries remain unchanged.

```sh
python3 "<skill>/scripts/l2-state.py" --repo . merge "$proposal"
# After the user approves the merged diff:
python3 "<skill>/scripts/l2-state.py" --repo . merge "$proposal" --apply
```

For each file the helper merges **current file / last generated baseline /
proposed generated text** with [Git's three-way merge](https://git-scm.com/docs/git-merge-file)
(`git merge-file --diff3`). Non-overlapping hand
edits survive. On success the file gets the merged text, while the baseline gets
the incoming generated text. This distinction preserves manual ownership across
multiple improvements. Repeating the same proposal is a no-op.

On any conflict, even with `--apply`, the helper prints the conflict with labelled
current/baseline/proposed sides and exits 1. **No target or baseline is written**,
including other conflict-free files in that proposal. Revise the generated proposal
to avoid the conflict, preview again, and get approval for the revised diff. Do not
resolve it by copying current text into the baseline or overwriting the target.
If the learning cannot be separated from a conflicting hand edit, leave it unapplied
for human review.

An absent baseline means the repo was not initialized here: use normal targeted
diff-and-propose, never initialize over it or manufacture a baseline from current
files. Files outside the manifest remain ordinary hand-authored L2, even when
created by a later improvement. Adding/removing managed paths, renaming them,
deletions, or migrating baseline versions requires a separate reviewed migration;
this helper refuses them instead of guessing ownership.

## Operational behavior and verification

Both commands preview by default. They validate all proposed paths and merge all
files before writing; reject traversal, symlinks, hardlinks, case collisions,
invalid state, and missing managed targets. A per-worktree Git lock serializes
helper invocations. Apply checks that files still match its planning snapshots;
ordinary editors do not take this lock, so avoid editing targets during apply.

Individual files use atomic replacement, the baseline is written last, and normal
I/O failures trigger rollback. This is **not** a crash-atomic multi-file transaction:
after a process/machine crash, inspect the working-tree diff and baseline together
before retrying. A crash may leave `bento-l2.lock` in the worktree's Git directory;
remove it only after confirming the recorded process is no longer running.

Run the deterministic CLI tests with:

```sh
python3 -m unittest discover -s plugins/bento/skills/bento-init/scripts -p 'test_l2_state.py' -v
```

These tests exercise real temporary Git repos, file diffs, and Git three-way merges.
The planning evals test checkpoint and baseline reasoning with/without the plugin:

```sh
claude plugin eval ./plugins/bento --runs 3 --ablation with-without --no-publish
```

Those scenarios are explicitly hypothetical; they test explanations, not actual
file generation. Neither suite establishes the quality of an agent's evidence
selection for a particular project; review generated output at the checkpoints
in the real target repo.
