#!/bin/sh
# One-time signing setup for Tokens on Track.
#
# release.py needs two things that live outside the repository: a Developer ID
# Application certificate in the login keychain, and a notary credential
# profile. This script gets both in place, backs up the irreplaceable half,
# and writes the .env that makes release.py argument-free afterwards.
#
#   ./setup-signing.sh
#
# Re-runnable. Every phase checks whether it is already done and skips, so
# running it again after a partial setup picks up exactly where it stopped.
#
# What is deliberately NOT automated: creating the certificate itself. That
# needs a private key generated directly into the keychain with the right
# access controls, which Keychain Access does correctly and a script does
# fragilely — an openssl-generated key imported by hand tends to work until
# codesign asks for it non-interactively and hangs on a permission prompt.
# It is a five-minute GUI task that happens once every five years. The script
# prints the steps and verifies the result.
set -eu

cd "$(dirname "$0")"

NOTARY_PROFILE="${NOTARY_PROFILE:-tokens-on-track-notary}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/Desktop}"

[ -f .env ] && . ./.env

fail() { echo "error: $*" >&2; exit 1; }

# --------------------------------------------------------------------- #
# Phase 0 — tools
# --------------------------------------------------------------------- #
echo "==> checking tools"

xcrun --find notarytool >/dev/null 2>&1 \
    || fail 'notarytool not found. Install the Command Line Tools:
       xcode-select --install'

echo "    notarytool ok"

# --------------------------------------------------------------------- #
# Phase 1 — certificate
#
# Auto-detection matches release.py: one certificate is the answer, none is a
# to-do list, more than one is a decision only the user can make.
# --------------------------------------------------------------------- #
echo "==> checking for a Developer ID Application certificate"

FOUND="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p')"
COUNT="$(printf '%s' "$FOUND" | grep -c . || true)"

if [ -z "${DEVELOPER_ID:-}" ]; then
    case "$COUNT" in
        1) DEVELOPER_ID="$FOUND" ;;
        0) DEVELOPER_ID="" ;;
        *) fail "more than one \"Developer ID Application\" certificate:
$(printf '%s\n' "$FOUND" | sed 's/^/         /')
       Set the one you want in .env, then re-run:
         DEVELOPER_ID=\"Developer ID Application: ... (TEAMID)\"" ;;
    esac
fi

if [ -z "$DEVELOPER_ID" ]; then
    cat <<'INSTRUCTIONS'

    No certificate yet. Two steps, both in a browser and Keychain Access.

    1. Create a certificate signing request
       Keychain Access -> menu "Certificate Assistant" ->
         "Request a Certificate From a Certificate Authority..."

         User Email Address : your Apple ID email
         Common Name        : your name
         CA Email Address   : leave empty
         Request is         : Saved to disk

       Save the .certSigningRequest anywhere; it is single-use scratch.
       This is the step that generates the private key into your keychain,
       which is why it cannot be skipped or done on another machine.

    2. Issue the certificate
       https://developer.apple.com/account/resources/certificates/add

         Type         : Developer ID -> "Developer ID Application"
         Profile Type : G2 Sub-CA
         Upload       : the .certSigningRequest from step 1

       Download the .cer and double-click it to install. Then delete both
       downloaded files - the .cer is re-downloadable from that page, and the
       .certSigningRequest is spent.

    Note: only the Account Holder of the developer team can issue this.

    Then run ./setup-signing.sh again.

INSTRUCTIONS
    exit 1
fi

TEAM_ID="$(printf '%s' "$DEVELOPER_ID" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
[ -n "$TEAM_ID" ] || fail "could not read a team ID out of \"${DEVELOPER_ID}\"."

echo "    ${DEVELOPER_ID}"
echo "    team ${TEAM_ID}"

# --------------------------------------------------------------------- #
# Phase 2 — notary credentials
#
# store-credentials prompts for the password itself and writes it to the
# keychain, so it never appears in this script, in .env, or in shell history.
# --------------------------------------------------------------------- #
echo "==> checking notary profile \"${NOTARY_PROFILE}\""

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "    already stored"
else
    if [ -z "${APPLE_ID:-}" ]; then
        # `|| true` so a closed stdin reports the real problem below instead
        # of tripping set -e with no explanation.
        printf '    Apple ID holding the Developer Program membership: '
        read -r APPLE_ID || true
    fi
    [ -n "${APPLE_ID:-}" ] || fail "an Apple ID is required. Set APPLE_ID in .env
       or run this script from a terminal where it can prompt."

    cat <<INSTRUCTIONS

    notarytool needs an app-specific password, not your Apple ID password.
    Two-factor authentication makes the real password unusable from a script;
    an app-specific password is the 2FA-exempt substitute, and it can be
    revoked on its own if it ever leaks.

    Generate one now:
      https://account.apple.com/account/manage
      -> Sign-In and Security -> App-Specific Passwords -> +

    Paste it at the prompt below. It goes straight into the keychain.

