#!/bin/bash
# Checks the signed, notarised app from the last build, then signs,
# notarises and staples its DMG. Usage: scripts/notarize-dmg.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$PROJECT_DIR/scripts/apple-signing-env.sh"

BUNDLE_DIR="$PROJECT_DIR/app/src-tauri/target/release/bundle"
VERSION=$(node -e "console.log(require('$PROJECT_DIR/app/src-tauri/tauri.conf.json').version)")
APP="$BUNDLE_DIR/macos/FLAC Tools.app"
DMG="$BUNDLE_DIR/dmg/FLAC Tools_${VERSION}_aarch64.dmg"

if [ ! -f "$DMG" ]; then
    echo "error: no DMG for version $VERSION at $DMG" >&2
    exit 1
fi

# Runs a stapler command, retrying. Stapling and validating both fetch the
# ticket from Apple's servers: it can take a little while to appear after
# the submission is accepted, and the connection sometimes drops.
stapler() {
    for ATTEMPT in 1 2 3 4 5 6; do
        if xcrun stapler "$@"; then
            return 0
        fi
        if [ "$ATTEMPT" -eq 6 ]; then
            echo "error: 'stapler $*' failed $ATTEMPT times" >&2
            exit 1
        fi
        echo "stapler $1 failed (try $ATTEMPT), retrying in 20s..."
        sleep 20
    done
}

echo ""
echo "═══ Verifying the app ═══"
codesign --verify --deep --strict --verbose=2 "$APP"
# Tauri staples the app after notarising it, but carries on if that fails.
if ! xcrun stapler validate -q "$APP"; then
    echo "The app has no ticket stapled to it (or the check couldn't reach Apple), stapling it now."
    stapler staple "$APP"
fi
stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo ""
echo "═══ Notarising $(basename "$DMG") ═══"
codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$DMG"
SUBMISSION=$(
    xcrun notarytool submit "$DMG" --keychain-profile "$FLAC_TOOLS_NOTARY_PROFILE" \
        --wait --timeout 1h --output-format json
) || true
SUBMISSION_ID=$(node -e "console.log(JSON.parse(process.argv[1]).id)" "$SUBMISSION")
STATUS=$(node -e "console.log(JSON.parse(process.argv[1]).status)" "$SUBMISSION")
echo "Submission $SUBMISSION_ID: $STATUS"

if [ "$STATUS" != "Accepted" ]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$FLAC_TOOLS_NOTARY_PROFILE" >&2
    exit 1
fi

stapler staple "$DMG"

echo ""
echo "═══ Verifying the DMG ═══"
stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
