# Monitoring-driven error fix

Fix one reproducible root cause from a bounded set of monitoring issues. The repository or
caller supplies the provider, projects/environment, time window and candidate limit.

1. Fetch the supplied candidate set and rank impact: affected users, then severity of the
   broken path, then event count. Record the evidence for that order. Skip issues already
   owned by a PR/ticket, outside scope or impossible for repository code to prevent. Read the
   actual event/trace, not just its title. Missing monitoring access is a blocker, not a no-op.
2. Use `bento-investigate` in work-only context: reproduce, capture inputs/stack, trace the
   shared cause, test one hypothesis, fix it and add a regression test seen failing without
   the fix. A candidate requiring a production write, a public-contract decision or an
   out-of-scope change is disqualified; examine the next candidate and record the reason.
3. Expected/recovered failures can be actionable noise only when code proves recovery and no
   user-visible failure remains. Trace the emitter and the monitoring integration. Never hide
   exhausted retries, lost data or a real failure with a broad message filter. An intentionally
   monitored condition stays unless changing that policy was authorized. For a suppression,
   test both the recovered case not being reported and the real failure still being reported;
   for grouping, test that differing incidental values share a fingerprint.
4. Keep the fix small (about 80 changed lines by default) and at the root cause. Run the area's
   checks and regression. Report the selected issue id/link, impact, immediate/root cause,
   evidence, fixed behavior and every skipped candidate. Do not resolve, assign, ignore or
   comment on monitoring issues; the caller handles external state and delivery.
