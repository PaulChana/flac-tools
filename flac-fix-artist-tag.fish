#!/usr/bin/env fish
# Recursively replaces the ARTIST tag on every .flac file under --path
# (default: current directory), but only for files whose current ARTIST
# matches OLD_NAME (case-insensitive). Files with a different artist are
# left untouched. This is a targeted correction tool for a known-wrong
# value — for filling in empty tags, use flac-fill-tags.fish instead.
#
# Usage: ./flac-fix-artist-tag.fish OLD_NAME NEW_NAME [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-fix-artist-tag.fish OLD_NAME NEW_NAME [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively replaces ARTIST on every .flac file whose current"
    echo "ARTIST matches OLD_NAME (case-insensitive) with NEW_NAME. Files"
    echo "with a different artist are left untouched."
    echo
    flac_common_help
    echo
    echo "Example: flac-fix-artist-tag.fish \"prodigy\" \"The Prodigy\""
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set positional
for a in $argv
    if not string match -rq '^--' -- "$a"
        set positional $positional "$a"
    end
end

if test (count $positional) -lt 2
    flac_err "Error: need OLD_NAME and NEW_NAME."
    flac_err "Usage: flac-fix-artist-tag.fish OLD_NAME NEW_NAME [--path=DIR] [--dry-run]"
    exit 1
end

set old_name (string lower -- $positional[1])
set new_name $positional[2]

set changed 0

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    if test (string lower -- (flac_get_tag "$f" ARTIST)) = "$old_name"
        flac_log "$f  ARTIST: '$positional[1]' -> '$new_name'"
        flac_set_tag "$f" ARTIST "$new_name"
        set changed (math "$changed + 1")
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Changed: $changed"
