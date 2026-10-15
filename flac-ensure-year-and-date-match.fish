#!/usr/bin/env fish
# Sets YEAR to the year in DATE wherever the two disagree.
#
# Recursively scans every .flac file under --path (default: current
# directory) and makes the YEAR tag match the year part of the DATE tag
# (its first four characters, so "1997-05-12" gives "1997"). Files with no
# DATE are skipped, as are files whose YEAR already matches.
#
# Usage: ./flac-ensure-year-and-date-match.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-ensure-year-and-date-match.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively sets YEAR to the first four characters of DATE on"
    echo "every .flac file where the two disagree. Files with no DATE are"
    echo "left untouched."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set changed 0
set checked 0

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    set checked (math "$checked + 1")
    set date (flac_get_tag "$f" DATE)[1]
    set year (flac_get_tag "$f" YEAR)[1]
    set date_year (string sub -l 4 -- "$date")

    if test -z "$date_year"
        flac_log_v "$f  no DATE, skipping"
        continue
    end
    if test "$year" = "$date_year"
        flac_log_v "$f  YEAR '$year' already matches"
        continue
    end

    flac_log "$f  YEAR: '$year' -> '$date_year'"
    flac_set_tag "$f" YEAR "$date_year"
    set changed (math "$changed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Checked: $checked"
echo "Changed: $changed"
