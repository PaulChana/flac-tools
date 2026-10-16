#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: bump-version.sh <version>" >&2
    echo "  e.g. bump-version.sh 0.4.0" >&2
    echo "       bump-version.sh 0.4.0-beta.1" >&2
    exit 1
fi

VERSION="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)\.[0-9]+)?$ ]]; then
    echo "error: '$VERSION' is not a recognised version" >&2
    echo "       expected MAJOR.MINOR.PATCH, optionally -alpha.N or -beta.N" >&2
    exit 1
fi

FLAC_TOOLS_ROOT="$ROOT" FLAC_TOOLS_VERSION="$VERSION" node <<'NODE'
const {readFileSync, writeFileSync} = require('node:fs');

const root = process.env.FLAC_TOOLS_ROOT;
const version = process.env.FLAC_TOOLS_VERSION;

const cargoPath = `${root}/app/src-tauri/Cargo.toml`;
const cargoPattern = /(\[package\][\s\S]*?\nversion\s*=\s*")([^"]*)(")/;
const cargo = readFileSync(cargoPath, 'utf8');
if (!cargoPattern.test(cargo)) {
  console.error(`error: could not find a [package] version in ${cargoPath}`);
  process.exit(1);
}
writeFileSync(cargoPath, cargo.replace(cargoPattern, `$1${version}$3`));

for (const relative of [
  'app/src-tauri/tauri.conf.json',
  'app/package.json',
]) {
  const path = `${root}/${relative}`;
  const pattern = /("version":\s*")([^"]*)(")/;
  const source = readFileSync(path, 'utf8');
  if (!pattern.test(source)) {
    console.error(`error: could not find a "version" field in ${path}`);
    process.exit(1);
  }
  writeFileSync(path, source.replace(pattern, `$1${version}$3`));
}
NODE

# Bring Cargo.lock's entry for the app up to the new version.
cargo update --manifest-path "$ROOT/app/src-tauri/Cargo.toml" --offline -p flac-tools -q

CARGO_VERSION=$(grep -m1 '^version = ' "$ROOT/app/src-tauri/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')
CONF_VERSION=$(node -e "console.log(require('$ROOT/app/src-tauri/tauri.conf.json').version)")
PKG_VERSION=$(node -e "console.log(require('$ROOT/app/package.json').version)")

if [ "$CARGO_VERSION" != "$VERSION" ] || [ "$CONF_VERSION" != "$VERSION" ] || [ "$PKG_VERSION" != "$VERSION" ]; then
    echo "error: versions disagree after bumping" >&2
    echo "  Cargo.toml:      $CARGO_VERSION" >&2
    echo "  tauri.conf.json: $CONF_VERSION" >&2
    echo "  package.json:    $PKG_VERSION" >&2
    exit 1
fi

echo "Version set to $VERSION in all three files."
