# Tokens on Track

**Use every token. Never run dry.**

Tokens on Track is a macOS menu bar app showing how much of your **Claude Code**,
**Codex**, and **OpenCode Go** quota you have burned, plus **OpenRouter** and
**Cursor** spend against the budgets those services expose. It shows whether you are spending
faster than the window refills, refreshes every 10 minutes by default, and tells
you when you are running hot.

<img src="docs/screenshots/menubar.png" width="163" alt="The menu bar item: a Claude mark with a green ring at 70% marked w, and a second at 53% marked h.">

### [⬇ Download for macOS](https://github.com/gnibu/tokens-on-track/releases/latest/download/TokensOnTrack.dmg)

A signed and notarized `.dmg`. macOS 14+.

---

What it reports, in the dropdown and on the desktop card:

```
TOKENS ON TRACK                   05:07
Claude                             MAX
5h          ▓▓▓─┃──────   18%     07:59
week        ▓▓▓▓┃──────   22%  Sat 21:00
Codex                              PRO
week        ▓───┃──────    3%  Mon 08:34
week (Spark)▓───┃──────    1%  Mon 08:36
OpenCode                            GO
5h          ▓▓──┃──────   14%     15:30
week        ▓───┃──────    8%  Mon 02:00
month       ▓───┃──────    4%  Wed 12:44
OpenRouter                       $20/MO
day         ▓▓──┃──────   16%     00:00
month       ▓───┃──────    1%  Wed 00:00
Cursor                             PRO
month       ▓▓──┃──────   10%     16:23
```

- **Bar** — quota consumed in that window.
- **`┃` tick** — where the bar *should* be if you spent the window evenly.
  Fill left of the tick, you are under budget; right of it, you are ahead.
- **Colour** — position against the target, not absolute usage. Green at or
  under the target, orange up to 1.5× it, red beyond that or above 90% consumed.
- **Percentage** — quota used by default, or usage compared with the even-spend
  target when *Vs target* is selected in Settings. At 100% of target, spending
  is exactly where it should be now.
- **Working hours** — optionally spread the full quota over selected weekdays
  and hours while you are inside that schedule. Outside it, the target returns
  to the ordinary wall clock.
- **Right column** — when the window resets, as a wall-clock time.

## Install

