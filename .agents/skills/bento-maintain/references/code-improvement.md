# Code improvement

Make one small change that preserves behavior for every caller. The caller supplies the
scope; the repository supplies its conventions and checks.

1. Prefer a demonstrable reuse of an existing helper, removal of proven dead code, a precise
   existing type replacing an escape hatch, then a simpler equivalent expression. Search
   repository-wide for callers, dynamic references, entry points and the shared alternative.
   An exported API is not dead merely because this repository has no caller.
2. Pick one package and one reason to change. A diff around 60 changed lines is a useful
   default, not a reason to split code artificially. Do not change public signatures, API
   payloads, queries/schema, config formats, dependencies, prompts, generated files or existing
   test expectations as a code-quality cleanup. Uncertain behavior → skip the candidate.
3. Use `bento-refactor` in work-only context: pin current behavior first, make the structural
   change, then prove equivalence. Type-check and lint alone are not a behavior pin. When a
   dependency or dead-code finder reports a candidate, verify it against real references
   before deleting it; leave reflection and externally consumed entry points alone unless proven.
4. Run the area checks and pin. Report the searches proving the change's premise and why
   callers behave identically. A change that merely moves complexity or adds a one-caller
   abstraction is not an improvement. Use `bento-hotspots` when the actual request is to rank
   complexity, rather than reimplementing its selection here.
