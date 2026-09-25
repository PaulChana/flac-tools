#!/usr/bin/env fish
# Recursively sets ALBUMARTIST to NEW_NAME on every .flac file under
# --path (default: current directory), overwriting whatever was there
# before. Pass --both to also set ARTIST. This is a deliberate,
# explicit-value correction tool — for filling in empty tags instead,
# use flac-fill-tags.fish.
#
# Usage: ./flac-set-albumartist.fish NEW_NAME [--both] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-set-albumartist.fish NEW_NAME [--both] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively sets ALBUMARTIST to NEW_NAME on every .flac file,"
    echo "overwriting whatever was there before."
    echo
    echo "  --both   Also set ARTIST to NEW_NAME (default: ALBUMARTIST only)."
    flac_common_help
    echo
    echo "Example: flac-set-albumartist.fish \"The Prodigy\""
    echo "Example: flac-set-albumartist.fish \"The Prodigy\" --both"
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set both 0
if contains -- --both $argv
    set both 1
end

set new_name (string match -v -- '--*' $argv)[1]

if test -z "$new_name"
    flac_err "Error: no name given."
    flac_err "Usage: flac-set-albumartist.fish NEW_NAME [--both]"
    exit 1
end

set files_changed 0

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    set old_albumartist (flac_get_tag "$f" ALBUMARTIST)

    flac_log "$f"
    flac_log "  ALBUMARTIST: '$old_albumartist' -> '$new_name'"
    flac_set_tag "$f" ALBUMARTIST "$new_name"

    if test $both -eq 1
        set old_artist (flac_get_tag "$f" ARTIST)
        flac_log "  ARTIST: '$old_artist' -> '$new_name'"
        flac_set_tag "$f" ARTIST "$new_name"
    end

    set files_changed (math "$files_changed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Files changed: $files_changed"
