# Dependency-security maintenance

Fix one bounded batch of concrete advisories sharing a dependency tree or root cause.
The repository supplies advisory access, package-manager commands, pins and checks.

1. Read available advisories/audit results and existing PRs or tracker ownership. Skip already
   owned fixes. Missing advisory access is not an empty alert list. Classify direct, transitive,
   major-upgrade, already-patched and unused candidates before choosing a batch; prioritize
   severity and evidence of production reachability.
2. Read the repository dependency skill if supplied as a lens. Use it for ecosystem-specific
   resolution and pins, within the caller's permissions. Respect do-not-bump rules and release
   cooldowns. A fix requiring a prohibited version, major behavioral migration or protected
   path is handed back, not silently substituted or suppressed.
3. Identify the manifests and lockfiles the actual build consumes. Change the owning
   dependency/override, regenerate that lockfile with the repository's tool and confirm the
   resolved version is fixed. Do not patch a leftover workspace lockfile the build ignores.
   Use bounded constraints and avoid unrelated resolution churn. Install only through tooling
   and commands the assignment allows; factory bootstrap restrictions still apply.
4. Run the relevant tests, type checks and advisory checks. Report fixed/skipped advisory ids,
   versions before/after, the lockfile actually consumed, and exposure/attack-vector/blast-radius
   evidence. Revert a batch whose required checks cannot pass without expanding scope.
5. Do not dismiss alerts, alter security allowlists, close dependency PRs, merge or create
   tracker issues here. An unused-package conclusion needs code evidence and goes to the caller
   as a proposed disposition. An upstream outage or blocked patch is not a verified fix.
