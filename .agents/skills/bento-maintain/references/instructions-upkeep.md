# Agent-instruction upkeep

Keep existing instructions accurate and correctly placed. This is mechanical upkeep;
new standing lessons belong to `bento-learn` and its proposal/approval flow.

1. Discover instruction files in scope, excluding dependencies, vendored skills and installed
   skills identified by the repository's skill lock/installation records. Read their source
   references. Use the placement rules in
   `bento-learn/references/instruction-layer.md` and any repository instruction procedure.
2. Check sibling `CLAUDE.md` discovery, relative links and anchors, skill routes, script paths,
   task-runner commands and flags against their actual definitions. Also identify duplicated,
   contradictory or misplaced rules. Follow the host's instruction discovery conventions;
   an `@AGENTS.md` companion is appropriate only for repositories using that arrangement.
3. Fix a stale reference only when its correct replacement is unambiguous. Preserve valid
   symlinks. If companions are required and creation is allowed, create the missing companion
   rather than duplicating the instructions. Moving a rule must retain its full meaning at
   its owning scope and leave a task-triggered pointer. Edit only instructions and their
   owning documentation when those destinations are inside the authorized scope.
4. Never weaken a safety boundary, permission requirement or production-data rule. Conflicting
   intent, a removed feature with no replacement, or a new policy → report a proposal without
   applying it. Generated instructions listed in `.bento-state/baseline.json` follow
   `bento-learn`'s three-way proposal workflow; if approval or baseline edits are outside this
   assignment, report the proposed correction instead of editing the managed file directly.
5. Re-read every moved rule at its destination and verify each corrected link, anchor and
   command against source. Report the reference that justifies each change, the files checked,
   and anything left unresolved. Bound a pass to one coherent group of fixes (about ten small
   corrections by default), leaving further independent work for the caller.
