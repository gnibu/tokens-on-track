---
name: bento-setup
description: |
  Wire Bento's principles, skill links and pre-PR review gate, migrate legacy installs, record
  ship preferences and discover the repository's real maintenance tools. Idempotent and local,
  so run after every Bento npx skills add/update. Args: --yes uses preference defaults; --preferences
  re-asks them; --purge unwires.
---

# bento setup

`npx skills` installs the playbooks. This skill wires the one thing a skill can't carry:
the always-on principles in `PRINCIPLES.md` (next to this file). Every step is idempotent.
Report failures instead of claiming setup completed.

**Safe to run unprompted.** Setup edits local instruction files, the skills link and its
marker-bounded overlay sections, which the user reviews before committing. A rerun with
unchanged facts changes nothing. That is reversible work under the autonomy contract: after any
`npx skills add` or `npx skills update` of bento, run this skill yourself, without asking
first. Only the steps marked *confirm* below (machine-wide or moving real folders) and the
ship preference questions, asked once per repo, pause.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-setup.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

`<skill>` is this skill's directory. Run from the consumer repo root.

## Scope

Match where bento's skills are installed:

- **project** — `.agents/skills/bento-setup/` or `.claude/skills/bento-setup/` exists in the
  repo (committed with `skills-lock.json`, so the repo pins its bento version).
- **global** — `~/.agents/skills/bento-setup/` or `<claude-dir>/skills/bento-setup/`.