1. **[Download the latest `.dmg`](https://github.com/gnibu/tokens-on-track/releases/latest/download/TokensOnTrack.dmg)**, open it, and drag **Tokens on Track**
   to *Applications*.
2. Launch it. Approve the notification prompt, and the Keychain prompt if one appears
   (Claude's token and any key you paste in Settings live in the Keychain —
   a Codex-only setup never sees a prompt).

The download is signed with a Developer ID certificate and notarized by Apple, so
Gatekeeper does not block it on a Mac that has never seen it. macOS may still ask
you to confirm the first launch of a downloaded app; that is the ordinary prompt,
not the *"cannot be opened"* refusal. Nothing to compile, no developer tools needed.

**Requirements:** macOS 14+, and at least one supported provider already set
up. Any provider can be missing without affecting the others.

Prefer to build it yourself? See [Building from source](#building-from-source).

## What you get

**Menu bar.** The window in the most trouble, as its provider's logo, a ring
filled to its consumption and tinted by its position against the target, and
the selected percentage reading. Any of the three can be switched off, and you
can widen it to as many as four windows, which are simply the busiest ones — two Claude windows if
Claude owns the two busiest. Tick *Always keep every provider on screen* to hand
each provider a slot first instead, so a quiet Codex stays visible beside a loud
Claude at the cost of bumping a window that really is busier. The window's
initial sits in the hole of the ring (`w` week, `h` 5-hour), which is the one
place a menu bar has room to spare. Click it for the dropdown.

**Dropdown.** Two tabs on a pane of glass. *Usage* leads with one line saying
whether you are fine — "On target everywhere", or how far above the target
the worst window is — then a row per window, with a **Refresh** button beside
the tabs. *Settings* holds everything else, so opening it can no longer push the
reading off the bottom of the screen.

<img src="docs/screenshots/dropdown-usage.png" width="430" alt="The dropdown on the Usage tab: On target everywhere, with a row for each Claude and Codex window.">

**Desktop card.** The same reading, free-standing and roomier: a ring for the
worst window, the summary line, and a block per provider with a word for how
that provider on its own is doing. The whole card lights red from the inside
once a window is in trouble, so the state survives peripheral vision. Drag it
anywhere; the position is remembered by its top left corner, so it stays put
when a row appears. It sits just above the desktop icons and behind every window
by default — set *Card layer* to *Floating* to keep it in front instead.
Right-click it for refresh, hide and quit.

<img src="docs/screenshots/desktop-card.png" width="460" alt="The desktop card: a ring for the worst window beside the summary line, then a block for Claude and one for Codex.">

**Notifications.** One alert when a window passes your threshold, one when it is
above your target multiple. Each fires at most once per window; the
moment a window resets, the slate is wiped and the next crossing is announced
again.

The Settings tab groups them the way System Settings does: *Menu bar* (which
parts to draw, how many windows), *Display* (whether percentages show *Used* or
*Vs target*, desktop card on/off, its layer, open at login), *OpenCode Go*
(connection and optional API key), *OpenRouter*
(connection, optional API key, one monthly USD budget, and optional dollar
details), *Cursor* (connection, optional API key or session token, an optional
monthly budget for team Admin keys, and optional dollar details), *Working hours*
(selected days and one shared time range), *Alerts* (both thresholds, on
sliders rather than steppers), and *Refresh* (5, 15, 30 or 60 minutes).

<img src="docs/screenshots/dropdown-settings.png" width="430" alt="The Settings tab, showing the Menu bar and Display groups.">

Screenshots are captured by `.agents/skills/glass-ui-changes/capture.sh`.

### Working-hours target

The working-hours target is optional and off by default. While the current
local time is inside the selected schedule, each provider window's full 100%
quota is spread evenly over every selected working hour contained in that
window. That also redistributes the shares that a wall-clock target would have
assigned to evenings and weekends.

When the current time leaves the schedule, every window deliberately switches
back to an ordinary wall-clock target. The white target notch, target
percentage, colour, worst-window ranking and target alerts all use the active
calculation, so they may jump at the boundary. Target alerts are never
suppressed outside working hours. Windows with no scheduled overlap also use a
wall-clock target.

### Why not a WidgetKit widget

The desktop card can be dragged anywhere and shares the running app's state
and refresh schedule. A WidgetKit extension would need a separate data-sharing
and refresh design. Sandboxing itself does not prevent this app from working:
the Store edition uses explicit folder grants and Keychain access.

## How it works

The app fetches on its own timer, on wake, and on demand. The direct-download
edition caches readings in `~/.local/share/ai-usage/usage.json` (override the
directory with `AI_USAGE_DIR`); the Store edition uses its sandbox's Application
Support directory. Everything on screen shares the same reading, so the menu
bar ring, the dropdown and the desktop card can never disagree.

| Source file | Job |
| --- | --- |
| `Fetcher.swift` | discovers credentials and calls the usage APIs |
| `OpenCodeGo.swift` | maps OpenCode Go's reported quota percentages into windows |
| `OpenRouter.swift` | derives daily and monthly budget windows from spend |
| `Cursor.swift` | maps Cursor's billing cycle and team spend into the same windows |
| `Report.swift` | the JSON written to the cache |
| `WorkSchedule.swift` | local working intervals, DST and schedule boundaries |
| `Pace.swift` | target share, active time basis, pace rate, colours, reset labels |
| `UsageCard.swift` | the reading, shared by the dropdown and the desktop card |
| `Glass.swift` | the glass surfaces, tracks, ring and controls both are built from |
| `StatusIcon.swift` | the menu bar item — logo, ring, percentage |
| `BrandGlyph.swift` | reads `Resources/Icons/*.svg` into drawable outlines |
| `Notifier.swift` | threshold and target alerts, one per window instance |
| `UsageStore.swift` | the single reading, its timer, and the cache |

### Where the numbers come from

| Provider | Credential | Endpoint |
| --- | --- | --- |
| Claude | One Keychain item per Claude Code profile (`Claude Code-credentials` for `~/.claude`, or `Claude Code-credentials-<hash>` for other `CLAUDE_CONFIG_DIR` paths; Claude Code 2.1.56+) | `GET api.anthropic.com/api/oauth/usage` |
| Codex | One `auth.json` per Codex profile (`~/.codex`, or another `CODEX_HOME` folder) | `GET chatgpt.com/backend-api/codex/usage` |
| OpenCode Go | app Keychain item, active OpenCode account, `OPENCODE_GO_API_KEY` / `OPENCODE_API_KEY`, or a running Conductor OpenCode process | `GET opencode.ai/zen/go/v1/usage` |
| OpenRouter | app Keychain item, OpenCode auth, `OPENROUTER_API_KEY`, or a running Conductor OpenCode process | `GET openrouter.ai/api/v1/key` |
| Cursor | signed-in Cursor app session, app Keychain item, `CURSOR_API_KEY` / `CURSOR_SESSION_TOKEN`, or a running Conductor Cursor process | `GET cursor.com/api/usage-summary` or `POST api.cursor.com/teams/spend` |

The Claude and Codex endpoints are the same first-party endpoints the CLIs
themselves call, and both are **undocumented internal APIs**. They can change
shape or start rejecting non-CLI callers without notice. OpenRouter uses its
documented key endpoint. Cursor's personal usage comes from the same dashboard
summary the website draws; a team Admin API key (`crsr_…` with `admin:*`) uses
the documented Admin spend endpoint instead. A personal user/agent API key
cannot read usage.

Which windows appear depends on what each API returns for your plan:

- Claude reports `five_hour` and `seven_day`.
- Codex reports a primary window, an optional secondary one, and any
  named model-specific buckets from `additional_rate_limits` (for example,
  `GPT-5.3-Codex-Spark`) as their own compact rows, such as `week (Spark)`.
  Newly discovered models are shown by default and get one switch in Settings;
  the app remembers that switch even when a later response omits the model.
  On Pro today only weekly windows come back —
  `secondary_window` is `null`. If a 5-hour window reappears it is rendered with
  no change.
- OpenCode Go reports its 5-hour, weekly, and monthly quota percentages and
  reset times directly. Tokens on Track reads the active `opencode-go` account
  from OpenCode's current `account.json`, with its legacy `auth.json` entry as a
  fallback. No local budget is required.
- OpenRouter reports dollar spend. Enter one monthly budget in Settings; the
  app divides it by the number of UTC days in the current month for the daily
  row, while the monthly row uses the full amount. A disabled-by-default setting
  can show the spend and allowance beneath each percentage, keeping cents — and
  sub-cent spend — visible rather than rounding them away. Until a budget
  is defined, the app shows one setup notice instead of an empty provider block.
- Cursor reports the current billing cycle from the signed-in Cursor app on
  this Mac. Optional Auto, API and on-demand rows appear when those counters
  are in use; each can be hidden from Settings like other model-specific
  limits. A team Admin key instead reports cycle spend against the key's spend
  limit, or against a monthly budget entered in Settings. A user/agent API key
  cannot read usage on its own; the app then uses the signed-in Cursor session
  if one is available.

## Security

Worth understanding before running something that touches your API credentials.

- For a second Claude subscription, create another Claude Code profile with
  `CLAUDE_CONFIG_DIR` pointing at a separate folder, sign into it once, then add
  that folder under **Claude accounts** in Settings. Profile paths are stored
  locally; OAuth tokens stay in Claude Code's Keychain items. The direct-download
  build may also notice a running Claude Code process and remember its profile
  after a valid credential is seen.
- For a second Codex subscription, launch Codex with a separate home, for
  example `CODEX_HOME=~/.codex-work codex`, and sign in there once. Add that
  folder under **Codex accounts** in Settings. The direct-download build can
  also notice a running Codex process with `CODEX_HOME` set; the App Store build
  only reads folders you explicitly choose. Tokens remain in each profile's
  `auth.json`.
- Reads the Claude OAuth token via `/usr/bin/security`, the Codex token from
  each selected profile's `auth.json`, an OpenCode Go key from OpenCode's active
  account, a Cursor session from the Cursor app's Keychain item
  `cursor-access-token` or `state.vscdb`, and an OpenRouter or Cursor key from
  the first available configured source. A key entered in Settings is stored in
  the app's own Keychain item.
- Conductor's OpenCode Go, OpenRouter, or Cursor key is available only inside its managed
  process. While that process is running, the app can read its same-user process
  environment as a best-effort fallback; it never copies that key into storage.
- Sends each token *only* to its own provider's host. No third party, no
  telemetry, no analytics.
- Never prints or logs a token. The cache holds usage values, OpenRouter and
  Cursor spend totals and budgets, reset timestamps and plan names — nothing secret.
- Read-only on provider-owned credential stores. It never writes or refreshes
  their tokens. Only a key explicitly entered in Settings is written, and only
  to the app's own Keychain item.
- No dependencies beyond the system frameworks. The app's own supply chain is
  this repo and nothing else. Read it; it is short.
- **Downloading is a wider trust decision than building.** Take the `.dmg` and you
  are also trusting the release build and the machine that signed it, which you
  cannot audit from here. `release.py` itself pulls `rich` and `pydantic` at
  version ranges. Build from source with `build.sh` if you would rather trust only
  the code you can read — it needs no network and no third-party package.

**Signing.** The published `.dmg` is signed with a Developer ID Application
certificate and notarized by Apple; its signature is stable across launches.
A build you make yourself with `build.sh` is signed with an ad-hoc identity
instead — enough for notifications and the login item, but the signature changes
on every rebuild, so macOS may re-ask for Keychain consent after one. That is
expected for local builds and does not happen with the released app.

## Troubleshooting

**Menu bar shows a letter instead of a logo**

`BrandGlyph` falls back to the provider's initial when it cannot read
`Resources/Icons`. That happens when the app is run straight out of `swift
build` rather than from the bundle `build.sh` assembles. Point it at the working
copy with `AI_USAGE_ICONS=$PWD/Resources/Icons`, or just use `./build.sh`.

**Menu bar item missing**

macOS hides status items when the bar runs out of room, and menu bar managers
(Bartender, Ice, Hidden Bar) park them off-screen by default. Check the app is
alive with `pgrep -fl "Tokens on Track"`, then look in your manager's hidden section.

**Desktop card missing**

By default it sits behind every window, so a maximised window hides it. Show the
desktop, or set *Card layer* to *Floating*. If it was dragged to a screen
that is no longer attached, it comes back to the top right on the next launch.

**No notifications**

The app asks for permission on first launch. If it was refused, re-enable it
under System Settings → Notifications → Tokens on Track. Notifications need the app to
be signed, which `build.sh` handles — running the raw `swift build` binary skips
them on purpose.

**`stored token went stale — run claude once` / `run codex once`**

You are still signed in. Each CLI keeps a refresh token and mints a new access
token when it next runs, so the copy this app reads out of their store lapses on
its own — overnight, typically. Start the relevant CLI once and the next fetch
recovers. By design this app never refreshes tokens itself — it will not touch
your logins.

Until it recovers, the rows carry the last reading that did land, dimmed, with
the notice saying when it was taken. They are dropped once they are three hours
old or their window has reset, whichever comes first.

**`http 403` from Codex**

The edge in front of `chatgpt.com` intermittently rejects a valid request. The
fetch already retries once; a later run generally succeeds.

**Reading is stale**

The header marks a reading `(stale)` once the cache is more than 45 minutes old.
Hit **Refresh**; if that fails the per-provider error says why.

## Building from source

```sh
git clone https://github.com/gnibu/tokens-on-track.git
cd tokens-on-track
./build.sh --install
```

That compiles, wraps the binary in `Tokens on Track.app`, ad-hoc signs it, copies
it to `/Applications` and launches it. Drop `--install` to build into `.build/`
and leave `/Applications` alone. The footer identifies source builds using
Git's standard descriptive form, such as `v1.1.2-3-gabc1234-dirty`; a published
build shows only its exact release version.

**Requirements:** macOS 14+ and Command Line Tools (`xcode-select --install`).
Full Xcode is *not* needed for this direct-download build; `build.sh` assembles
the bundle by hand.

For the sandboxed App Store edition, open `TokensOnTrack.xcodeproj` in full
Xcode. It uses the same Swift sources with dedicated Store settings and
provider folder permissions. See [App Store build instructions](docs/app-store-build.md)
and the [release checklist](docs/app-store-release.md).

Publishing a signed, notarized `.dmg` is a different loop — see
[docs/releasing.md](docs/releasing.md).

## Uninstall

```sh
osascript -e 'quit app "Tokens on Track"'
rm -rf "/Applications/Tokens on Track.app"
rm -rf ~/.local/share/ai-usage
defaults delete io.github.ai-usage
```

## License

Copyright © 2026 Benoit Pothier. Released under the MIT License — see
[`LICENSE`](LICENSE).

`Resources/Icons` holds the Claude and OpenAI marks, taken verbatim from
[simple-icons](https://github.com/simple-icons/simple-icons), whose packaging is
CC0, plus provider marks from their official sites. The marks themselves remain
trademarks of their respective owners, and are
used here only to identify whose quota a row is reporting. They are drawn
monochrome and scaled uniformly, never recoloured, stretched or rotated. Neither
the providers nor their owners endorse or are affiliated with this project.