INSTRUCTIONS

    xcrun notarytool store-credentials "$NOTARY_PROFILE" \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
        || fail "storing notary credentials failed."

    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "credentials stored but rejected by Apple. Check the Apple ID,
       the team ID, and that the password is app-specific."
    echo "    stored and verified"
fi

# --------------------------------------------------------------------- #
# Phase 3 — .env
#
# Written before the backup gate below, so a run that stops at the backup
# still leaves the machine configured rather than half-configured.
#
# Nothing here is secret. It exists so release.py does not have to re-derive
# the identity on every run, and so a second certificate showing up later does
# not turn into an ambiguity error mid-release.
# --------------------------------------------------------------------- #
echo "==> writing .env"

if [ -f .env ]; then
    echo "    .env exists — leaving it alone"
else
    cat > .env <<ENV
# Local release configuration. Gitignored. No secrets belong here: the
# app-specific password lives in the keychain under NOTARY_PROFILE.
# Regenerate with ./setup-signing.sh
DEVELOPER_ID="${DEVELOPER_ID}"
APPLE_ID="${APPLE_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE}"
ENV
    chmod 600 .env
    echo "    .env"
fi

# --------------------------------------------------------------------- #
# Phase 4 — back up the private key
#
# Last, and blocking, because it is the only step whose omission is
# unrecoverable. The certificate is re-downloadable from developer.apple.com
# forever; the private key exists in exactly one place and cannot be
# regenerated. Losing it means revoking the certificate and burning one of the
# few Developer ID slots Apple grants.
#
# This is also the one step left to the GUI on purpose. `security export`
# cannot filter by name — it exports every identity in the login keychain,
# which means one macOS permission prompt per key and a .p12 padded out with
# unrelated Apple system identities. Keychain Access exports the single
# identity asked for, which is the artifact actually wanted.
# --------------------------------------------------------------------- #
BACKUP="${BACKUP_DIR}/tokens-on-track-signing-${TEAM_ID}.p12"

echo "==> backing up the signing key"

# Probed twice, because Keychain Access still writes RC2-40, which OpenSSL 3
# refuses without -legacy — one probe alone would call an unencrypted file
# encrypted, which is the wrong way round to be wrong. LibreSSL reads RC2
# natively and rejects -legacy, so the first probe answers there and the
# second harmlessly errors out.
#
# -nokeys parses only the certificate half, so neither probe can print key
# material whichever way it goes.
opens_without_password() {
    openssl pkcs12 -in "$1" -nokeys -passin pass: -out /dev/null 2>/dev/null \
        || openssl pkcs12 -legacy -in "$1" -nokeys -passin pass: -out /dev/null 2>/dev/null
}

if [ ! -f "$BACKUP" ]; then
    cat <<INSTRUCTIONS

    Keychain Access -> "login" keychain -> "My Certificates"
      -> right-click "${DEVELOPER_ID}"
      -> Export...
      -> save as:
           ${BACKUP}

    It asks for a password to encrypt the file. Use a strong, unique one: the
    .p12 holds the private key, and whoever has both the file and its password
    can sign software as you. The field accepts blank without complaining -
    do not leave it blank.

INSTRUCTIONS

    # Nothing depends on this succeeding, so a machine without Keychain
    # Access in the usual place just gets the instructions above.
    open -a "Keychain Access" 2>/dev/null || true

    printf '    Press return once the export is saved... '
    read -r _ || true
    echo
fi

[ -f "$BACKUP" ] || fail "no file at ${BACKUP}
       Nothing was exported, so the signing key is still backed up nowhere.
       Re-run this script once the export is saved."

if opens_without_password "$BACKUP"; then
    fail "that .p12 has an EMPTY password. Anyone holding the file can sign
       software as you. Delete it and export again, filling in the password
       field this time:
         rm \"${BACKUP}\""
fi

echo "    ${BACKUP}"
echo "    password-protected"

cat <<'INSTRUCTIONS'

    Move the file and its password into your password manager or encrypted
    backup, then delete the copy on disk. That file is also how you move
    signing to a second Mac or to CI later - double-click to import.

    Never commit it, and never leave it in a plaintext-synced folder.

INSTRUCTIONS

echo "    setup complete. Release with:"
echo "        ./release.py"
