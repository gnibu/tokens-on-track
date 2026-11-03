#!/bin/sh
# Capture the app's surfaces into docs/screenshots/ for the README and the
# marketing page.
#
#   .agents/skills/glass-ui-changes/capture.sh
#
# Drives the installed app, not a dev build, for the reason in SKILL.md: a
# second copy gets a status item the window server parks off-screen.
#
# Everything is captured with `screencapture -l <windowID>`, never with a region
# crop. A region crop of a 460x297 card on a busy desktop caught a browser
# window sitting in front of it — a private URL and a half-filled sign-in form —
# because the card sits *behind* every window by default. `-l` reads the
# window's own backing store, so occlusion and the desktop behind it are both
# irrelevant, and the corners come out with real alpha.
#
# Requires an unlocked screen and, just as importantly, a machine nobody else is
# using. This script drives the real cursor and the panel closes the moment it
# stops being key, so a human clicking anywhere mid-run both steals the pointer
# back and dismisses the thing being photographed. Run it while away from the
# keyboard; it takes about fifteen seconds.
set -eu

cd "$(dirname "$0")/../../.."

HERE=".agents/skills/glass-ui-changes"
OUT="${OUT:-docs/screenshots}"
CLICK="/tmp/tot-click"
WINS="/tmp/tot-wins"

fail() { echo "error: $*" >&2; exit 1; }

PID="$(pgrep -f '/Applications/Tokens on Track.app' || true)"
[ -n "$PID" ] || fail 'app is not running. Run ./build.sh --install first.'

ax() {
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to get ${1}"
}

ax 'name of menu bar 1' >/dev/null 2>&1 || fail 'cannot reach the status item.
       Either the screen is locked, or this terminal lacks Accessibility
       permission (System Settings > Privacy & Security > Accessibility).'

swiftc -O "${HERE}/click.swift" -o "$CLICK"
swiftc -O "${HERE}/windows.swift" -o "$WINS"
mkdir -p "$OUT"

# A lock part-way through yields wallpaper PNGs that look like a code bug.
caffeinate -u -t 300 &
trap 'kill %1 2>/dev/null || true' EXIT

# The dropdown's window id changes every time it opens, so everything is looked
# up fresh. Layer 101 is the panel; the card is identified by its fixed width so
# this also works when its level is set to Floating.
# Fields are: id x y w h layer onscreen.
panel_id()    { "$WINS" "$PID" | awk '$6=="layer=101" && $7=="onscreen=true" {print $1}'; }
settings_id() { "$WINS" "$PID" | awk '$4>=900 && $6=="layer=0" && $7=="onscreen=true" {print $1; exit}'; }
card_id()     { "$WINS" "$PID" | awk '$4==460 && $7=="onscreen=true" {print $1}'; }

shot() { screencapture -x -l "$1" -o -t png "$2" && echo "    $2  $(file -b "$2" | cut -d, -f2 | tr -d ' ')"; }

# --------------------------------------------------------------------- #
# 1. Menu bar item
#
# The only surface that has to be a region crop — a status item is not a window
# of this process. The crop contains nothing but the app's own pixels, so it is
# safe, but check it anyway if the menu bar is crowded.
# --------------------------------------------------------------------- #
echo "==> menu bar item"
# The status item is not always `menu bar 1`: on macOS 27 an empty 0x0 item
# sits there and the real one is in `menu bar 2`. Take the first with a size.
ITEM=""
for BAR in 1 2; do
    ITEM="$(ax "{position, size} of menu bar item 1 of menu bar ${BAR}" 2>/dev/null || true)"
    [ "$(echo "$ITEM" | cut -d, -f3 | tr -d ' ')" -gt 0 ] 2>/dev/null && break
done
IX=$(echo "$ITEM" | cut -d, -f1 | tr -d ' ')
IY=$(echo "$ITEM" | cut -d, -f2 | tr -d ' ')
IW=$(echo "$ITEM" | cut -d, -f3 | tr -d ' ')
IH=$(echo "$ITEM" | cut -d, -f4 | tr -d ' ')
screencapture -x -R"$((IX - 8)),${IY},$((IW + 16)),${IH}" -t png "${OUT}/menubar.png"
echo "    ${OUT}/menubar.png  $(file -b "${OUT}/menubar.png" | cut -d, -f2 | tr -d ' ')"

# --------------------------------------------------------------------- #
# 2. Usage dropdown and separate Settings window
#
# `screencapture -l` captures each window without including overlapping apps.
# --------------------------------------------------------------------- #
echo "==> dropdown"
[ -n "$(panel_id)" ] || "$CLICK" "$((IX + IW / 2))" "$((IY + IH / 2))"
sleep 1
PANEL="$(panel_id)"
[ -n "$PANEL" ] || fail 'the dropdown did not open. See SKILL.md step 2.'
shot "$PANEL" "${OUT}/dropdown-usage.png"

# The dropdown is key, so the app's Settings keyboard shortcut opens the
# regular window without relying on a hard-coded gear position.
osascript -e "tell application \"System Events\" to tell (first process whose unix id is ${PID}) to keystroke \",\" using command down"
sleep 1
SETTINGS="$(settings_id)"
[ -n "$SETTINGS" ] || fail 'the Settings window did not open.'
# SwiftUI sidebar buttons expose their text as accessibility labels. Walk the
# settings window's descendants rather than depending on screen coordinates.
choose_section() {
    osascript - "$PID" "$1" <<'APPLESCRIPT'
on run argv
    tell application "System Events"
        tell (first process whose unix id is (item 1 of argv as integer))
            set settingsWindow to first window whose title is "Tokens on Track Settings"
            repeat with sidebarElement in (entire contents of settingsWindow)
                try
                    if role of sidebarElement is "AXButton" and name of sidebarElement is (item 2 of argv) then
                        perform action "AXPress" of sidebarElement
                        return
                    end if
                end try
            end repeat
            error "Settings sidebar section not found: " & (item 2 of argv)
        end tell
    end tell
end run
APPLESCRIPT
    sleep 1
}
choose_section "Accounts"
shot "$SETTINGS" "${OUT}/settings-window.png"
choose_section "Alerts"
shot "$SETTINGS" "${OUT}/settings-alerts.png"
choose_section "Working hours"
shot "$SETTINGS" "${OUT}/settings-working-hours.png"
choose_section "Appearance"
shot "$SETTINGS" "${OUT}/settings-appearance.png"
choose_section "Accounts"

# --------------------------------------------------------------------- #
# 3. Desktop card
# --------------------------------------------------------------------- #
echo "==> desktop card"
CARD="$(card_id)"
if [ -n "$CARD" ]; then
    shot "$CARD" "${OUT}/desktop-card.png"
else
    echo "    not visible — enable it in Settings > Appearance > Card on desktop"
fi

# Leave the panel closed.
[ -n "$(panel_id)" ] && "$CLICK" "$((IX + IW / 2))" "$((IY + IH / 2))"

cat <<'EOF'

    Done. Two things to check before committing:

    1. Open every PNG and look at it. These are captures of a live desktop.
    2. Note the DPI. A panel on a 1x external display captures at 1x while the
       card on a Retina built-in captures at 2x. For assets that match, move the
       menu bar to the built-in display (System Settings > Displays, drag the
       white bar) and re-run.
EOF
