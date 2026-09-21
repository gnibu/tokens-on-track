# Claude Multiple-Account Support

**Date:** 2026-09-21  
**Status:** Approved in chat; awaiting written-spec review

## Goal

Allow Tokens on Track to display multiple Claude subscriptions at the same
time, especially a personal Pro or Max subscription alongside a Team
subscription. Each account keeps its own quota rows, pace calculations,
visibility settings, stale state, alerts, and plan badge.

The feature follows Claude Code's native profile isolation rather than adding
a second authentication system. Claude Code 2.1.56 and later stores a
non-default profile's OAuth credential in a namespaced macOS Keychain item
derived from its `CLAUDE_CONFIG_DIR`. Tokens on Track remains a read-only
consumer of those credentials.

## User Experience

With two configured Claude Code profiles, the usage surfaces show two separate
provider blocks. Their default labels are derived from the subscription type:

```text
Claude Personal                       MAX
5h          ...
week        ...

Claude Team                          TEAM
5h          ...
week        ...
```

Users can edit either label, which also supports less common arrangements such
as two work accounts. Account labels appear everywhere a provider name is
currently used, including the dropdown, desktop card, tooltips, summaries, and
notifications. Both accounts use the Claude glyph.

Settings gains a **Claude accounts** group. It lists:

- the default `~/.claude` profile, which is always known;
- profiles discovered from running Claude Code processes in the direct-download
  edition;
- profiles the user adds with a folder picker;
- previously discovered profiles that produced a valid credential and were
  remembered.

Each entry shows its label, profile location, and connection state. Labels are
editable. Non-default entries can be removed. A removed automatically
discovered path is ignored until the user explicitly adds it again, so a
running Claude process cannot immediately undo the removal.

The App Store edition cannot enumerate processes under its sandbox. It supports
the default profile and profiles explicitly added through Settings. This
limitation is explained in the connection copy rather than presented as an
error.

## Profile Discovery and Credentials

The default profile is the expanded absolute `~/.claude` directory. Its
Keychain service remains:

```text
Claude Code-credentials
```

For any non-default profile, the service is:

```text
Claude Code-credentials-<first 8 lowercase hex characters of SHA-256(path)>
```

The hash input is the expanded absolute path Claude Code receives through
`CLAUDE_CONFIG_DIR`. Normalization expands `~`, makes relative paths absolute,
and removes `.` and `..` components, but deliberately does not resolve symlinks
or change case: either change could produce a different string from the one
Claude Code hashed. The app applies the same normalization before persisting or
hashing paths and tests representative paths against known SHA-256 vectors. It
does not read, copy, refresh, or rewrite Claude's credential.

In the direct-download edition, process discovery reuses the existing
same-user, read-only process inspection pattern already used for transient
OpenRouter and Cursor credentials. It considers only processes identified as
Claude Code and extracts only `CLAUDE_CONFIG_DIR`. Captured process text is
discarded immediately. A profile is remembered only after its Keychain item
decodes as a Claude OAuth credential; merely observing an environment variable
does not create a permanent account entry.

Explicit folder selection stores the normalized path, a security-scoped bookmark
where the App Store build requires one for future presentation or validation,
and the optional label. Claude OAuth secrets remain solely in Claude Code's
Keychain items.

Candidate profiles are merged by normalized path in this order:

1. default profile;
2. explicitly configured and previously validated profiles;
3. currently discovered profiles.

After credentials are read, duplicate access tokens are collapsed in memory.
The explicitly configured candidate wins over a transient discovery, and the
default candidate wins an otherwise equal tie. Token hashes and tokens are
never persisted or logged.

## Provider Identity

The current report model assumes `Provider.name` is both a user-facing label
and the provider's stable identity. Multiple Claude accounts require those
responsibilities to be separated.

`Provider` gains:

- a stable `id` persisted in the report;
- a provider `kind` such as `claude`, `codex`, `openrouter`, or `cursor`;
- a user-facing `name` that can be `Claude Personal`, `Claude Team`, or a
  custom label.

Claude IDs are derived from the Keychain service name, not the current label,
so renaming an account preserves its history and preferences. Existing
single-provider IDs remain stable for Codex, OpenRouter, and Cursor.

