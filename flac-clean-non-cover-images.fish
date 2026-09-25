#!/usr/bin/env fish
# Recursively deletes any .jpg/.jpeg/.png file NOT named cover.jpg, and any
# Thumbs.db file, under --path (default: current directory).
#
# Usage: ./flac-clean-non-cover-images.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-clean-non-cover-images.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively deletes any .jpg/.jpeg/.png file NOT named cover.jpg, and"
    echo "any Thumbs.db file."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set find_expr -type f \
    -not -iname 'cover.jpg' \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \)

set thumbs_expr -type f -iname 'Thumbs.db'

if test $opt_dry_run -eq 1
    find "$opt_path" $find_expr -print
    find "$opt_path" $thumbs_expr -print
else
    if test $opt_verbose -eq 1
        find "$opt_path" $find_expr -print -delete
        find "$opt_path" $thumbs_expr -print -delete
    else
        find "$opt_path" $find_expr -delete
        find "$opt_path" $thumbs_expr -delete
    end
end
