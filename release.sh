#!/bin/sh
# Build a signed, notarized, universal Tokens on Track.dmg for direct
# distribution outside the Mac App Store.
#
# build.sh is the development loop: host architecture, ad-hoc signature, no
# network. This is the shipping loop, and it is slower for good reasons — it
# compiles twice, waits on Apple's notary service, and produces something a
# stranger's Mac will open without a Gatekeeper warning.
#
# Command Line Tools are enough. There is no Xcode project and none is needed:
# the two-triple build below is what `--arch` would have routed through xcbuild
# for, and notarytool ships with the CLT.
#
# One-time setup lives in ./setup-signing.sh — run that once and this script
# needs no arguments and no environment ever again.
#
#   ./setup-signing.sh      certificate + notary credentials + key backup
#   ./release.sh            build dist/Tokens on Track-<version>.dmg
#
# Configuration is resolved in this order, first hit wins:
#
#   1. the environment
#   2. ./.env, if present (gitignored; see .env.example)
#   3. auto-detection — the single "Developer ID Application" certificate in
#      the keychain, and the default notary profile name
#
# So the normal case is zero configuration. .env exists for the machine that
# has two certificates, or a notary profile under a different name. No secret
# belongs in it: the app-specific password lives in the keychain, put there
# once by setup-signing.sh, and neither script ever reads it back.
#
# Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist
# before each release; both are read from there rather than passed in, so the
# plist stays the single source of truth.
set -eu

cd "$(dirname "$0")"

APP_NAME="Tokens on Track"
DIST_DIR="dist"
BUNDLE="${DIST_DIR}/${APP_NAME}.app"

# Sourced before the defaults below are applied, so .env can set either
# variable, and an explicit environment variable still beats the file.
[ -f .env ] && . ./.env

NOTARY_PROFILE="${NOTARY_PROFILE:-tokens-on-track-notary}"

# Must match Package.swift's platforms declaration.
DEPLOYMENT_TARGET="14.0"
TRIPLES="arm64-apple-macosx${DEPLOYMENT_TARGET} x86_64-apple-macosx${DEPLOYMENT_TARGET}"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "error: $*" >&2; exit 1; }

# --------------------------------------------------------------------- #
# Preflight
#
# Every check here maps to a failure that would otherwise surface minutes
# later, after a full two-architecture compile or a round trip to Apple.
# --------------------------------------------------------------------- #
echo "==> preflight"

# Auto-detect the identity so the common case needs no configuration at all:
# one Developer ID Application certificate in the keychain is the whole
# answer. Two is genuinely ambiguous — an expiring certificate sitting next to
# its replacement would otherwise sign a public release with whichever one
# sorted first — so that case refuses to guess.
if [ -z "${DEVELOPER_ID:-}" ]; then
    FOUND="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p')"
    # `|| true` because grep exits 1 on a zero count, which set -e would take
    # as a script failure rather than the answer it is.
    case "$(printf '%s' "$FOUND" | grep -c . || true)" in
        0) fail 'no "Developer ID Application" certificate in the keychain.
       Run: ./setup-signing.sh' ;;
        1) DEVELOPER_ID="$FOUND" ;;
        *) fail "more than one \"Developer ID Application\" certificate:
$(printf '%s\n' "$FOUND" | sed 's/^/         /')
       Choose one in .env — see .env.example." ;;
    esac
fi

security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID" \
    || fail "no codesigning identity matching \"${DEVELOPER_ID}\" in the keychain.
       Run: security find-identity -v -p codesigning"

case "$DEVELOPER_ID" in
    "Developer ID Application:"*) ;;
    *) fail 'DEVELOPER_ID must be a "Developer ID Application: ..." identity.
       An Apple Development or 3rd Party Mac Developer certificate will sign
       fine and then fail notarization.' ;;
esac

xcrun --find notarytool >/dev/null 2>&1 || fail 'notarytool not found. Install the Command Line Tools.'

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notary profile \"${NOTARY_PROFILE}\" is missing or invalid.
       Run: ./setup-signing.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
