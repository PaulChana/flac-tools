# Release notes

One file per release, named for the version: `0.2.0.md`. Write what changed for people using
the app, in Markdown.

`just deploy` looks here for the version being built (the one in `app/package.json`, set with
`just bump`). If the file is missing and you're in a terminal, it opens `$EDITOR` (or reads
the notes from the terminal) and saves them here; otherwise it stops. The notes are copied
next to the DMG in `release/dist/<version>/`.
