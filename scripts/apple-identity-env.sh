# Sourced by the other scripts: finds the Developer ID certificate the app
# is signed with (team APPLE_TEAM_ID) and exports APPLE_SIGNING_IDENTITY.
export APPLE_TEAM_ID="${APPLE_TEAM_ID:-M9T382L3AL}"

if [ -z "${APPLE_SIGNING_IDENTITY:-}" ]; then
    APPLE_SIGNING_IDENTITY=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n "s/.*\"\(Developer ID Application: .* ($APPLE_TEAM_ID)\)\".*/\1/p" \
            | head -1
    )
    export APPLE_SIGNING_IDENTITY
fi

if [ -z "$APPLE_SIGNING_IDENTITY" ]; then
    echo "error: no Developer ID Application certificate for team $APPLE_TEAM_ID in the keychain" >&2
    echo "       check with: security find-identity -v -p codesigning" >&2
    return 1 2>/dev/null || exit 1
fi
