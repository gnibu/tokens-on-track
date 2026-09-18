# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and released versions
match the git tags and `CFBundleShortVersionString`. Each release is also
published with generated notes on the
[releases page](https://github.com/gnibu/tokens-on-track/releases).

## [Unreleased]

### Added

- Claude and Codex model-specific quota rows, such as `week (Fable)` and
  `week (Spark)`, discovered from provider responses. Each discovered model is
  shown by default, remembered across responses that omit it, and can be hidden
  across every surface from Settings.
- A refresh button on the desktop card, and a spinner on both refresh buttons
  while a poll is in flight.

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
