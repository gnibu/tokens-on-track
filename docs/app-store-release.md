# Mac App Store release checklist

Working checklist for the first paid release of **Tokens on Track**. Updated
2026-09-19. Check off tasks only after completing and verifying them.

**Release plan:** €4.99 paid upfront, source code remains public. Make the App
Store the main download after approval; preserve existing GitHub releases.
Transition future official binaries to the Store when that version is ready.

**Current position:** production Store configuration and folder-access support
are implemented. A universal archive and distribution-signed App Store package
export passed locally. TestFlight, fresh-Mac testing, public listing materials,
and submission are still outstanding. See [build instructions](app-store-build.md).

Owners: **Ben** handles account details, agreements, business decisions, and
publication. **Code** covers repository changes and local verification we can
work through together. **Together** covers testing and review.

## 0. Completed feasibility work

- [x] Build and sign an isolated App Sandbox prototype without changing the installed app.
- [x] Confirm sandbox enforcement: unrelated files and process enumeration are blocked.
- [x] Fetch live Claude usage using the existing Claude Code Keychain credential.
- [x] Fetch live Codex and Cursor usage after granting read-only folder access.
- [x] Restore the Codex/Cursor grants from security-scoped bookmarks after relaunch.
- [x] Fetch live OpenRouter usage from an existing saved Keychain key.
- [x] Check cache writes, a disposable Keychain item's add/read/delete cycle, and normal UI startup.

These checks ran on one Mac with Developer ID signing. They do not establish
fresh-install behavior or App Store approval. OpenRouter succeeded using a saved
key, not by reading a running OpenCode process. Claude's existing Keychain access
worked on this machine; fresh-machine consent still needs testing.

Local evidence and throwaway source are in `.context/sandbox-spike/REPORT.md`
(gitignored and unavailable in a fresh clone). The prototype is not a daily-use
build. Production now implements the validated approach separately; current
verification and remaining limits are in [build instructions](app-store-build.md).

## 1. Set up the tools and seller account — Ben

Start here. Account setup and the code work in step 3 can progress in parallel.

