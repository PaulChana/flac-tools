# flac-tools

CLI tools for working with Flac files

These are intended to be used with [https://fishshell.com](fish) on macos. They might work on linux too, but i havent tested them. Theyre built for my own use, but hopefully they will be useful to others

All files take a `--help` argument if you want to know how they work

## The app

`app/` holds a macOS app (Tauri + Svelte) for browsing a FLAC library and editing tags:

- Sidebar folder tree. Double-click, press Enter, or right-click a folder to rename it. The file icon in the sidebar header shows FLAC files in the tree too.
- Tables of subfolders, FLAC files (one column per tag found) and other files. A YEAR that doesn't match DATE is highlighted.
- Tag editor for the selected file(s). Press Enter in a field to write it. Edits that touch more than 20 files, or files from several folders, ask for confirmation first.
- Tools tab: runs any of the `flac-*.fish` scripts against the selected folder, dry run by default.

### Building the app

The app is a [Tauri 2](https://tauri.app) app: a Rust backend in `app/src-tauri/` and a Svelte 5 + TypeScript UI in `app/src/`, bundled with Vite. It builds for macOS only.

#### Prerequisites

- **Xcode Command Line Tools**: `xcode-select --install`
- **Rust** (stable), via [rustup](https://rustup.rs): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Node.js** 20.19 or newer (Vite needs it), with npm: `brew install node`
- **just**, to run the build commands: `brew install just`
- **fish** and **flac**: `brew install fish flac`. The Tools tab runs the scripts with fish, and some Rust tests use the `flac` CLI to make test files. Without `flac` those tests pass without checking anything.

Some scripts need more tools, which you only need for those scripts: `brew install jq` (`flac-fill-tags`, `flac-download-album-art`) and `brew install shntool cuetools` (`flac-make-tracks-from-cue`).

#### Build

From the repo root:

```sh
just build
```

This installs the npm packages if needed, builds the UI, compiles the Rust backend in release mode and bundles it. The app ends up at:

```
app/src-tauri/target/release/bundle/macos/FLAC Tools.app
```

The first build takes a few minutes while Cargo compiles the dependencies. Later builds are much faster.

This build is not signed (signed releases are made with `just release`, see [Releasing](#releasing)). It runs on the Mac that built it. To use it on another Mac you need to sign it, or clear the quarantine flag after copying it there: `xattr -cr "FLAC Tools.app"`.

#### Other commands

Run `just` with no arguments to list them all.

| Command                          | What it does                                                                                                  |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `just deps`                      | Installs the npm packages, only when `package-lock.json` has changed. The other commands run this first.     |
| `just build`                     | Builds the release app bundle, `FLAC Tools.app` (unsigned).                                                   |
| `just dev`                       | Runs the app in development. The UI reloads when you save a file.                                             |
| `just ui`                        | Builds only the UI, into `app/dist`. The Rust app embeds it, so the Rust tests need it.                       |
| `just test`                      | Runs the Rust unit tests and the Svelte/TypeScript type check.                                                |
| `just test-rust`                 | Runs only the Rust unit tests.                                                                                |
| `just check`                     | Runs only the type check (`svelte-check`) and the translation check.                                          |
| `just install`                   | Builds the app and copies it into `/Applications`.                                                            |
| `just open`                      | Opens the built app.                                                                                          |
| `just clean`                     | Deletes the build output, `dist/` and `node_modules/`.                                                        |
| `just bump <version>`            | Sets the version in `Cargo.toml`, `tauri.conf.json` and `package.json`.                                       |
| `just release <version>`         | Bumps the version, commits, and pushes `main` and the `v<version>` tag. GitHub Actions then builds the release. |
| `just deploy`                    | Tests, then builds, signs and notarises the app and its DMG, into `release/dist/<version>/`.                  |
| `just notary-password <apple-id>` | Stores the Apple ID app-specific password used to notarise in the macOS Keychain. It prompts for the password and doesn't echo it. |
| `just notary-check`              | Checks the Developer ID certificate and the notarisation credentials.                                         |
| `just notarize-dmg`              | Notarises and staples the DMG from the last build. Use it to retry only that step.                            |

If you don't have `just`, the same steps by hand are:

```sh
cd app
npm ci                                                 # install dependencies
npm run tauri dev                                      # run in development
npm run tauri build                                    # build the .app
cargo test --manifest-path src-tauri/Cargo.toml        # Rust tests
npm run check                                          # type check
```

One test, `trashes_folders`, is skipped by default because it moves a folder to your Trash. Run it with `cargo test --manifest-path app/src-tauri/Cargo.toml -- --ignored`.

#### Releasing

Releases are built, signed, notarised and published by the **Release** workflow
(`.github/workflows/release.yml`) when a `v*` tag is pushed. To make one:

1. Commit or finish the changes that go in the release, on `main`.
2. Write the release notes in `release/notes/<version>.md`, e.g. `release/notes/1.2.0.md`. Write what changed for people using the app, in Markdown. They become the GitHub release's description. See [release/notes/README.md](release/notes/README.md).
3. Run `just release <version>`, e.g. `just release 1.2.0`. It:
   - stops if you're not on `main`, if the notes file is missing, or if the tag already exists, locally or on GitHub
   - sets the version in `Cargo.toml`, `tauri.conf.json` and `package.json`
   - stages everything (`git add -A`) and shows what will be committed
   - asks for confirmation, then commits `Release <version>`, pushes `main`, and creates and pushes the `v<version>` tag

   If you answer no, the version bump stays in place and the changes stay staged.
4. Watch the run in the repo's **Actions** tab. The workflow checks the tag matches the version in `app/package.json` and that the notes exist, runs `just deploy`, then creates the GitHub release with the DMG attached as `FLAC-Tools-<version>.dmg`. A version with a hyphen, e.g. `1.3.0-beta.1`, is published as a pre-release.

The workflow needs these repository secrets:

| Secret                       | What it is                                                         |
| ---------------------------- | ------------------------------------------------------------------ |
| `APPLE_CERTIFICATE`          | The Developer ID Application certificate and key, as a base64 `.p12`. |
| `APPLE_CERTIFICATE_PASSWORD` | The password of that `.p12`.                                       |
| `APPLE_ID`                   | The Apple ID used to notarise.                                     |
| `APPLE_PASSWORD`             | An app-specific password for that Apple ID.                        |

##### Building a signed release locally

`just deploy` does the same build on your Mac, without publishing anything. It builds the version currently set in `app/package.json`; set that with `just bump <version>`. If the release notes are missing, it opens `$EDITOR` to write them, or reads them from the terminal. The DMG and notes end up in `release/dist/<version>/`.

It needs, once per Mac:

- the Developer ID Application certificate for team `M9T382L3AL` in your login keychain
- the Apple ID app-specific password, stored with `just notary-password <apple-id>`
- a notarytool profile, stored with `xcrun notarytool store-credentials flac-tools-notary --apple-id <apple-id> --team-id M9T382L3AL`

`just notary-check` confirms all three. If notarising the DMG fails, for example on a network error, run `just notarize-dmg` to retry that step without rebuilding.

#### Where the app finds the scripts

The `flac-*.fish` scripts are copied into the app when it's built, so the app doesn't need the repo to run them. After editing a script, rebuild the app to pick up the change.

To use scripts of your own, or to try script edits without rebuilding, use the folder button in the Tools tab to add a folder of extra scripts. Its `.fish` scripts appear alongside the bundled ones. A script with the same name as a bundled one replaces it. Pointing it at this repo runs the repo's copies. A script in another folder can use the shared helpers with `source $FLAC_TOOLS_LIB`, which the app sets to the bundled `flac-lib.fish`.

#### Translations

The interface is translated into German, English, Spanish, French, Hindi, Japanese, Brazilian and European Portuguese, and Chinese. Choose a language in Settings (⌘,). The translations are in `app/src/lib/locales`, one JSON file per language, keyed by the English text.

When you add or change text in the interface, wrap it in `$t("…")` (or `tr("…")` in a `.ts` file), then run `npm run i18n` in `app/`. That updates `en.json` and lists the strings each language is missing. `npm run check` fails until every language has them all, with the same `{placeholders}`.

#### Open source licences

The About page lists the open source software in the app. `npm run build` regenerates the list (`app/src/lib/generated/licenses.ts`) from the Rust crates and npm packages the app depends on, plus the bundled fonts.

#### Debugging in VS Code

`.vscode/` has launch configurations for the [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) extension:

- **FLAC Tools (Debug)** starts the Vite dev server and runs a debug build under the debugger.
- **FLAC Tools (Release)** builds the UI and runs an optimised build, which behaves like the bundled app.

## License

MIT
