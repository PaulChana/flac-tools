#!/usr/bin/env fish
# Moves cover.jpg out of albumart_backup folders, next to the .flac files,
# and deletes the albumart_backup folder.
#
# Recursively finds every albumart_backup folder under --path (default:
# current directory) that holds a cover.jpg, moves the cover up one level
# into the album folder, then deletes the albumart_backup folder. Folders
# are left alone, and flagged, when the album folder already has a
# cover.jpg (unless --force), when the album folder has no .flac files, or
# when albumart_backup holds anything besides cover.jpg (and .DS_Store).
#
# Usage: ./flac-restore-cover-backup.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-restore-cover-backup.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively finds albumart_backup folders holding a cover.jpg, moves"
    echo "the cover up into the album folder next to the .flac files, and"
    echo "deletes the albumart_backup folder. Skips (and flags) folders where:"
    echo "  - the album folder already has a cover.jpg (unless --force),"
    echo "  - the album folder has no .flac files,"
    echo "  - albumart_backup holds anything besides cover.jpg and .DS_Store."
    echo
    echo "  --force   Replace an existing cover.jpg in the album folder."
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set force 0
contains -- --force $argv; and set force 1

set moved 0
set skipped 0

for b in (find "$opt_path" -type d -name albumart_backup | sort)
    set cover (find "$b" -maxdepth 1 -type f -iname cover.jpg | head -1)
    if test -z "$cover"
        flac_log_v "No cover.jpg in $b"
        continue
    end

    set album (dirname "$b")
    set dest "$album/cover.jpg"

    set others (find "$b" -mindepth 1 -maxdepth 1 -not -path "$cover" -not -name .DS_Store)
    if test (count $others) -gt 0
        flac_log "SKIP: $b has other files too ("(count $others)") — left in place"
        set skipped (math "$skipped + 1")
        continue
    end
    if test (count (flac_files_in "$album")) -eq 0
        flac_log "SKIP: $album has no .flac files — $b left in place"
        set skipped (math "$skipped + 1")
        continue
    end
    if test -f "$dest"; and test $force -eq 0
        flac_log "CONFLICT: $album already has cover.jpg — $b left in place"
        set skipped (math "$skipped + 1")
        continue
    end

    flac_log "Moved: $cover -> $dest"
    flac_log "Deleted: $b"
    if test $opt_dry_run -eq 0
        if not mv -f "$cover" "$dest"
            flac_err "Couldn't move $cover — $b left in place"
            set skipped (math "$skipped + 1")
            continue
        end
        rm -rf "$b"
    end
    set moved (math "$moved + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Covers moved: $moved"
echo "Skipped: $skipped"
