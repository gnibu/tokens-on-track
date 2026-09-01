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

# release.py's shebang is `uv run --script`, so without uv it exits 127 with
# no diagnostic at all. Checked here rather than there, because there is no
# way for a script to report the absence of its own interpreter.
command -v uv >/dev/null 2>&1 \
    || fail 'uv not found. release.py runs under it, and without it the script
       exits 127 with no message. Install with either:
         brew install uv
         curl -LsSf https://astral.sh/uv/install.sh | sh'

echo "    uv ok"

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
else
    # A configured value gets the same scrutiny as a detected one. Otherwise a
    # .env left over from another machine reaches "setup complete" here and is
    # only rejected later by release.py, after the backup and notary phases
    # have already reported success against a certificate that is not present.
    printf '%s\n' "$FOUND" | grep -qxF "$DEVELOPER_ID" || fail "DEVELOPER_ID is set to
         ${DEVELOPER_ID}
       but no such certificate is installed. Present:
$(printf '%s\n' "$FOUND" | sed 's/^/         /')
       Fix .env, or unset DEVELOPER_ID to auto-detect."

    case "$DEVELOPER_ID" in
        "Developer ID Application:"*) ;;
        *) fail 'DEVELOPER_ID must be a "Developer ID Application: ..." identity.
       An Apple Development or 3rd Party Mac Developer certificate will sign
       fine and then fail notarization.' ;;
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

# Every openssl call below runs twice, plain and with -legacy. Keychain
# Access still writes RC2-40, which OpenSSL 3 refuses without -legacy, while
# LibreSSL reads it natively and rejects the flag — so on either openssl one
# of the two forms answers and the other harmlessly errors out. Relying on a
# single form would read "cannot parse" as a verdict about the file.
#
# The password reaches openssl through the environment, not the command line,
# where it would be visible to anyone running ps.
p12() {
    form="$1"; shift
    openssl pkcs12 "$@" -in "$BACKUP" -passin "env:P12PASS" 2>/dev/null && return 0
    [ "$form" = "legacy" ] && openssl pkcs12 -legacy "$@" -in "$BACKUP" -passin "env:P12PASS" 2>/dev/null
}

opens_with_current_password() {
    P12PASS="$P12PASS" p12 legacy -nokeys -out /dev/null >/dev/null
}

# -nocerts -nodes is the only way to reach the private key, so unlike the
# earlier probes this does handle key material. It stays in a pipeline and is
# reduced to a public key immediately; nothing is written to disk.
backed_up_public_key() {
    P12PASS="$P12PASS" p12 legacy -nocerts -nodes | openssl pkey -pubout 2>/dev/null
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

    Export the certificate itself, not the key underneath it. Expanding the
    row and exporting the key alone produces a file that looks right and
    cannot sign anything.

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

# --------------------------------------------------------------------- #
# Prove the backup is what it claims to be
#
# "It parses" is not the same as "it restores". A certificate-only export, an
# export of the wrong identity, and a truncated file all open cleanly and all
# leave the private key backed up nowhere — and the failure only surfaces on
# the day the original keychain is gone, which is the one day it cannot be
# fixed. So the check goes all the way: decrypt the archive, take the public
# half of the private key inside it, and require it to match the certificate
# this setup is configured to sign with.
# --------------------------------------------------------------------- #
echo "    ${BACKUP}"

P12PASS=""
if opens_with_current_password; then
    fail "that .p12 has an EMPTY password. Anyone holding the file can sign
       software as you. Delete it and export again, filling in the password
       field this time:
         rm \"${BACKUP}\""
fi

printf '    Password for the .p12 (to verify it, not stored): '
stty -echo 2>/dev/null || true
read -r P12PASS || true
stty echo 2>/dev/null || true
echo

[ -n "$P12PASS" ] || fail "no password given, so the backup could not be verified.
       Re-run to check it. An unverified .p12 is worth what an empty directory
       is worth on the day you need it."

opens_with_current_password || fail "that password does not open the .p12.
       Either the password is wrong or the file is damaged. Both mean you do
       not have a backup yet."

# `|| true` because an archive with no private key makes this fail, and set -e
# would turn the most important diagnostic here into a silent exit.
KEY_PUB="$(backed_up_public_key || true)"
[ -n "$KEY_PUB" ] || fail "that .p12 opens but contains no private key.
       A certificate-only export restores nothing — the certificate is
       re-downloadable from Apple anyway; the key is the part that is not.
       In Keychain Access export the certificate row itself, not the key
       nested under it."

# The certificate's own copy of the public key, straight from the keychain.
# -a because a renewal leaves two certificates under one common name, and the
# backup legitimately matches either.
CERT_PEMS="$(mktemp -d)"
security find-certificate -c "$DEVELOPER_ID" -a -p > "${CERT_PEMS}/all.pem" 2>/dev/null || true
awk -v d="$CERT_PEMS" '/BEGIN CERTIFICATE/ { n++ } n { print > (d "/cert" n ".pem") }' \
    "${CERT_PEMS}/all.pem" 2>/dev/null || true

MATCHED=no
for pem in "${CERT_PEMS}"/cert*.pem; do
    [ -f "$pem" ] || continue
    if [ "$(openssl x509 -in "$pem" -pubkey -noout 2>/dev/null)" = "$KEY_PUB" ]; then
        MATCHED=yes
        break
    fi
done
rm -rf "$CERT_PEMS"
P12PASS=""

[ "$MATCHED" = yes ] || fail "the key in that .p12 is not the key for
         ${DEVELOPER_ID}
       It is a real private key, but a different one — most likely an export
       of another identity. Export again from the right row."

echo "    password-protected, holds the private key for this certificate"

cat <<'INSTRUCTIONS'

    Move the file and its password into your password manager or encrypted
    backup, then delete the copy on disk. That file is also how you move
    signing to a second Mac or to CI later - double-click to import.

    Never commit it, and never leave it in a plaintext-synced folder.

INSTRUCTIONS

echo "    setup complete. Release with:"
echo "        ./release.py"
