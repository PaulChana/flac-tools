#!/usr/bin/env fish
# Deletes everything except .flac files and images, plus covers and
# Artwork folders.
#
# Recursively scans all directories under --path (default: current
# directory) and deletes any file that is NOT a .flac file and NOT a
# common image file (jpg, jpeg, png, gif, bmp, webp). This clears out
# leftover cue sheets, playlists, logs, text files, nfo files, etc.
# Also deletes whole "covers" and "Artwork" folders (any case) of scans
# and booklets — unless one holds FLAC files, as an album called "Covers"
# would, which is skipped with a warning.
#
# Usage: ./flac-remove-extraneous-files.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-remove-extraneous-files.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively deletes any file that is not a .flac file or a common"
    echo "image file (jpg, jpeg, png, gif, bmp, webp). This removes"
    echo "leftover .cue, .m3u, .log, .txt, .nfo, etc. Also deletes folders"
    echo "named covers or Artwork (any case), unless they hold FLAC files."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

for d in (find "$opt_path" -mindepth 1 -type d \( -iname covers -o -iname artwork \) -prune)
    if test -n "$(find "$d" -type f -iname '*.flac' -print -quit)"
        flac_err "Skipped $d — it has FLAC files in it"
    else if test $opt_dry_run -eq 1
        echo "$d/"
    else
        test $opt_verbose -eq 1; and echo "$d/"
        rm -rf "$d"
    end
end

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
