#!/usr/bin/env fish
# One-time migration: recursively finds every folder.jpg under --path
# (default: current directory) and renames it to cover.jpg. Skips any
# directory that already has a cover.jpg (flags it rather than
# overwriting).
#
# Usage: ./flac-rename-folder-to-cover.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-rename-folder-to-cover.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively renames every folder.jpg to cover.jpg. Flags (does"
    echo "not overwrite) any directory that already has both."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set renamed 0
set conflicts 0

for f in (find "$opt_path" -type f -iname 'folder.jpg')
    set d (dirname "$f")
    set dest "$d/cover.jpg"

    if test -f "$dest"
        flac_log "CONFLICT: $d already has cover.jpg — folder.jpg left in place"
        set conflicts (math "$conflicts + 1")
    else
        flac_log "Renamed: $f -> $dest"
        if test $opt_dry_run -eq 0
            mv "$f" "$dest"
        end
        set renamed (math "$renamed + 1")
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Renamed: $renamed"
echo "Conflicts (both existed): $conflicts"
