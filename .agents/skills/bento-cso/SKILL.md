---
name: bento-cso
description: |
  Security audit of a change or surface — find vulnerabilities before they ship. Use for a
  security review, or changes to auth/permissions, trust boundaries, secret handling or
  sensitive data exposure, including untrusted input reaching queries, shells, file paths
  or templates. Routine internal data access alone is not a trigger. Triggers:
  "security review", "is this safe", "audit for vulnerabilities", "check for security issues".
---

# Security audit

Review the code/change against the common vulnerability classes and report real, evidenced
findings. Confidence-calibrated: don't surface what you can't point to.

`bento-ship` calls this audit conditionally before final checks. Return the scope, findings
and recommended fixes to the caller; the audit itself edits nothing. Ship triages local fixes
and carries product/public-contract decisions into its existing decision stop.

**Repo layer first.** Read the repo's `AGENTS.md`/`CLAUDE.md` and, if it exists, the
overlay `.agents/bento/bento-cso.md` at the repo root; follow it under the
[overlay rules](../bento-learn/references/instruction-layer.md#repo-overlays-for-bento-skills).

## Steps (paste as todos)

1. **Scope the surface.** What's exposed — endpoints, inputs, auth boundaries, data access,
   secrets, dependencies. External-facing and privileged paths first.
2. **Walk the checklist** against that surface:
   - **Input handling** — injection (SQL/command/template), unvalidated input, deserialization.
   - **AuthZ/AuthN** — missing checks, IDOR/broken object-level access, privilege escalation.
   - **Secrets** — hardcoded keys/tokens, secrets in logs/errors/URLs, over-broad scopes.
   - **Data exposure** — PII in responses/logs, tenant/row isolation, verbose errors.
   - **Dependencies** — known-vuln packages, untrusted sources.
   - **Web** — XSS, CSRF, unsafe redirects, missing security headers.
3. **Evidence each finding.** Cite the `file:line` and the concrete exploit path. A finding you
   can't anchor to code gets dropped, not softened.
4. **Rank by severity × exposure.** Critical/external first; note likelihood and impact.
5. **Recommend a fix per finding** — the specific change, not "be more careful."
6. **Report.** Findings ranked; state what you checked and found clean, so the audit's scope
   is legible.

## Guardrails

- No unanchored findings. Every issue names the code and the exploit; suppress the rest.
- Don't run live exploits against production or shared systems — reason from the code, or probe
  only an isolated target you're authorized to test.
- "No issues found in scope X" is a valid, useful result — say it plainly.
