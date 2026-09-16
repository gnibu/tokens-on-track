# OpenRouter Budget Support

Date: 2026-09-16

## Objective

Add OpenRouter to Tokens on Track as a budget-backed provider that looks and behaves like the existing Claude and Codex quota providers. The user sets one monthly USD budget. The app reads current OpenRouter spend, derives `day` and `month` quota windows, and feeds those windows through the existing pacing, ranking, menu bar, notification, stale-reading, dropdown, and desktop-card systems.

The first version uses an ordinary OpenRouter inference key. It does not require a management key, account-wide credit access, or historical analytics.

## User experience

### Usage surfaces

Once connected and given a monthly budget, OpenRouter appears as an ordinary provider block on the dropdown and desktop card:

- The provider heading uses the official OpenRouter glyph and a plan badge such as `$20 / MO`.
- The `day` row shows today's OpenRouter spend against a daily allowance derived from the monthly budget.
- The `month` row shows month-to-date spend against the monthly budget.
- Both rows use the existing filled track, target notch, usage percentage, pace colour, reset label, worst-row marker, menu bar gauge, ranking, and alerts.
- Each OpenRouter row adds a small second line in its existing label column for exact USD amounts, for example `$0.11 / $0.67` and `$0.11 / $20`. Other providers retain their current one-line rows.
- Tooltips include both the existing percentage/pace explanation and the exact USD amount.

The global **Used / Vs target** preference applies unchanged. A gauge always fills to the share of its budget consumed; the printed percentage follows the selected preference.

### Settings

Settings gains an **OpenRouter** group that remains available even before the provider is connected. It contains:

- Connection status and the active credential source.
- A masked control to add or replace an API key.
- A control to remove the saved key when one exists.
- A monthly budget field denominated explicitly in USD.
- The existing provider visibility control once OpenRouter has connected successfully.

The monthly budget begins unset. It accepts any finite positive USD value. If a credential works but the budget is unset or invalid, the provider reports `set a monthly budget in Settings` and does not draw a fabricated zero gauge.

Changing the budget immediately recomputes cached OpenRouter window percentages from cached spend amounts. It does not depend on another network request succeeding.

## Spend and budget calculations

The app calls `GET https://openrouter.ai/api/v1/key` with the chosen key as a Bearer token. The ordinary-key response provides `usage_daily`, `usage_weekly`, and `usage_monthly`; only the daily and monthly values are needed in this version.

OpenRouter's usage periods are treated as UTC periods:

- The day window starts at 00:00 UTC and resets at the next 00:00 UTC.
- The month window starts at 00:00 UTC on the first day and resets at 00:00 UTC on the first day of the next month.
- The daily allowance is `monthly budget / number of days in the current UTC month`.
- Day usage percent is `usage_daily / daily allowance * 100`.
- Month usage percent is `usage_monthly / monthly budget * 100`.

Percentages may exceed 100. The existing track and ring cap their drawing at a full circle/track while severity, text, and alerts retain the true percentage.

Window lengths and reset timestamps are supplied exactly, including variable month lengths and leap years. This lets the existing `Pace` implementation calculate target notches and pace ratios. The existing optional working-hours schedule also applies to OpenRouter windows; it redistributes the target, not the underlying USD budget or spend.

The manual budget is local display policy. The app does not create or modify an OpenRouter key limit.

## Credential discovery and security

Credential candidates are considered in this order:

1. A manually supplied OpenRouter key stored by Tokens on Track in the macOS Keychain.
2. An `openrouter` credential in OpenCode's standard `~/.local/share/opencode/auth.json` file.
3. `OPENROUTER_API_KEY` inherited by the Tokens on Track process.
4. An `OPENROUTER_API_KEY` found in a running Conductor-managed OpenCode ACP process.

The manual Keychain credential is authoritative. If it receives a 401, the app reports `key rejected — update it in Settings` rather than silently selecting another credential. Invalid automatic candidates may be skipped in favour of the next automatic candidate.

Conductor discovery is deliberately best-effort because Conductor does not expose a documented credential API. The app finds processes whose command identifies the versioned Conductor OpenCode ACP binary, reads the environment of those same-user processes, extracts only `OPENROUTER_API_KEY`, deduplicates candidates, and discards the captured process text immediately. A Conductor credential:

- is used only while a matching process is running;
- stays in memory;
- is never copied into Tokens on Track's Keychain or cache;
- is never printed or logged;
- is sent only to `https://openrouter.ai`.

The Settings status names transient discovery clearly, for example `Conductor · available while OpenCode runs`. If it disappears, the previous successful reading follows the app's existing stale-reading policy and the Settings group offers the manual Keychain fallback.

The app uses Security.framework for its own Keychain item so the secret is not placed in process arguments. The usage cache never contains an API key. It contains only non-secret spend totals, budgets, percentages, reset timestamps, and provider state.

## Data model and components

### `UsageWindow`

Add optional Codable USD metadata:

- `spentUSD`
- `budgetUSD`

Older caches decode with both values absent. Claude and Codex windows leave them absent. OpenRouter uses them for the secondary label, tooltip, and local budget recalculation.

### OpenRouter mapping

A small pure mapping unit converts `(daily spend, monthly spend, monthly budget, date)` into two `UsageWindow` values. Keeping UTC boundary and percentage calculations outside network code makes month-boundary, leap-year, and budget-change behaviour directly testable.

