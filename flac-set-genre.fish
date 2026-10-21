#!/usr/bin/env fish
# Asks for a genre in a dialog, then sets GENRE on every .flac file.
#
# Recursively finds the .flac files under --path (default: current
# directory), opens a macOS dialog asking for the genre (filled in with
# the current one when every file already has the same genre), and sets
# GENRE on all of them, replacing whatever was there. Cancelling the
# dialog, or leaving it empty, changes nothing. Pass --genre=NAME to skip
# the dialog.
#
# Usage: ./flac-set-genre.fish [--genre=NAME] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-set-genre.fish [--genre=NAME] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Asks for a genre in a dialog, then sets GENRE on every .flac file"
    echo "under the folder, replacing whatever was there. Cancelling the"
    echo "dialog, or leaving it empty, changes nothing."
    echo
    echo "  --genre=NAME   Use NAME instead of asking."
    flac_common_help
    echo
    echo "Example: flac-set-genre.fish --genre=\"Drum & Bass\""
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set genre ""
set asked 1
for a in $argv
    if string match -q -- '--genre=*' $a
        set genre (string replace -- '--genre=' '' $a)
        set asked 0
    end
end

set files (find "$opt_path" -type f -iname '*.flac' -not -name '.*' | sort)
if test (count $files) -eq 0
    echo "No .flac files under $opt_path."
    exit 0
end

if test $asked -eq 1
    # Offer the current genre when every file already has the same one.
    set current (for f in $files; set g (flac_get_tag "$f" GENRE); echo "$g[1]"; end | sort -u)
    set default ""
    test (count $current) -eq 1; and set default $current[1]

    set folder (basename (realpath "$opt_path"))
    set prompt "Genre for the "(count $files)" FLAC file(s) in “$folder”:"
    set genre (osascript \
        -e 'on run argv' \
        -e 'tell me to activate' \
        -e 'set r to display dialog (item 1 of argv) default answer (item 2 of argv) with title "Set genre" buttons {"Cancel", "Set Genre"} default button "Set Genre" cancel button "Cancel"' \
        -e 'return text returned of r' \
        -e 'end run' \
        -- "$prompt" "$default" 2>/dev/null)
    if test $status -ne 0
        echo "Cancelled — no files were changed."
        exit 0
    end
end

set genre (string trim -- "$genre")
if test -z "$genre"
    echo "No genre given — no files were changed."
    exit 0
end

set files_changed 0
for f in $files
    set old (flac_get_tag "$f" GENRE | string join ' / ')
    if test "$old" = "$genre"
        flac_log_v "$f  unchanged"
        continue
    end
    flac_log "$f"
    flac_log "  GENRE: '$old' -> '$genre'"
    flac_set_tag "$f" GENRE "$genre"
    set files_changed (math "$files_changed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Genre: $genre"
echo "Files changed: $files_changed"