Brand lookup uses `kind`, allowing both Claude blocks to draw the same glyph
without parsing their labels. Provider visibility, scoped-model visibility,
notification keys, row keys, menu-bar selection, stale carry-over, and fetch
timestamps use the stable provider ID. User-facing prose continues to use the
label.

Old cached reports have no `id` or `kind`. Decoding assigns legacy Claude data
to the default Claude profile and maps every other known provider by its
existing name. Existing hidden-provider and Claude model-limit preferences are
migrated to the default Claude profile. No old reading or preference is lost.

## Fetching and State Flow

At launch and on full refresh, the app builds the Claude profile catalog from
the persisted settings, default profile, and any available process discovery.
Each valid profile produces a separate poll target. Claude accounts are fetched
concurrently with one another and with the other providers.

For each profile, the fetcher:

1. derives the appropriate Keychain service;
2. reads and decodes `claudeAiOauth`;
3. assigns the stable account ID and resolved label;
4. sends the access token only to Anthropic's OAuth usage endpoint;
5. parses structured and legacy limits through the existing generic Claude
   window parser;
6. assigns the plan badge from `subscriptionType` without restricting it to a
   hard-coded list.

Known personal subscription values default to `Claude Personal`. Team and
Enterprise-like values default to `Claude Team` and `Claude Enterprise`.
Unknown non-empty values use the profile directory name, while the raw plan
value remains the badge. A custom label always wins.

Provider scheduling changes from one timestamp per provider name to one per
stable provider ID. Adding or discovering a profile triggers an immediate poll
for that account. Removing a profile removes it from the live report on the
next state update without deleting Claude Code data.

## Failure Handling

Accounts fail independently. If Team's credential is missing, expired, or
rejected, Personal continues to refresh and vice versa. The account's Settings
row explains the action using its profile path, for example to run Claude Code
with that `CLAUDE_CONFIG_DIR` and sign in. A stale token retains that account's
last useful reading under the existing carry-over policy.

A configured profile with no credential remains visible in Settings but does
not add an empty block to usage surfaces. Malformed credentials, unreadable
Keychain items, unknown subscription strings, future quota groups, and a mix of
legacy and structured limits degrade through the existing provider error and
generic parsing behavior.

If two profiles resolve to the same access token, only the preferred profile is
polled and displayed. This avoids duplicate network calls and misleadingly
double-counted menu-bar slots.

## Testing and Verification

Pure regression tests cover:

- default and namespaced Keychain service derivation;
- path expansion and normalization, including preservation of symlinks and
  case;
- merging default, configured, remembered, discovered, removed, and duplicate
  profiles;
- default labels for personal, Team, Enterprise, and unknown plan values;
- stable IDs surviving label changes;
- decoding and migrating old reports and preferences;
- independent account filtering, model visibility, stale carry-over,
  scheduling, notifications, and menu-bar selection;
- duplicate-token collapse without persisting token material;
- synthetic Team credentials and usage payloads, including unknown future
  structured quota rows;
- failure of one Claude account while another remains healthy.

The normal regression suite and both direct and App Store builds must pass.
Visual verification covers one-account and two-account states in the dropdown,
desktop card, Settings, and menu bar, including long custom labels and mixed
healthy/error states.

No Team credential is available in the development environment. The code will
therefore be verified against synthetic, secret-free fixtures and Claude Code's
current Keychain naming convention. Live Team validation remains a release
check to perform with a volunteer tester before claiming the feature as tested
against Anthropic's service.

## Documentation and Security

The README will explain how to create a second Claude Code profile with
`CLAUDE_CONFIG_DIR`, log into it, and add it to Tokens on Track. It will state
that Claude Code 2.1.56 or later is required for isolated macOS profile
credentials. The security section will document that profile paths are stored,
credentials remain in Claude Code's Keychain entries, automatic process
discovery is direct-download-only, and tokens are sent only to Anthropic.

The changelog will describe simultaneous Claude Personal and Team display and
note that live Team verification requires community testing.

## Out of Scope

- Logging into Claude from Tokens on Track.
- Refreshing or copying Claude OAuth tokens.
- Claude web-session cookies or organization APIs.
- Organization-wide admin analytics or aggregated Team-member usage.
- Combining two subscriptions into one synthetic quota.
- Supporting pre-2.1.56 Claude Code installations that overwrite a single
  shared macOS Keychain item.
