set shell := ["bash", "-euo", "pipefail", "-c"]

app := "app"
manifest := "app/src-tauri/Cargo.toml"
bundle := "app/src-tauri/target/release/bundle/macos/FLAC Tools.app"

[private]
default:
    @just --list

# Install the npm dependencies (only when package-lock.json has changed)
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{app}}
    if [ ! -d node_modules ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
        npm ci
    fi

# Build the release app bundle: FLAC Tools.app
build: deps
    cd {{app}} && npm run tauri build
    @echo "Built: {{bundle}}"

# Run the app in development, with hot reload for the UI
dev: deps
    cd {{app}} && npm run tauri dev

# Run all the tests: Rust unit tests and the Svelte/TypeScript checks
test: test-rust check

# Build the UI into app/dist (the Rust app embeds it, so its tests need it)
ui: deps
    cd {{app}} && npm run -s build

# Run the Rust unit tests
test-rust: ui
    cargo test --manifest-path {{manifest}}

# Type-check the Svelte and TypeScript UI code
check: deps
    cd {{app}} && npm run check

# Copy the built app into /Applications
install: build
    rm -rf "/Applications/FLAC Tools.app"
    cp -R "{{bundle}}" /Applications/
    @echo "Installed /Applications/FLAC Tools.app"

# Open the built app
open:
    open "{{bundle}}"

# Delete build output (Rust target dir, UI dist and node_modules)
clean:
    cargo clean --manifest-path {{manifest}}
    rm -rf {{app}}/dist {{app}}/node_modules

# Set the version in Cargo.toml, tauri.conf.json and package.json
bump version:
    bash scripts/bump-version.sh {{version}}

# Test, then build, sign and notarise the app and its DMG, into release/dist/<version>/
deploy: deps _deploy-notes _deploy-test _deploy-bundle _deploy-summary

# The release notes for this version: written now if they're missing
_deploy-notes:
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(node -p "require('./{{app}}/package.json').version")
    NOTES="release/notes/$VERSION.md"
    if [ -f "$NOTES" ]; then
        echo "Release notes: $NOTES"
        exit 0
    fi
    if [ ! -t 0 ]; then
        echo "error: no release notes at $NOTES" >&2
        echo "       write that file, or run this from a terminal to enter them now" >&2
        exit 1
    fi
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    touch "$TMP/$VERSION.md"
    echo ""
    echo "There are no release notes for $VERSION yet."
    if [ -n "${EDITOR:-}" ]; then
        echo "Opening $EDITOR — save and quit when you are done."
        "$EDITOR" "$TMP/$VERSION.md"
    else
        echo "Type the notes (Markdown), then press Ctrl-D on a blank line to finish."
        echo ""
        cat > "$TMP/$VERSION.md"
    fi
    if ! grep -q '[^[:space:]]' "$TMP/$VERSION.md"; then
        echo "" >&2
        echo "error: no notes were entered — nothing has been changed" >&2
        exit 1
    fi
    mv "$TMP/$VERSION.md" "$NOTES"
    echo "Saved $NOTES"

# Run all the tests before packaging
_deploy-test: ui
    @echo ""
    @echo "═══ Running Rust tests ═══"
    cargo test -q --manifest-path {{manifest}}
    @echo ""
    @echo "═══ Checking the UI and translations ═══"
    cd {{app}} && npm run -s check

# Build, sign and notarise the app (Tauri), then sign, notarise and staple the DMG
_deploy-bundle:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "═══ Building, signing and notarising the app ═══"
    . scripts/apple-signing-env.sh
    echo "Signing as $APPLE_SIGNING_IDENTITY"
    (cd {{app}} && npm run tauri build)
    bash scripts/notarize-dmg.sh

# Copy the DMG and notes to release/dist/<version>/ and report
_deploy-summary:
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(node -p "require('./{{app}}/src-tauri/tauri.conf.json').version")
    APP="app/src-tauri/target/release/bundle/macos/FLAC Tools.app"
    DMG="app/src-tauri/target/release/bundle/dmg/FLAC Tools_${VERSION}_aarch64.dmg"
    OUT="release/dist/$VERSION"
    mkdir -p "$OUT"
    cp "$DMG" "$OUT/FLAC Tools $VERSION.dmg"
    cp "release/notes/$VERSION.md" "$OUT/"
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  FLAC Tools $VERSION is ready"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "  DMG:    $OUT/FLAC Tools $VERSION.dmg ($(du -sh "$OUT/FLAC Tools $VERSION.dmg" | cut -f1))"
    echo "  Notes:  $OUT/$VERSION.md"
    if xcrun stapler validate -q "$APP" 2>/dev/null && xcrun stapler validate -q "$DMG" 2>/dev/null; then
        echo "  ✓  App and DMG notarised and stapled"
    else
        echo "  ⚠  App or DMG not notarised — run 'just notary-check', then 'just notarize-dmg'"
    fi
    echo ""

# Store the Apple ID app-specific password used to notarise (prompts, nothing echoed)
notary-password apple_id:
    security add-generic-password -U -a "{{apple_id}}" -s "${FLAC_TOOLS_APPLE_KEYCHAIN_SERVICE:-flac-tools-apple-notary}" -w

# Check the Developer ID certificate and the notarisation credentials
notary-check:
    #!/usr/bin/env bash
    set -euo pipefail
    . scripts/apple-signing-env.sh
    echo "Signing identity: $APPLE_SIGNING_IDENTITY"
    echo "Apple ID:         $APPLE_ID"
    echo "notarytool profile '$FLAC_TOOLS_NOTARY_PROFILE' is accepted by Apple."

# Notarise and staple the DMG from the last build (to retry just that step)
notarize-dmg:
    bash scripts/notarize-dmg.sh
