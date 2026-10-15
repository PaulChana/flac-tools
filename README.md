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

The app is not signed. It runs on the Mac that built it. To use it on another Mac you need to sign it, or clear the quarantine flag after copying it there: `xattr -cr "FLAC Tools.app"`.

#### Other commands

Run `just` with no arguments to list them all.

| Command          | What it does                                                        |
| ---------------- | ------------------------------------------------------------------- |
| `just dev`       | Runs the app in development. The UI reloads when you save a file.   |
| `just test`      | Runs the Rust unit tests and the Svelte/TypeScript type check.      |
| `just test-rust` | Runs only the Rust unit tests.                                      |
| `just check`     | Runs only the type check (`svelte-check`).                          |
| `just install`   | Builds the app and copies it into `/Applications`.                  |
| `just open`      | Opens the built app.                                                |
| `just clean`     | Deletes the build output, `dist/` and `node_modules/`.              |

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
