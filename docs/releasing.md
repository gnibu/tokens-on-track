# Releasing

For the planned paid Mac App Store version, follow the
[App Store release checklist](app-store-release.md) and
[Store build instructions](app-store-build.md). The instructions below
cover direct distribution through GitHub.

`build.sh` is the development loop — host architecture, ad-hoc signature, no
network. `release.py` is the shipping loop: a universal binary, a Developer ID
signature, notarization, and a stapled `.dmg` that opens on a stranger's Mac
without a Gatekeeper warning.

Git tags are the version source. A development build describes its exact
worktree, for example `1.1.2-3-gabc1234` for the third commit after `v1.1.2`,
or `1.1.2-3-gabc1234-dirty` when it has uncommitted edits. A clean checkout at
an exact tag displays only that release (`1.1.3`). Apple's
`CFBundleShortVersionString` remains numeric, while `CFBundleVersion` is the
monotonic commit count; the descriptive version is stored separately for the
in-app footer.

Once per machine:

```sh
./setup-signing.sh
```

It walks through issuing the Developer ID Application certificate, stores the
notary credentials in the keychain, checks your backup of the signing key is
really encrypted, and writes a `.env`. It is re-runnable and skips whatever is
already done.

Then, per release, merge the intended changes and publish from the exact current
`origin/main` commit:

```sh
./release.py                # dist/TokensOnTrack-<version>.dmg
./release.py --publish      # ...and tag v<version>, and put it on GitHub
./release.py --force        # rebuild even if dist/ is already current
./release.py --timeout 90   # allow 90 min per notarization
./release.py --self-test    # check the parsing logic, build nothing
```

Builds are skipped on make's rule: if everything in `dist/` is newer than
every file it was built from — `Sources`, `Resources`, `Package.swift`, and
`release.py` itself — the existing artifacts are reused. What that saves is
not the compile, which `swift build` already does incrementally in under a
minute, but the notary queue, which took over an hour on this team's first
submission. The mtimes are not trusted alone: `stapler validate` has to agree,
so a run that died between notarizing and stapling is correctly seen as
unfinished rather than current.

`--publish` fetches `origin/main`, requires `HEAD` to be that exact commit,
tags it as `v<version>`, pushes the tag, and creates a GitHub release with the
dmg attached and generated notes. Publishing from a pull-request branch is
deliberately rejected even when it has been pushed: the repository uses
squash merges, so a tag made before the merge would live on parallel history
and GitHub would generate misleading release notes. The other preconditions —
`gh` installed and authenticated, a clean tree, and a release tag that does not
already exist — are also checked before the build starts rather than after.

Routine patch releases require no source version edit. `TOTReleaseTrain` in
`Resources/Info.plist` is the only manual version knob and contains just
`major.minor`; change it only when starting a new major or minor train. The
release script chooses the next patch after the highest matching local or
published tag, then stamps that same exact version into the app, DMG name,
volume name, Git tag, GitHub release title, and in-app footer.

No arguments and no environment needed: the signing identity is auto-detected
from the keychain, and the notary password never leaves it. `.env` (see
[`.env.example`](../.env.example)) is only for a machine holding more than one
Developer ID certificate, or a notary profile under a different name.

No Python environment to set up: [`uv`](https://docs.astral.sh/uv/) fetches
the two dependencies from the script's inline PEP 723 metadata on first run.
`uv` itself does have to be installed — `brew install uv`, or the [official
installer](https://docs.astral.sh/uv/getting-started/installation/) — and
`setup-signing.sh` checks for it, since a missing interpreter leaves the
script no way to report its own absence.

Notarization is submitted with `--no-wait` and polled rather than handed to
`notarytool --wait`, which blocks on a blank line for however long Apple takes.
That is minutes usually, but can be an hour on a Team ID with no submission
history, and nothing distinguishes a slow queue from a wedged one. Polling
gives the wait an elapsed clock, a budget bar, and a log line each time Apple's
answer changes.

Two submissions happen per release, and neither is redundant. A ticket is
bound to the cdhash of exactly what was submitted, and stapling embeds it so
Gatekeeper can validate offline. The app is notarized and stapled first, then
copied into the dmg, so a user who drags it to `/Applications` gets a copy with
its ticket already inside; the dmg is then notarized and stapled on its own
behalf so it opens cleanly on a machine that has never seen it. The order is
forced — once the dmg is built it is read-only, so the enclosed app cannot be
stapled after the fact.

Notarization is not App Store submission. The upload is an automated malware
scan — no review, no sandbox requirement, and Apple distributes nothing. It is
also not optional for a public download: a signed but un-notarized app trips
Gatekeeper's *"cannot be opened because Apple cannot check it for malicious
software"*.
