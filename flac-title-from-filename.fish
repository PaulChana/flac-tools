#!/usr/bin/env fish
# Sets each file's TITLE tag from its file name.
#
# Recursively finds .flac files under --path (default: current directory)
# and sets TITLE to the file name without its extension and without the
# leading track number: "01 - Title.flac", "01. Title.flac", "01 Title.flac"
# and "1-01 Title.flac" all give "Title". In names with underscores and no
# spaces, the underscores become spaces. Overwrites the existing TITLE.
# Files whose name is only a number are skipped.
#
# Usage: ./flac-title-from-filename.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-title-from-filename.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively sets TITLE from each .flac file's name, without the"
    echo "extension and the leading track number, overwriting the old TITLE."
    echo "'01 - Title.flac', '01. Title.flac' and '1-01 Title.flac' all"
    echo "give 'Title'. Underscores become spaces in names with no spaces."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set files_changed 0
set skipped 0

for f in (find "$opt_path" -type f -iname '*.flac' -not -name '.*' | sort)
    set base (basename "$f")
    set title (string replace -ri -- '\.flac$' '' "$base")
    if not string match -q -- '* *' "$title"
        set title (string replace -a -- _ ' ' "$title")
    end
    # Leading "01", "1-01" or "101", then any of " - ", ". ", ") ", "_".
    set title (string replace -r -- '^\s*\d{1,3}(?!\d)(?:-\d{1,3}(?!\d))?\s*(?:[-.)_]\s*)*' '' "$title" | string trim)

    if test -z "$title"
        flac_err "Skipping $f: no title in the file name"
        set skipped (math "$skipped + 1")
        continue
    end

    set old (flac_get_tag "$f" TITLE | string join ' / ')
    if test "$old" = "$title"
        flac_log_v "$f  unchanged"
        continue
    end
    flac_log "$f"
    flac_log "  TITLE: '$old' -> '$title'"
    flac_set_tag "$f" TITLE "$title"
    set files_changed (math "$files_changed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Files changed: $files_changed"
echo "Skipped (no title in name): $skipped"
