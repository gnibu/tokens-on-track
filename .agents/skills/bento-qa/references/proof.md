# Proof of a change

Leave an artifact a reviewer can check without trusting the author. Choose evidence for the
changed behavior and include its location and result in the caller's report, ticket or PR.

| Change | Evidence |
|---|---|
| UI/layout | Comparable before/after screenshots of the actual flow; mobile and desktop for layout |
| Logic/refactor/dead code | Behavior pin or regression test, plus exact test/type-check/build commands and results |
| Agent/prompt behavior | The same input before/after; a representative dataset score delta beats one sample |
| Performance | Before/after measurements from the same command/environment over several runs |
| Config/data | Old/new values read back from the authorized isolated store, or a fixture-based validation when live writes are forbidden |
| Documentation/instructions | Corrected claims, links and commands checked against their actual owning sources; docs checks when required |
| Other | Request/response transcript, CLI output or a permitted read-only query showing the result |

Capture **before** first. For screenshots use the same path/query, account, viewport, scroll,
theme and form state. Capture the real application running this checkout's source; identify
the worktree's server/port. Keep full-viewport images, with any crop/annotation only additional.
Never fabricate an app, borrow an image or present an error/blank state as successful proof.
If the real app cannot run, state `Screenshot omitted: <reason>` and what other evidence exists;
a required UI check remains unverified. Stop only servers this task started.

Do not save production data to recreate a screenshot or run a destructive flow for evidence.
Use fixtures or an explicitly isolated environment; dirty a form and cancel when that suffices.
Never include secrets or customer data in artifacts. Respect the repository's upload/location
rules and the caller's permission to write to a tracker; no upload authority → return paths.

Record exact commands, exit/results and tests added. Missing tools, zero tests, a skipped
check or a source-only inspection are not a passing execution. Name pre-existing failures
separately. No possible evidence → say why and return the verification gap, never invent a pass.
