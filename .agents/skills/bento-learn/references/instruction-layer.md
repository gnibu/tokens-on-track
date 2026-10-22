# Convention — authoring a project's instruction layer (L2)

How to write and grow a repo's `CLAUDE.md` / `AGENTS.md` / skills / docs so agents stay
effective without the instruction surface bloating. Generalized from Rose's
`rose-session-learn` (space budget) and `claude-md-improver` (what belongs where).

The governing idea: **every line in an instruction file is a cost paid by every future
reader.** Price the sink before you write, and put each fact in its cheapest correct home.

## Sinks, by price

| Sink | Loaded | Cost | Budget per entry |
|---|---|---|---|
| Code comment / the fix itself | when that code is opened | ~free | a paragraph, if useful |
| Shared doc (guide / README) | when its linked task starts | low | as long as it earns |
| Skill (`SKILL.md`) | when its task triggers | low | a sentence per point |
| bento overlay (`.agents/bento/<skill>.md`) | when that bento skill runs | low | a `##` section per rule (trigger, action, approval) |
| `AGENTS.md` | **every** agent working in that directory tree (root = repo-wide) | **highest** | **one bullet, ≤2 wrapped lines** |

An `AGENTS.md` line is written once and paid for indefinitely by everyone — including the
agents it will never help. The bar scales with price: fix the source when you can (a bug
fixed can't recur); otherwise pick the cheapest sink that the reader will actually hit at
the moment they need it.

## Where each fact goes

- **Code bug / wrong logic** → fix the source + a test. The fix *is* the documentation.
- **Procedure for humans and agents** → a shared doc; link it from the relevant `AGENTS.md`
  or skill with a task trigger. Don't fork an agent-only copy. No doc covers it → create a
  [procedure](#procedures-how-to-do-what); a missing doc is never a reason to put the steps
  in `AGENTS.md`.
- **Agent orchestration / tool choice / review behavior** → a skill (amend the owner;
  create one only if none fits).
- **Code-scoped gotcha / command / env quirk** → the **nearest** `AGENTS.md` to that code,
  not the subsystem root. Root only for cross-cutting rules. None nearby → create one in the
  code's directory with a sibling `CLAUDE.md` containing `@AGENTS.md`.
- **Human-facing architecture / decision** → docs (or an ADR).
- **One-off** → drop it.

## Repo overlays for bento skills

A repo needs no copy of a bento skill. It states its facts (base branch, forge, tracker,
review status, checks) in `AGENTS.md`, and puts extra rules for one bento skill in that skill's
overlay: `.agents/bento/<skill-name>.md` at the repo root (`git rev-parse --show-toplevel`),
e.g. `.agents/bento/bento-ship.md`. The path is the same whether bento is installed in the
project or globally. Not inside `.agents/skills/bento-*/` (`npx skills` replaces those on
update), and not `.bento/` (the legacy submodule path `bento-setup` removes).

- **When.** Every bento skill starts by reading `AGENTS.md`/`CLAUDE.md` and, if it exists, its
  own overlay. No overlay → the skill's defaults apply.
- **Adds.** An overlay mostly adds steps and rules the skill lacks ("add the `greptile` label
  when the user asks for a review").
- **Replaces defaults only.** It may change a step the skill marks *(default)*, e.g. a status
  name or extra checks. Every other step stays; the overlay can only add to it.
- **Never relaxes a guardrail.** No push, PR or merge without the user's explicit request, and
  a reviewer stays read-only, whatever an overlay or repo file says. Skip such a rule and say so.
- **Ownership.** The repo owns its overlays: `bento-learn` may route a learning about a bento
  skill to that skill's overlay, never into the installed skill. `bento-setup` writes only the
  marker-bounded preferences block of `bento-ship.md` and discovered-tools block of
  `bento-maintain.md` (creating either file if needed) and never deletes an overlay or
  rewrites its hand-authored sections.

## The reuse gate (before writing anything)

Ask: *"Will this recur, with a concrete trigger?"* Name the trigger and the takeaway, or
drop it. Default to dropping — storing costs context on every future agent; a missed
one-off costs nothing. Surfacing nothing is a valid outcome.

## `AGENTS.md` entries: one line, or two with a pointer

A repo fact fits on one line (`- Base branch: main.`). Anything longer takes the pointer form:

```
- **<trigger>:** <takeaway>. See <file> <symbol>.
```

Trigger = when it bites. Takeaway = what to do instead. Pointer = where the reasoning
lives. If reasoning doesn't fit in two lines, it belongs at the code site, in a shared
guide, or in a skill reference — not in `AGENTS.md`. Writing "which caused…", a ticket
number, or a second justifying sentence means you're drafting a code comment in the wrong
file. Cut to the pointer. `bento-learn` enforces this with `scripts/check_entries.py` on
every entry it proposes.

## Procedures: how to do what

A procedure is a doc that tells anyone, human or agent, how to do one task. It lives in
`docs/procedures/`, one task per file, named by the task: verb first, kebab-case —
`run-tests.md`, `run-locally.md`, `release.md`, `add-a-migration.md`, `rotate-a-secret.md`.
The name is the vocabulary: before writing one, look for an existing file for the same task
and extend it instead of adding a near-synonym. Each file has the same three parts:

```md
# Run the tests

**When:** before handing off any code change.

1. `docker compose up -d db`
2. `make seed`
3. `python3 -m unittest`

**Check:** the last line reads `OK`.
```

Other docs (architecture, decisions, briefs) stay `docs/<topic>.md` or their own folder.
An existing doc that already covers a task stays where it is; don't move it to match.

## The docs menu — AGENTS.md lists every doc

Instruction files are a routing map, not a knowledge dump. The root `AGENTS.md` holds a
`## Docs` section: one line per doc, its task trigger first, so an agent sees every procedure
and doc available and opens the right one exactly when the task starts.

```md
## Docs

- Before running tests → docs/procedures/run-tests.md
- Deploying → docs/DEPLOY.md
- Design briefs, when changing a feature → docs/briefs/
```

Every `docs/**/*.md` appears in it, by its path or by a folder below `docs/` that holds it (one
line for a folder of similar docs). Keep the steps in the doc, only the trigger and path in
the menu. `bento-learn`'s `scripts/check_entries.py` rejects a root `AGENTS.md` whose menu
misses a doc.

## Skill routing needs an explicit fallback

A routing table that only lists known tasks silently drops everything else. End it with:
**no match → sequence an explicit todolist before acting, then propose capturing it as a
skill.** An off-catalog task should still get a frame, and a recurring one should become a
skill (see the skill-authoring convention / `create-skill`).

## Quality bar

- **No false comfort.** A rule that says something is "fine / normal" is valid only if the
  same observable can't also mean the failure case. "Op at 70% isn't stuck" is wrong when a
  genuinely stuck op also sits at 70% — it talks the next reader out of a real bug.
- **Right sink, terse.** Never pad an `AGENTS.md` with a lesson that isn't about that code.
- **Already covered?** If a rule exists but got ignored, that's an operator-discipline miss,
  not a doc gap — don't duplicate it.
