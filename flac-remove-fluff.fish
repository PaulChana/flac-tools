#!/usr/bin/env fish
# Recursively scans all directories under --path (default: current
# directory) and deletes any file that is NOT a .flac file and NOT a
# common image file (jpg, jpeg, png, gif, bmp, webp). This clears out
# leftover cue sheets, playlists, logs, text files, nfo files, etc.
#
# Usage: ./flac-remove-fluff.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-remove-fluff.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively deletes any file that is not a .flac file or a common"
    echo "image file (jpg, jpeg, png, gif, bmp, webp). This removes"
    echo "leftover .cue, .m3u, .log, .txt, .nfo, etc."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set find_expr -type f \
    -not -iname '*.flac' \
    -not -iname '*.jpg' \
    -not -iname '*.jpeg' \
    -not -iname '*.png' \
    -not -iname '*.gif' \
    -not -iname '*.bmp' \
    -not -iname '*.webp'

if test $opt_dry_run -eq 1
    find "$opt_path" $find_expr -print
else if test $opt_verbose -eq 1
    find "$opt_path" $find_expr -print -delete
else
    find "$opt_path" $find_expr -delete
end
