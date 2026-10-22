# Adopt maintenance in an existing factory

Keep scheduling, budgets, leases, retries, tracker writes and PR delivery in the factory.
Install all Bento skills together so maintenance can reuse refactor, docs, investigation,
learning conventions and QA's proof reference. A missing required skill is a blocker; never
fall back silently to a stale copied procedure.

Each job's local procedure invokes `bento-maintain <task> <scope> --factory` and passes its
permissions and any narrower file rules. The worker returns edits, proof and an outcome;
the adapter performs authorized tracker writes and adds the required report prefix/packages.
Keep output names and job ids stable when replacing a copied procedure.

Put shared repository facts in `AGENTS.md`, and task-specific facts in
`.agents/bento/bento-maintain.md`. For example:

```markdown
# Acme overlay for bento-maintain

## Checks
- Trigger: code-improvement or error-fix in src/.
- Action: run `python3 -m unittest discover -s src`; see docs/testing.md.
- Approval: local verification within the assignment.

## Protected paths
- Trigger: every task.
- Action: never edit migrations/, secrets/, generated/, or factory configuration.
- Approval: this assignment grants no exception.

## Documentation
- Trigger: docs-upkeep.
- Action: check docs/nav.yml against docs/pages/; use `make docs-check` when shell is allowed.
- Approval: edits only inside the assigned docs scope.
```

Use the local dependency skill as the security task's lens and supply monitoring projects,
query/window and candidate count for error-fix. An adapter that can read/edit but cannot run
a shell must specify the permitted source-only checks; it must not report a successful build.
Keep denied commands, network failures and blocked-host output in the factory's failure format.

An existing complexity job continues to call `bento-hotspots`; it is not a sixth maintenance
implementation. Keep ticket queue selection in the factory. For review-derived lessons call
`bento-learn --reviews --propose-only`. For a larger cleanup call `bento-multi-phase-plan`
to inventory sites and propose batches; execution follows the caller's actual authorization.
