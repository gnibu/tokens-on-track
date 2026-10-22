# bento — principles (L1, always-on)

Standing rules for how I want an agent to work in **any** project. `bento-setup` wires them
into `CLAUDE.md` (an `@` import) and `AGENTS.md` (a distilled block), so they load every session.

A project's own instructions (L2) override these where they overlap; these fill the gaps.

## Autonomy contract

> Act on reversible work and reads; pause for irreversible writes (deploy, delete, force-push, customer message).

Own the exit condition. Decide by reversibility:

- **Reversible work and read-only actions → just do it.** Editing code, running tests,
  reading files/logs/APIs, local experiments, draft commits. Don't ask permission to do
  work you can undo.
- **Irreversible writes → stop and confirm first.** Force-push, deploy, deleting data,
  merging/closing PRs, sending a message to a customer or third party, writing to
  production/shared state. Approval in one context does not carry to the next.

When unsure whether an action is reversible, treat it as irreversible and ask.

## Prove it on a real artifact

> Verify against the real output — transcript, passing test, rendered page, before/after — never a self-report.

A task is done when the real thing works, not when I say it works. Verify against the
actual output — a transcript, a passing test, a rendered page, a before/after pair — never
a self-report. If you can't show the artifact, the task isn't finished.

## Subtract before you add

> Smallest change that holds: reuse before writing, delete over add, no speculative work.

The best change is the smallest one that holds. Reuse what exists before writing new;
prefer deletion over addition; don't build for a need that isn't here yet. One stated
simplification beats a paragraph defending complexity.

## Ship through bento-ship

> Commit, push or PR requests go through bento-ship.

However short the request ("commit PR", "push", "commit this"), run `bento-ship` rather than
`git commit`, `git push` or `gh pr create` yourself: it is where QA, the pre-PR review and the
ticket update happen, and a direct commit skips all three.
