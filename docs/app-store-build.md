# Building the Mac App Store edition

Open `TokensOnTrack.xcodeproj`, select the **Tokens on Track** scheme and your
Mac, then Run. Both Xcode configurations enable App Sandbox and compile with
`APP_STORE`. `Debug` is for development; the scheme archives using `AppStore`,
with arm64 and x86_64 slices. The existing `build.sh` / `release.py` SwiftPM
workflow continues to produce the direct-download edition.

The bundle ID is `io.github.ai-usage` and the default team is Tenjin Tech
(`3F5CFS4B2T`). Signing is automatic. Set your own team and bundle ID when
building a fork; do not export or commit private signing keys. App Store
signing uses Xcode's Apple account, not the direct-release `.env` settings.

## Archive and export

In Xcode, use **Product → Archive**, then Organizer → **Distribute App → App
Store Connect**. For a local package without uploading:

```sh
xcodebuild -project TokensOnTrack.xcodeproj \
  -scheme 'Tokens on Track' -configuration AppStore \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/store \
  -archivePath '.build/Tokens on Track.xcarchive' \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive \
  -archivePath '.build/Tokens on Track.xcarchive' \
  -exportPath .build/store-export \
  -exportOptionsPlist Config/ExportOptions.plist \
  -allowProvisioningUpdates
```

The archive uses Apple Development signing. Export applies the team's App
Store distribution signing and provisioning, and signs the installer package.
`destination=export` prevents automatic upload. There is no ad-hoc signing
fallback in this workflow. A distribution export is for the Store, not direct
installation; use the development build locally and TestFlight for beta tests.

Versions come from `versioning.py`, shared with the direct edition. To upload
another build from the same commit, pass `STORE_BUILD_NUMBER=33` (or the next
unused higher number) to the archive command. Use
`STORE_MARKETING_VERSION=1.1.4` to explicitly select a different release.
Otherwise the latest Git tag supplies the marketing version and the commit
count supplies the build number. Check both against App Store Connect before
each upload. The generated Info.plist is in Xcode's derived files, not the
source tree.

The project is checked in; no generator needs installing. After adding or
removing Swift source files, run `python3 scripts/generate-xcode-project.py`.
The generator is the source of truth for project structure; configuration
values live in `Config/*.xcconfig`.

## Provider connections

Open the menu bar dropdown → **Settings → Connections**:

- **Codex:** select `~/.codex`, containing `auth.json`.
- **Cursor:** select `~/Library/Application Support/Cursor/User/globalStorage`,
  containing `state.vscdb`.
- **Claude:** uses the existing Claude Code Keychain login. macOS may request
  consent; run Claude Code if the provider token expires.
- **OpenCode Go:** add the API key from your OpenCode account in its Settings
  section.
- **OpenRouter:** add your key in its Settings section. Cursor also supports
  a manually entered team Admin key.

In the system folder chooser, use **Command–Shift–G** to enter a path. Grants
are read-only and stored as security-scoped bookmarks. Selecting a folder
rather than an individual file supports providers replacing their credential
files when refreshing a login. Cancel keeps the previous selection. A wrong
folder or a failed bookmark save also keeps the previous grant. Use **Remove**
to forget access, or **Choose again** when permissions expire or are revoked.

The Store build does not inspect other processes, read their environments, or
automatically search OpenCode files. It never changes Claude, Codex, OpenCode, or Cursor
credentials. Only manually entered keys are written to the app's own Keychain
items. Cached readings may remain visible as stale after removing a grant.

## Local data and migration

The Store and direct editions share a bundle ID and should be treated as
replacement installations, not apps to run side by side. Keep the installed
direct app until the Store edition has passed testing.

Store cache files live in the sandbox's Application Support/Tokens on Track
directory. The old direct-download cache is not copied; the Store edition
fetches a new reading. Preferences use the app's UserDefaults domain; verify
macOS preference migration on a clean upgrade before promising retention.
Provider folder grants must be chosen in the Store build. Keychain service
names are preserved, but consent/access across distribution signatures still
needs TestFlight verification. No credential migration writes are performed.

The app bundles `Resources/Privacy.html`, linked from Settings, plus a privacy
manifest declaring local UserDefaults access (`CA92.1`). Publish a public
privacy-policy URL and complete App Store Connect's privacy questionnaire
before submission. Support links to the repository's GitHub issues.

## Verification

```sh
./test.sh
./test.sh --store
./build.sh
```

On 2026-09-19, both regression variants, the direct build, universal Store
archive, and App Store package export passed on the development Mac. Package
and app signatures were verified; the export used Cloud Managed Apple
Distribution and a Mac Team Store Provisioning Profile. Version: 1.1.3 (32).

A separate sandboxed harness compiled the production fetcher and folder-access
code. Before granting folders, Claude and OpenRouter returned live usage;
Codex and Cursor remained disconnected. After OS-granted folder selection,
all four returned live usage, including after a fresh launch using saved
bookmarks. Removing the saved grants disconnected Codex/Cursor on the next
launch, and an unrelated file remained unreadable. A disposable Keychain item
passed add/read/delete checks. Unit tests
cover denied and removed permissions, corrupt/stale bookmarks, failed
replacement, scope cleanup, and atomic credential-file replacement.

This does not replace TestFlight or fresh-Mac testing. In particular, exercise
the actual system folder chooser, cancellation, login-item registration,
notification consent, and first-time Claude Keychain consent. The local UI
automation session lacked Accessibility permission; the settings view was
rendered and visually checked in the local harness. App Store Connect upload
validation and App Review have not been performed. See the
[release checklist](app-store-release.md) for the remaining steps.