- [x] Finish Xcode installation and first-launch setup. Verified Xcode 27.0 at `/Applications/Xcode.app`, selected by `xcode-select`; `xcodebuild -checkFirstLaunchStatus` exits successfully and the GUI remains running. The initial launch failure was resolved after license acceptance and first-launch setup.
- [x] In Xcode Settings → Accounts, sign in with the Apple Account associated with the intended developer team. Confirm the correct team is available. Completed by Ben.
- [ ] Sign in to [App Store Connect](https://appstoreconnect.apple.com/) and confirm the intended seller/team and active Developer Program membership.
- [ ] In Business, review and accept the current agreements, including the Paid Apps Agreement.
- [ ] Complete and submit the required tax information directly in App Store Connect.
- [x] Submit banking information in App Store Connect. Ben reported on 2026-09-19 that Apple is processing the update and expects changes within 24 hours; further banking edits are temporarily unavailable.
- [ ] After processing, verify banking information is accepted and the Paid Apps Agreement is active. App preparation and local build work can continue while waiting.
- [ ] Apply for the [Small Business Program](https://developer.apple.com/app-store/small-business-program/) if eligible; verify acceptance rather than assuming the reduced commission applies.
- [ ] If distributing in the EU, complete the applicable trader-status declaration and verification in Business → Compliance. Follow [Apple's trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

Apple documents [agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/)
and [payment setup](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments/).
Enter passwords, bank details, and tax information in Apple's interfaces; the
repository checklist only needs their completion status.

## 2. Register the app — Together

- [x] Use the existing `io.github.ai-usage` bundle ID for the Store replacement. The two editions should not be run side by side; cache and credential-access migration limits are documented in the build instructions.
- [x] Verify the App ID is available under Tenjin Tech (`3F5CFS4B2T`). Xcode successfully obtained a Mac Team Store Provisioning Profile for this explicit ID during export.
- [ ] In App Store Connect → Apps → + → New App, select macOS and enter the available app name, primary language, registered bundle ID, and an internal SKU such as `tokens-on-track-macos`.
- [ ] Record the confirmed bundle ID, app record link, and developer Team ID in the build documentation. These identifiers are public-safe; no private credentials belong there.

An app record must exist before uploading a build. See
[Apple's app-record instructions](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

## 3. Build the production Store version — Code

- [x] Add an Xcode app target/shared scheme and a dedicated Store configuration using the existing Swift sources, resources, and versioning. Direct-download build also passes.
- [x] Configure automatic signing and provisioning for Tenjin Tech and `io.github.ai-usage`. Universal archive and distribution-signed package export succeeded using the Xcode account.
- [x] Add the project, entitlements, reproducible build instructions, and ignore rules for private signing files and local Xcode state. Changes are prepared in the working tree; not committed yet.
- [x] Enable App Sandbox, outgoing network, read-only user-selected folders, and app-scoped bookmarks; verify the exported entitlements.
- [x] Implement Codex/Cursor folder selection and bookmarks, including cancellation, invalid selection, stale/removed grants, and credential replacement. Unit tests and sandboxed grant/relaunch checks pass; interactive chooser testing remains below.
- [x] Keep provider-owned credentials read-only and retain the existing app-owned Keychain storage for manually entered OpenRouter/Cursor keys. A disposable Keychain add/read/delete test passes; real Settings key entry/removal still needs TestFlight testing.
- [x] Exclude process/environment discovery from Store builds and explain supported connections in Settings.
- [x] Verify Store cache writes inside the container and document migration: no old cache copy, new folder grants required, preference/Keychain continuity needs a clean-upgrade test.
- [x] Bundle an accessible privacy policy and support link; add the UserDefaults required-reason privacy manifest. Public policy hosting remains a release task.
- [x] Verify packaged icon, developer-tools category, copyright, macOS 14 minimum, arm64/x86_64 slices, and version 1.1.3 (32). App Store Connect upload validation remains outstanding.

No subscription or in-app purchase implementation is planned: the initial
business model is a paid app download.

## 4. Test the distribution build — Together

- [x] Pass both direct and Store regression suites, create a universal archive, export a distribution-signed package, and verify app/package signatures locally.
- [ ] Upload through Xcode Organizer using App Store Connect distribution; resolve processing or validation errors. See [Apple's upload instructions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
- [ ] Install the processed build through TestFlight and test on another Mac or a clean account without the prototype's permissions.
- [ ] Verify live reads from all four providers, including first-time Claude Keychain consent and a newly entered OpenRouter key.
- [ ] Exercise the actual folder chooser and cancellation; test permissions and credential replacement on a fresh account. Saved-bookmark relaunch with live providers and unit tests for removal/revocation/replacement already pass locally.
- [ ] Verify menu bar, desktop card, notifications, user-enabled launch at login, offline behavior, stale credentials, and API errors.
- [ ] Test the advertised macOS versions and architectures; correct the declared support if necessary.
- [ ] Verify installation alongside or over the GitHub version according to the chosen bundle-ID strategy, without duplicate login items or lost settings.

## 5. Prepare the listing and review access — Together

- [ ] Set the intended €4.99 base price and review Apple's generated prices and selected territories before release.
- [ ] Draft the description, subtitle, keywords, category, and support contact. Clearly state provider-account requirements and supported connection methods.
- [ ] Capture Store screenshots with sample data and no exposed account details or secrets. Follow [Apple's screenshot requirements](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).
- [ ] Publish working support and privacy-policy URLs and include the policy link in the app.
- [ ] Complete App Privacy, age rating, content-rights, and export-compliance information based on the actual build. See [Apple's privacy instructions](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
- [ ] Check permission to use provider services/endpoints and brand assets, and retain supporting information for review. Undocumented endpoints remain a separate review and maintenance concern. See [Review Guidelines 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property).
- [ ] Prepare reviewer instructions explaining where the menu bar app appears and how to connect/test each provider. Supply suitable test access; if using a demo mode instead of an account, follow Apple's requirements and obtain prior approval where required. Do not supply personal credentials or commit test secrets.

## 6. Submit and launch — Ben, with technical support

- [ ] Select the validated build, check the complete listing, and choose manual release so launch timing stays under your control.
- [ ] Submit to App Review, answer questions, and fix any requested issues. Use [Apple's submission steps](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/).
- [ ] After approval, release the app and verify the public listing, purchase, installation, and provider connections.
- [ ] Put the Store download button first in the README, keeping source-build instructions accessible.
- [ ] Announce the distribution change, preserve previous GitHub releases, and update release automation/documentation before stopping future GitHub binary publishing.
- [ ] Keep release tags and source available; monitor support reports, provider API changes, and sales before revisiting pricing.

Suggested README wording after the Store release is live:

> Tokens on Track is open source. Purchase the Mac App Store version for
> convenient installation and automatic updates, and to support development.
> You can also build it yourself for free.
