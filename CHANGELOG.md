# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions match the
git tags and `CFBundleShortVersionString`. Each release is also published with
generated notes on the [releases page](https://github.com/gnibu/tokens-on-track/releases).

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
