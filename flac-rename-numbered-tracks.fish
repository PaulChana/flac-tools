#!/usr/bin/env fish
# Recursively finds files named "NN Name" or "NN. Name" (NN = two digits,
# optional trailing period) under --path (default: current directory),
# and renames them to "NN - Name".
#
# Usage: ./flac-rename-numbered-tracks.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-rename-numbered-tracks.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively renames files named 'NN Name' or 'NN. Name' (NN = two"
    echo "digits, optional trailing period) to 'NN - Name'."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

flac_log_v "Scanning from: $opt_path"

set candidates (find -E "$opt_path" -type f -regex '.*/[0-9][0-9]\.? [^/]*')
flac_log_v "Files matching pattern: "(count $candidates)

if test (count $candidates) -eq 0
    flac_log "No matching files found. Checking for .flac files at all..."
    set all_flac (find "$opt_path" -type f -iname '*.flac')
    flac_log "Total .flac files under here: "(count $all_flac)
    if test (count $all_flac) -gt 0
        flac_log "Example filenames found (first 5):"
        for f in $all_flac[1..5]
            flac_log "  "(basename "$f")
        end
    end
    exit 0
end

set renamed 0
set skipped 0

for d in $candidates
    set base (basename "$d")
    flac_log_v "Found: $d"
    if string match -rq '^[0-9][0-9] - ' -- "$base"
        flac_log_v "  SKIP (already in NN - Name format)"
        set skipped (math "$skipped + 1")
    else
        set new_path (echo $d | sed -E 's/([0-9][0-9])\.? /\1 - /')
        if test $opt_dry_run -eq 1
            flac_log "$d -> "(basename "$new_path")
            set renamed (math "$renamed + 1")
        else if mv "$d" "$new_path"
            flac_log "$d -> "(basename "$new_path")
            set renamed (math "$renamed + 1")
        else
            flac_err "FAILED to rename: $d"
        end
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Renamed: $renamed"
echo "Skipped (already correct): $skipped"
