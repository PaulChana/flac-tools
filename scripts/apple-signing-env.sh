# Sourced by the other scripts: exports the signing identity and the Apple ID
# credentials Tauri and notarytool use to notarise, read from the macOS
# Keychain (store them with `just notary-password <apple-id>` and
# `xcrun notarytool store-credentials flac-tools-notary`). Set
# FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE / FLAC_TOOLS_NOTARY_PROFILE to use others.
FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE="${FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE:-flac-tools-apple-notary}"
export FLAC_TOOLS_NOTARY_PROFILE="${FLAC_TOOLS_NOTARY_PROFILE:-flac-tools-notary}"

. "$(dirname "${BASH_SOURCE[0]}")/apple-identity-env.sh" || return 1 2>/dev/null || exit 1

if [ -z "${APPLE_ID:-}" ]; then
    APPLE_ID=$(
        security find-generic-password -s "$FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE" 2>/dev/null \
            | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p'
    )
    export APPLE_ID
fi

if [ -z "${APPLE_PASSWORD:-}" ]; then
    APPLE_PASSWORD=$(
        security find-generic-password -w -s "$FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE" 2>/dev/null || true
    )
    export APPLE_PASSWORD
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_PASSWORD" ]; then
    echo "error: no Apple ID app-specific password for notarisation" >&2
    echo "       run 'just notary-password <apple-id>' once to store it in the macOS Keychain" >&2
    return 1 2>/dev/null || exit 1
fi

FLAC_TOOLS_NOTARY_PROFILE_ACCEPTED=0
for FLAC_TOOLS_NOTARY_ATTEMPT in 1 2 3; do
    if FLAC_TOOLS_NOTARY_CHECK_OUTPUT=$(xcrun notarytool history --keychain-profile "$FLAC_TOOLS_NOTARY_PROFILE" 2>&1); then
        FLAC_TOOLS_NOTARY_PROFILE_ACCEPTED=1
        break
    fi
    if [ "$FLAC_TOOLS_NOTARY_ATTEMPT" -lt 3 ]; then
        sleep 10
    fi
done

if [ "$FLAC_TOOLS_NOTARY_PROFILE_ACCEPTED" -ne 1 ]; then
    echo "$FLAC_TOOLS_NOTARY_CHECK_OUTPUT" >&2
    echo "" >&2
    echo "error: Apple did not accept the notarytool keychain profile '$FLAC_TOOLS_NOTARY_PROFILE' after 3 attempts" >&2
    echo "       if the output above is a network or server error, re-run 'just notarize-dmg'" >&2
    echo "       if it is an authentication error, re-store the profile:" >&2
    echo "       run: xcrun notarytool store-credentials $FLAC_TOOLS_NOTARY_PROFILE --apple-id <apple-id> --team-id $APPLE_TEAM_ID" >&2
    return 1 2>/dev/null || exit 1
fi