DMG="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "    ${APP_NAME} ${VERSION} (${BUILD_NUMBER})"
echo "    signing as ${DEVELOPER_ID}"

WORK="$(mktemp -d)"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# --------------------------------------------------------------------- #
# Compile both architectures and fuse them
#
# swift build cannot emit a universal binary directly without xcbuild, so it
# runs once per triple and lipo stitches the results. --show-bin-path is asked
# per triple because each one lands in its own .build subdirectory.
# --------------------------------------------------------------------- #
echo "==> compiling universal binary"

set --
for triple in $TRIPLES; do
    echo "    ${triple}"
    swift build -c release --triple "$triple"
    set -- "$@" "$(swift build -c release --triple "$triple" --show-bin-path)/AIUsage"
done

lipo -create -output "${WORK}/AIUsage" "$@"
lipo -info "${WORK}/AIUsage"

# --------------------------------------------------------------------- #
# Assemble the bundle
# --------------------------------------------------------------------- #
echo "==> assembling ${BUNDLE}"

mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "${WORK}/AIUsage" "$BUNDLE/Contents/MacOS/AIUsage"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp -R Resources/Icons "$BUNDLE/Contents/Resources/Icons"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# --------------------------------------------------------------------- #
# Sign
#
# --options runtime opts into the hardened runtime, which notarization
# requires. No entitlements file is needed: the app reads the Claude keychain
# item by spawning /usr/bin/security, and the hardened runtime only restricts
# what loads *into* this process, not what it exec's. ~/.codex/auth.json is a
# plain read from an unsandboxed process. Adding entitlements here would be
# cargo cult.
#
# --timestamp is mandatory, which is why build.sh's --timestamp=none cannot be
# reused: a signature without a trusted timestamp is rejected by the notary.
# --------------------------------------------------------------------- #
echo "==> signing app"

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE"

# --------------------------------------------------------------------- #
# Notarize the app
#
# Two submissions happen in this script: the app, then the finished disk image.
# Stapling both means the app still validates offline if a user drags it out of
# the .dmg, and the .dmg itself opens cleanly on a machine that has never seen
# it. One submission would leave one of those two paths depending on a live
# lookup against Apple.
# --------------------------------------------------------------------- #
notarize() {
    target="$1"
    label="$2"
    result="${WORK}/notary-${label}.json"

    echo "==> notarizing ${label} (this waits on Apple, typically 1-5 min)"

    # --wait can still exit 0 on a rejected submission, so the status is read
    # back explicitly rather than trusted to the exit code.
    xcrun notarytool submit "$target" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$result"

    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    submission="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo '')"

    if [ "$status" != "Accepted" ]; then
        echo "    status: ${status}" >&2
        [ -n "$submission" ] && xcrun notarytool log "$submission" \
            --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fail "notarization of ${label} failed"
    fi
    echo "    accepted (${submission})"
}

ditto -c -k --keepParent "$BUNDLE" "${WORK}/app.zip"
notarize "${WORK}/app.zip" "app"

echo "==> stapling app"
xcrun stapler staple "$BUNDLE"

# --------------------------------------------------------------------- #
# Disk image
#
# The /Applications symlink is what makes the window a drag-to-install target
# rather than something the user has to think about.
# --------------------------------------------------------------------- #
echo "==> building ${DMG}"

DMG_ROOT="${WORK}/dmg"
mkdir -p "$DMG_ROOT"
cp -R "$BUNDLE" "$DMG_ROOT/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov \
    "$DMG"

echo "==> signing dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

notarize "$DMG" "dmg"

echo "==> stapling dmg"
xcrun stapler staple "$DMG"

# --------------------------------------------------------------------- #
# Verify the way Gatekeeper will
#
# codesign --verify only proves the signature is intact. spctl is what actually
# answers "will this open on a Mac that has never seen it", so it runs last and
# against the stapled artifacts.
# --------------------------------------------------------------------- #
echo "==> verifying"

spctl --assess --type exec --verbose=4 "$BUNDLE"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
xcrun stapler validate "$BUNDLE"
xcrun stapler validate "$DMG"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo
echo "    ${DMG} (${SIZE})"
echo "    ready to upload."