`<claude-dir>` is `$CLAUDE_CONFIG_DIR` if set, else `~/.claude`, resolved to an absolute
path (npx skills uses the same rule; `CLAUDE.md` imports don't expand variables).

Both present → ask (`--yes`: project). Neither → stop and tell the user to run
`npx skills add gnibu/bento --skill '*'` (add `-g` for global).

To update, rerun that same `npx skills add` command, then this skill. Prefer it to
`npx skills update`, which re-adds only skills whose hash changed: it skips skills installed
before skill-path tracking (printing their `npx skills add … -y` command instead) and never
installs a skill bento added since, one an updated playbook may call. If `update` already
ran, run the `add` command it printed (or the full one above), then this skill.

## Apply

1. **Migrate** if any legacy install is detected (next section). Do it first.
2. **Claude skills link** (project scope with `.agents/skills/`). Claude reads skills from
   `.claude/skills/`, Codex from `.agents/skills/`. Per-skill links drift (a skill added
   later gets no link, so Claude can't invoke it); one directory link can't:
   `.claude/skills -> ../.agents/skills`. `npx skills` keeps this layout on `add` and `update`:
   it skips the per-skill link when `.claude/skills/<name>` already resolves to the installed
   folder.
   - Already a link resolving to `.agents/skills` → nothing to do.
   - Missing → `mkdir -p .claude && ln -s ../.agents/skills .claude/skills`.
   - A directory holding only links that resolve into `.agents/skills/` →
     `rm -r .claude/skills && ln -s ../.agents/skills .claude/skills` (removes the links,
     not their targets).
   - Anything else (real folders, e.g. from `--copy`, or links elsewhere) → *confirm*: list
     them and offer to move each real folder to `.agents/skills/<name>` (stop on a name clash)
     before linking. `--yes` or declined → leave it and report the `.agents/skills/bento-*`
     with no `.claude/skills` entry.

   Global scope: leave `<claude-dir>/skills/` alone; it holds the user's other skills.
3. **Claude principles.** If `CLAUDE.md` (project or global) is a symlink to the `AGENTS.md`
   of step 4, skip this step and report "Claude reads the AGENTS.md block via the CLAUDE.md
   symlink": an import would load the principles twice for Claude and leave a stray `@path`
   line in Codex's file. Otherwise ensure the target `CLAUDE.md` contains the import line, appended as
   its own block at the end (imports mid-file are disallowed):

   ```
   # bento (always-on principles)
   @<import>
   ```

   - project: `./CLAUDE.md`, import `.claude/skills/bento-setup/PRINCIPLES.md`
   - global: `<claude-dir>/CLAUDE.md`, import `<claude-dir>/skills/bento-setup/PRINCIPLES.md`

   Skip if the line is present. Check the import target exists; if it doesn't, Claude
   wasn't an install target (`npx skills add ... -a claude-code`).
4. **Codex principles.** `python3 "<skill>/scripts/agents_block.py" <AGENTS.md>` with
   `./AGENTS.md` (project) or `${CODEX_HOME:-~/.codex}/AGENTS.md` (global). The block is
   marker-bounded and distilled; the script prints `added`, `updated` or `unchanged` (no
   write). Edit the `AGENTS.md` source, never a `CLAUDE.md` symlink.
5. **Pre-PR review gate.** A skill runs only when the agent picks it, so a hook backs the
   principle "commit, push or PR requests go through bento-ship": it blocks `git push` and
   `gh pr create` with "Run bento-ship first: no pre-PR review recorded for HEAD." unless the
   sha `bento-adversarial-review` recorded is `HEAD` (or only its fix commits follow), or the
   overlay says `Pre-PR review: skip`. For each agent that was an install target:

   - Claude: `.claude/settings.json` (project) or `<claude-dir>/settings.json` (global).
   - Codex: `.codex/hooks.json` (project) or `${CODEX_HOME:-~/.codex}/hooks.json` (global).
     Codex runs a new or changed hook only after the user trusts it; say so in the report.

   Run `python3 "<skill>/scripts/push_gate.py" install <file>` on each. It prints `added`,
   `updated` or `unchanged` and keeps every other hook.
6. **Ship preferences** (inside a git repo, either scope). The repo's answers to
   [bento-ship's preferences](../bento-ship/SKILL.md#preferences) live in a marker-bounded
   block of its overlay `.agents/bento/bento-ship.md`:

   ```markdown
   <!-- bento:preferences:start -->
   ## Ship preferences
   Written by `bento-setup`; change with `/bento-setup --preferences`.

   - Missing ticket: create
   - Ticket update: yes
   - Tracker: Linear, team TT, review status In Review
   - QA: always
   - Pre-PR review: always
   - Learnings: yes
   - PR reviewers: none
   <!-- bento:preferences:end -->
   ```

   - Ask, in one message, only the questions the block doesn't answer yet: each with its
     values, default first, and the step it controls. All answered → ask nothing and write
     nothing, so a rerun after an update asks only questions a newer bento added.
   - `Tracker`: take the tracker, team or project and review status from `AGENTS.md`/`CLAUDE.md`
     and ask only for what's missing (no tracker → `none`).
   - `--yes`, or no one to answer (an unattended run) → record the defaults and list them in
     the report.
   - `--preferences` → ask every question again, the recorded answers as defaults.
   - Write only between the markers: create the overlay (title `# Overlay for bento-ship`) or
     append the block if it has none; keep every other line.
7. **Discover maintenance tools** (inside a Git repo, either install scope, when
   `bento-maintain` is installed). Follow [maintenance-tools.md](references/maintenance-tools.md)
   to map the actual docs system, monitoring, advisory tooling, checks, forge and tracker to
   their consuming tasks. Record source-cited mappings and gaps in the marker-bounded section
   of `.agents/bento/bento-maintain.md`; preserve manual rules. No service is assumed or
   provisioned. Missing providers remain unavailable until the repository supplies them.
8. **Verify.** Show the diff of each file touched. A running session doesn't reload skills,
   so ask fresh headless sessions from the repo root and compare with `ls -d .agents/skills/bento-*`
   (global: `~/.agents/skills/bento-*`):

   ```sh
   claude -p "Without using any tool, print the count and names of your skills starting with 'bento-'." --max-turns 1
   codex exec "Without using any tool, print the count and names of your skills starting with 'bento-'."
   ```

   Run the agents that were install targets. A missing skill is a failure to report, not a
   pass.
9. **Report overlays.** List the repo's overlays (`.agents/bento/*.md` at the repo root) with
   each one's `##` rule headings, so the user sees which bento skills are customised here.
   None → say so. Then the ship preferences, marking those written this run and whether each
   is a default or the user's answer. Include maintenance mappings, their sources and any
   unavailable or unverified capabilities.

Project-scope changes (`CLAUDE.md`, `AGENTS.md`, `.agents/`, `.claude/skills/`,
`.claude/settings.json`, `.codex/hooks.json`, `skills-lock.json`) are for the user to review
and commit. Setup owns only the preferences
block of `.agents/bento/bento-ship.md` and the discovered-tools block of
`.agents/bento/bento-maintain.md`, creating either file if needed. Setup, migrate and purge
never delete an overlay or touch its hand-authored sections.

## Migrate from the submodule/plugin install

Detect each legacy piece; remove only what is present. Report each removal.

1. **Submodule** (`.bento` in `.gitmodules`):
   `git submodule deinit -f .bento && git rm -f .bento`, then
   `rm -rf "$(git rev-parse --git-dir)/modules/.bento"`. Use `--git-dir`, never
   `--git-common-dir`: from a linked worktree the latter is the main checkout's submodule
   repository, still used by its checkout. Remove
   `git submodule update --init .bento` from any setup script (e.g. Conductor's).
2. **Claude plugin and marketplace** (`claude plugin list` shows `bento@bento`,
   `bento-core@bento` or `bento-forge@bento`): `claude plugin uninstall <id>` for each, then
   `claude plugin marketplace remove bento`. This is machine-wide: *confirm* first, since other
   repos on this machine lose the plugin too (install bento globally, or migrate them).
   Remove `bento` from committed `extraKnownMarketplaces` / `enabledPlugins` in `.claude/settings.json`.
3. **Old hooks.** Delete `SessionStart`/`Stop` handlers whose command mentions
   `.bento/plugins/` from `.claude/settings.json`, `.claude/settings.local.json`,
   `<claude-dir>/settings.json` and `${CODEX_HOME:-~/.codex}/hooks.json`, and the
   `# bento:hooks:start` … `# bento:hooks:end` block from `.codex/config.toml`. Keep unrelated
   handlers. Then `rm -f ~/.bento/update-reminder` and remove `~/.bento` if empty.
4. **Codex links.** Codex reads `<repo>/.agents/skills/` directly, so a project `.codex/skills/`
   is redundant. Delete its symlinks into `.bento/` (dangling once the submodule is gone) or
   `.agents/skills/`. Real folders left there → *confirm* moving each to `.agents/skills/<name>`.
   Remove `.codex/skills/` once empty.
5. **Old principles import.** Remove the `# bento (personal agent kit — always-on principles)`
   heading and its `@…/principles/PRINCIPLES.md` line from `<claude-dir>/CLAUDE.md`.
   Apply step 3 writes the new one. The `AGENTS.md` block keeps its markers, so Apply step 4
   rewrites it in place.

## Purge (`--purge`)

1. Remove the `# bento (always-on principles)` block from the `CLAUDE.md` for the scope.
   Keep the `.claude/skills` link: the repo's own skills may live behind it.
2. Remove the `<!-- bento:start -->` … `<!-- bento:end -->` block from the `AGENTS.md`,
   keeping unrelated instructions.
3. Run `python3 "<skill>/scripts/push_gate.py" uninstall <file>` on each file Apply step 5
   writes for the scope.
4. The skills themselves: `npx skills remove` each `bento-*` skill, same scope (`-g` for global).