### Fetching

`Fetcher.fetchAll` adds OpenRouter alongside Claude and Codex. Credential discovery is isolated from response parsing and budget mapping. Fetches remain concurrent.

OpenRouter-specific HTTP messages are:

- 401 with a manual key: `key rejected — update it in Settings`
- 401 with only automatic candidates exhausted: `stored key was rejected`
- 429: `rate limited — the reading will catch up`
- 5xx: the existing service-unavailable wording
- no credential: `not connected`
- valid credential but no budget: `set a monthly budget in Settings`

### Preferences and recalculation

`Preferences` stores the optional monthly USD budget in UserDefaults, never the API key. `UsageStore` observes budget changes, recomputes any cached OpenRouter windows from their USD metadata, redraws all surfaces, and does not manufacture a notification from the preference edit. Notifications remain tied to real refreshes and clock boundaries.

### Settings connection state

The current OpenRouter credential source is non-secret, in-memory UI state. It is not required for decoding old reports. The usage surfaces rely only on ordinary `Provider` state, while Settings can distinguish Keychain, OpenCode, inherited environment, transient Conductor, rejected credentials, and no credential.

## Official OpenRouter mark

Vendor the current official glyph from:

`https://openrouter.ai/brand/v2/openrouter-glyph-light.svg`

as `Resources/Icons/openrouter.svg`. The file remains an auditable local build input after vendoring; runtime rendering does not depend on the network.

The official asset has a non-24-square view box. Extend the glyph loader to respect an SVG's `viewBox` and fit it uniformly into the requested square without stretching or rotating it. Existing 24×24 Claude and OpenAI assets retain their current geometry. Add `openrouter` to the provider-to-file map.

All three surfaces render the mark monochrome using the existing label/ink colour. Pace colour stays on the adjacent track or ring and never tints the trademark.

## Layout behaviour

`UsageRow` uses a one-line label for ordinary windows and a compact two-line label only when `spentUSD` and `budgetUSD` are present. The label column width remains unchanged, preventing either window from widening. The provider block and owning panels are already content-sized; OpenRouter adds vertical height only.

The budget badge formats whole-dollar budgets without decimals and non-whole budgets with at most two decimal places. Dollar row details use enough precision to keep small API spend visible rather than rounding `$0.004` to `$0.00`.

## Error and stale-data behaviour

OpenRouter participates in `Report.carryingOver` like every other provider. A previously successful non-zero reading remains visible, dimmed and timestamped, for at most three hours or until its day/month reset passes. A stale zero reading is hidden by the existing `hasVisibleReading` rule.

If only one carried window remains valid after a reset, only that window is shown. For example, a failed poll after the UTC day boundary may drop `day` while retaining the still-live `month` row.

OpenRouter is hidden from usage surfaces when it has never connected. Its setup controls remain available in Settings.

## Testing

Automated regression coverage includes:

- Mapping daily and monthly API values into USD metadata and budget percentages.
- Daily allowance across 28-, 29-, 30-, and 31-day UTC months.
- Exact UTC reset timestamps and window lengths at day, month, year, and leap-year boundaries.
- Zero spend, fractional-cent spend, exact-budget spend, and over-budget spend.
- Immediate recalculation from cached USD metadata after a budget change.
- Existing cache decoding with no USD fields and new cache round-tripping with them.
- Credential parsing from temporary OpenCode auth fixtures.
- Pure parsing of redacted process-environment fixtures, including multiple Conductor processes and duplicate keys.
- Manual-key authority and automatic-candidate fallback behaviour without logging secrets.
- OpenRouter filtering, stale carry-over, reset expiry, ranking, and notification compatibility.
- Parsing and proportional bounds checks for the official OpenRouter SVG alongside the existing marks.
- Dollar formatting for whole dollars, cents, and small spend.

Network tests use fixtures and pure response mapping rather than live external calls.

Final verification consists of:

1. Run the regression suite and a release build.
2. Install the real app using the project's build script.
3. Perform one live refresh with the currently available Conductor key while reporting only HTTP status and spend values.
4. Capture and inspect the dropdown Usage tab, Settings tab, desktop card, and menu bar.
5. Confirm the OpenRouter mark is upright, uniformly scaled, monochrome, and present on every surface.
6. Confirm the extra dollar line does not clip, widen, or misalign the existing glass panels.

## Documentation

Update the README to include OpenRouter in the supported providers, explain the monthly budget, document credential discovery and the manual Keychain fallback, name the `/api/v1/key` source, and state that no management key is required. The security section must explicitly describe the best-effort Conductor process discovery and its transient, memory-only handling.

## Out of scope

- OpenRouter management keys.
- Account credit balance from `/api/v1/credits`.
- Thirty-day historical or per-model analytics from `/api/v1/activity`.
- Charts or sparklines.
- Editing OpenRouter-side key limits.
- Per-model OpenRouter budgets.
- Weekly budget rows; the API value may be cached later, but the first UI intentionally stays at the approved `day` and `month` windows.

## Source references

- OpenRouter current-key API: https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key
- OpenCode provider credentials: https://opencode.ai/docs/providers
- Official OpenRouter brand refresh: https://openrouter.ai/blog/announcements/brand-refresh/
- Official current glyph: https://openrouter.ai/brand/v2/openrouter-glyph-light.svg
