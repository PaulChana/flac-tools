#!/usr/bin/env fish
# Removes a year from the front of folder names, so "1986 - Licensed To
# Ill" becomes "Licensed To Ill".
#
# Recursively renames every folder under --path (default: current
# directory, which itself is left alone) whose name starts with a year and
# a separator: "1986 - ", "1986-", "1986. ", "1986_", "(1986) " or
# "[1986] ". A year followed only by a space ("2001 A Space Odyssey") is
# not touched, nor is a folder named just a year. A folder whose new name
# is already taken is skipped and reported.
#
# Usage: ./flac-remove-date-prefix.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-remove-date-prefix.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively renames folders like \"1986 - Licensed To Ill\" to"
    echo "\"Licensed To Ill\". Handles \"1986 - \", \"1986-\", \"1986. \", \"1986_\","
    echo "\"(1986) \" and \"[1986] \"; a year followed only by a space is left alone."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set renamed 0
set conflicts 0

for d in (find "$opt_path" -mindepth 1 -depth -type d -not -path '*/.*')
    set name (basename "$d")
    set m (string match -r '^(?:[(\[]\s*(?:19|20)\d\d\s*[)\]]\s*|(?:19|20)\d\d\s*[-–—._]\s*)(.+)$' -- "$name")
    or continue
    set new (string trim -- $m[2])
    test -n "$new"; or continue
    set dest (dirname "$d")/$new

    if test -e "$dest"
        flac_err "CONFLICT: $d — \"$new\" already exists there, left as is"
        set conflicts (math "$conflicts + 1")
        continue
    end
    flac_log "$d  ->  $new"
    if test $opt_dry_run -eq 0
        mv "$d" "$dest"; or begin
            flac_err "Couldn't rename $d"
            continue
        end
    end
    set renamed (math "$renamed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no folders were renamed)"
end
echo "Renamed: $renamed"
echo "Conflicts (name already taken): $conflicts"
