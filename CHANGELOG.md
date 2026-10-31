# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and released versions
match the git tags and `CFBundleShortVersionString`. Each release is also
published with generated notes on the
[releases page](https://github.com/gnibu/tokens-on-track/releases).

## [Unreleased]

### Added

- Claude saved usage resets beside the plan badge, including the restored
  limits, expiry, and confirmation before redemption. Expired and paused
  grants are excluded; availability is checked again before spending one.
  The coin shows the soonest expiry (`exp: 22/10/26`), or the time
  (`exp: 14:22`) once it is less than a day away.
- Codex usage-reset credits: a small ↺ coin with the count sits beside the
  plan badge. Clicking it explains when a reset helps and, once Codex says a
  reset would clear something, spends one after a confirmation.
- Reset alerts (Settings → Alerts, on by default): a notification when a
  weekly or longer quota clears — on schedule or early — and when a provider
  grants a new reset credit. The 5-hour session is never announced.
- A local MCP server (`--mcp`) with a `get_usage` tool, so a coding agent can
  check remaining quota before each task. Settings → Agents copies a setup
  prompt for Claude Code, Codex or any other MCP client.
- OpenCode Go as a usage provider, with 5-hour, weekly, and monthly quota
  windows from its usage API. The direct build discovers active OpenCode
  credentials and supported environment sources; Settings can store a key in
  Keychain for either edition.
- Multiple Claude Code profiles at once — for example Claude Personal beside
  Claude Team — each with its own quota rows, labels, visibility, and plan badge.
  The direct-download build can also notice running Claude Code processes;
  live Team verification still needs a volunteer tester.
- Multiple Codex profiles at once — for example a personal account beside a
  work account — using separate `CODEX_HOME` folders. Each account has its own
  quota rows, label, visibility, stale state, and plan badge.
- Claude and Codex model-specific quota rows, such as `week (Fable)` and
  `week (Spark)`, discovered from provider responses. Each discovered model is
  shown by default, remembered across responses that omit it, and can be hidden
  across every surface from Settings.
- A refresh button on the desktop card, and a spinner on both refresh buttons
  while a poll is in flight.
- Cursor as a usage provider. The signed-in Cursor app session is discovered
  automatically; Settings can also store a team Admin API key or a dashboard
  session token. Personal accounts show the current billing cycle, with Auto,
  API and on-demand rows when those counters are in use.

### Changed

- Development builds display the preceding release, commit distance, short Git
  SHA and dirty state; published app, bundle, DMG and tag versions are stamped
  from one implementation.
- The default refresh interval is 10 minutes (was 15), and 10 is now a
  selectable interval alongside 5, 15, 30 and 60.
- A poll that lands nothing now says the app keeps retrying by itself, instead
  of leaving "No reading yet" looking like a dead end. A provider with no
  reading is named once by the outage line rather than given an empty block of
  its own.
- Polling is now per provider: one that cannot be reached is retried every
  minute on its own, while the providers that answer keep the configured
  interval instead of being asked alongside it. A rejected token or key keeps
  the normal interval.
- OpenRouter connection guidance now points to the manual Keychain-backed API
  key field instead of promising that another Conductor task will reconnect it.

### Fixed

- Cursor no longer raises a Keychain prompt for the Cursor app's token or
  Conductor's saved `CURSOR_API_KEY` when a silent source (the Cursor app
  session, environment, a running Conductor process) already works.
- Denying a Keychain prompt for another app's item (Claude Code, Cursor,
  Conductor) is remembered: the app stops asking, even after a relaunch, until
  Settings → Keychain → Ask again.
- The usage alert no longer fires while a window is on or under target, e.g.
  61% of the week the day before it resets.
- Alerts no longer repeat every poll when Claude's reset time flips between
  `11:59:59` and `12:00:00`; a reset moving by under an hour is the same window.
- Row labels such as `5h` and `week` no longer render shrunk in the first
  provider block when more than one provider is shown.

## [1.1.0] - 2026-09-16

### Added

- OpenRouter as a budget-backed provider. Enter one monthly USD budget and its
  spend is shown as `day` and `month` windows alongside the Claude and Codex
  quotas. Credentials come from the app's own Keychain item, OpenCode's auth
  file, `OPENROUTER_API_KEY`, or a running Conductor OpenCode process.

## [1.0.1] - 2026-09-10

### Added

- An unversioned `TokensOnTrack.dmg` so the README can link to the latest build
  directly.

### Changed

- Automate Developer ID signing and notarization behind `release.py`.

### Fixed

- Say "out" when a window is fully spent, and say it once.

## [1.0.0] - 2026-09-01

Initial release: a native menu bar app replacing the Übersicht widget, with
Claude and Codex quota, a glass dropdown and desktop card, pace and
working-hours targets, alerts, and a signed, notarized `.dmg`.
