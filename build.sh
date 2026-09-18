#!/bin/sh
# Build Tokens on Track.app from the SwiftPM target. Needs the Command Line Tools
# only — there is no Xcode project to open.
#
#   ./build.sh              build into .build/Tokens on Track.app
#   ./build.sh --install    also copy it to /Applications and launch it
set -eu

cd "$(dirname "$0")"

APP_NAME="Tokens on Track"
LEGACY_APP_NAME="AI Usage"
BUNDLE=".build/${APP_NAME}.app"
INSTALL_DIR="/Applications"
LEGACY_AGENT_DIR="${HOME}/Library/LaunchAgents"
LEGACY_WIDGET="${HOME}/Library/Application Support/Übersicht/widgets/ai-usage.jsx"

# Built for the host architecture. A universal binary needs `--arch arm64
# --arch x86_64`, which routes through xcbuild and so requires full Xcode.
echo "==> compiling"
swift build -c release
BINARY="$(swift build -c release --show-bin-path)/AIUsage"

echo "==> assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/AIUsage"
echo "==> stamping version"
xcrun python3 versioning.py Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp -R Resources/Icons "$BUNDLE/Contents/Resources/Icons"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Ad-hoc signature. Without one, macOS refuses to hand the app a notification
# token and the login item registration is rejected.
echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$BUNDLE"

if [ "${1:-}" = "--install" ]; then
    echo "==> installing to ${INSTALL_DIR}"
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
    osascript -e "quit app \"${LEGACY_APP_NAME}\"" 2>/dev/null || true

    # Retire both published launch-agent labels and the old Übersicht widget.
    # The Übersicht app and pipx package are left alone because they may still
    # be useful to the user for unrelated projects.
    echo "==> removing legacy widget"
    for label in io.github.ai-usage net.niak.ai-usage; do
        launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
        rm -f "${LEGACY_AGENT_DIR}/${label}.plist"
    done
    rm -f "$LEGACY_WIDGET"

    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    rm -rf "${INSTALL_DIR}/${LEGACY_APP_NAME}.app"
    cp -R "$BUNDLE" "${INSTALL_DIR}/"
    open "${INSTALL_DIR}/${APP_NAME}.app"
    echo
    echo "    ${INSTALL_DIR}/${APP_NAME}.app"
    echo "    running — look for the ring in the menu bar"
else
    # Absolute, because the script cd's to its own directory and the caller may
    # not have been there — a relative .build path is not one they can act on.
    echo
    echo "    $(pwd)/${BUNDLE}"
    echo "    built. Install with: $0 --install"
fi
