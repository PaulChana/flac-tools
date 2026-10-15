#!/usr/bin/env fish
# Sets DISCNUMBER and DISCTOTAL to 1, for single-disc albums.
#
# Recursively scans every .flac file under --path (default: current
# directory) and sets DISCNUMBER=1 and DISCTOTAL=1, for single-disc
# albums. Files that already have both are left alone. Don't run it on a
# multi-disc set: every disc would become disc 1.
#
# Usage: ./flac-set-disc-one.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-set-disc-one.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively sets DISCNUMBER=1 and DISCTOTAL=1 on every .flac file,"
    echo "for single-disc albums. Not for multi-disc sets."
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
    set disc (flac_get_tag "$f" DISCNUMBER)
    set total (flac_get_tag "$f" DISCTOTAL)
    if test "$disc" = 1; and test "$total" = 1
        flac_log_v "$f  already disc 1 of 1"
        continue
    end
    flac_log "$f  DISCNUMBER '$disc' -> '1', DISCTOTAL '$total' -> '1'"
    flac_set_tag "$f" DISCNUMBER 1
    flac_set_tag "$f" DISCTOTAL 1
    set changed (math "$changed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Checked: $checked"
echo "Changed: $changed"
