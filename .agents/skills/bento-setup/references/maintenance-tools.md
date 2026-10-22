# Map repository tools to maintenance tasks

Run this part of setup inside a target Git repository when `bento-maintain` is installed.
Discover integrations; do not install services, log in, create remote objects or run a
maintenance job during setup. No Git repository → skip repository mappings.

1. **Read declared facts first.** Inspect instructions, existing overlays and linked
   procedures. Then inspect manifests, task runners, CI, docs configuration, monitoring
   initialization and installed repository skills to fill gaps. Connected tools establish
   access, not which product the repository uses. Read configuration names/paths without
   printing credentials or environment values; do not read `.env` files for discovery.
2. **Map capabilities, not brands.** For each task record the actual tool/skill or procedure,
   its invocation/lookup method, applicable paths and source `file:line`:

   | Capability | Consuming task | Discover |
   |---|---|---|
   | Verification/bootstrap | code-improvement, security-fix, error-fix | Area test/type/lint commands and allowed setup procedure |
   | Instruction ownership | instructions-upkeep | Discovery/companion conventions, placement procedure, generated-file ownership |
   | Documentation | docs-upkeep | Docs roots, navigation/index config, audience/exclusion rules, link/build commands |
   | Dependency advisories | security-fix | Scanner or forge advisory access, package manager, consumed lockfiles, pins/cooldowns, dependency skill |
   | Error monitoring | error-fix | Provider/projects, environment, query/window, event lookup, candidate bound and diagnostic skill |
   | Forge and tracker | overlap checks and caller delivery | Pointer to the owning instructions/ship policy, plus PR/issue lookup method; no second tracker identity/team/status copy |
   | Protected paths | every task | Forbidden paths, generated files and deployment/production boundaries |

   Never infer a provider from another or choose a popular default. No monitoring declared
   → error-fix is `unavailable`. A configured service with no accessible tool/CLI is
   `configured, access unverified`; name what a worker would need. Multiple tools can map to
   different scopes. Record unresolved choices so a worker reports missing input, not guesses.
3. **Validate locally.** Check cited paths, task-runner recipes, manifest scripts and lens
   skills exist. Read check definitions to distinguish unit-only checks from checks needing
   secrets/services. Do not substitute easier checks. Record `command discovered, not executed`
   unless setup actually ran it. Identify the environment/access network-dependent checks
   need so a factory can provision it; do not simply discard them.
4. **Write discovered facts** to `.agents/bento/bento-maintain.md` inside
   `<!-- bento:maintenance:start -->` / `<!-- bento:maintenance:end -->`, creating it if absent.
   Use `## Discovered maintenance tools` with Trigger (task/scope), Action (tool/command and
   status), Approval (existing authority only) and source citations for each mapping. Reference
   manual sections rather than copying them. For forge/tracker identity, team, review status
   and ticket policy, link the owning AGENTS.md section or ship overlay; record only the
   maintenance lookup method/access status here. Do not restate those policy fields, even
   in a parenthetical beside the pointer. For example: `Policy: AGENTS.md:2; lookup:
   glab mr list / glab issue list; access unverified (CLI unavailable)`.
   Preserve everything outside the markers,
   including manual pins, protected paths and tracker policy. If a manual rule conflicts
   with discovery, report the drift and leave it intact; discovery grants no exception.
5. **Report coverage/gaps.** List changed mappings, unavailable capabilities and unverified
   access. An unchanged rerun leaves the file unchanged. No timestamps or rewriting manual
   sections. Workers still read current instructions: stale mappings cannot override policy.

Facts shared with ship remain in instructions or its overlay; link them rather than adding a
second registry. Global skill installs still write mappings per repository, never user-wide
provider defaults. Setup does not grant tracker writes or alter factory schedules/permissions.
