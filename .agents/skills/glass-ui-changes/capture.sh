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
panel_origin(){ "$WINS" "$PID" | awk '$6=="layer=101" && $7=="onscreen=true" {print $2, $3}'; }
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
# 2. Dropdown, both tabs
#
# `screencapture -l` does not steal focus, so the panel survives being
# photographed and the Settings tab can be clicked without reopening it.
# --------------------------------------------------------------------- #
echo "==> dropdown"
[ -n "$(panel_id)" ] || "$CLICK" "$((IX + IW / 2))" "$((IY + IH / 2))"
sleep 1
PANEL="$(panel_id)"
[ -n "$PANEL" ] || fail 'the dropdown did not open. See SKILL.md step 2.'
shot "$PANEL" "${OUT}/dropdown-usage.png"

# The Settings tab centre, measured off dropdown-usage.png: (155, 30) from the
# panel's own top-left.
#
# That origin comes from CGWindow, not AX. `window 1` is not dependable here —
# with the panel open, AX has been seen returning both windows on one call and
# only the desktop card on the next, at which point (155, 30) is measured from
# the card on another display and the click lands on the desktop.
set -- $(panel_origin)
FX="$1"; FY="$2"
"$CLICK" "$((FX + 155))" "$((FY + 30))"
sleep 1
PANEL="$(panel_id)"
[ -n "$PANEL" ] || fail 'the Settings tab click closed the dropdown.
       Re-measure the tab centre against docs/screenshots/dropdown-usage.png.'
shot "$PANEL" "${OUT}/dropdown-settings.png"
# Settings is a taller pane than Usage. Same height means the tab was
# missed and this is the Usage tab wearing the wrong filename.
H=$(sips -g pixelHeight "${OUT}/dropdown-settings.png" | awk '/pixelHeight/{print $2}')
UH=$(sips -g pixelHeight "${OUT}/dropdown-usage.png" | awk '/pixelHeight/{print $2}')
[ "$H" != "$UH" ] || fail "Settings tab click missed — captured the Usage tab again.
       Re-measure the tab centre against ${OUT}/dropdown-usage.png."

# TODO: the Working hours group sits below the fold and needs a scroll before it
# can be captured. Not automated yet.

# --------------------------------------------------------------------- #
# 3. Desktop card
# --------------------------------------------------------------------- #
echo "==> desktop card"
CARD="$(card_id)"
if [ -n "$CARD" ]; then
    shot "$CARD" "${OUT}/desktop-card.png"
else
    echo "    not visible — enable it in Settings > Display > Card on desktop"
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
