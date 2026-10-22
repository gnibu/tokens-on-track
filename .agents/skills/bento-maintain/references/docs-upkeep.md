# Documentation upkeep

Repair navigation, indexes, links and factual drift using the repository's documentation
system. Discover its framework, root and page-to-index rules rather than assuming them.

1. Discover the docs roots, navigation/index configuration, build/check commands and public
   versus internal audience boundaries from repository instructions. Check links and anchors
   against real files/headings. Check page inclusion and navigation relative to each config's
   own root, including generated or excluded pages.
2. Select one coherent set of stale references or claims. Verify documented commands against
   code/task runners and recent relevant changes. Add an index/nav entry only when repository
   policy requires it; a scratch note is not automatically a published page. A public page must
   not link to excluded or staff-only content.
3. Use `bento-docs` in work-only context to update the existing owning passage or navigation;
   avoid a parallel guide. Correct claims from current code, not from what an old PR intended.
   Ambiguous replacements or policy questions are findings, not guessed edits.
4. Run the repository's docs/link checks when available and permitted. If the caller supplies
   an explicit read/edit-only validation procedure, follow it and disclose the omitted build;
   never claim that source inspection proves rendering. Report corrected references and their
   source evidence, audience checks and any unresolved broken links in the scanned scope.
