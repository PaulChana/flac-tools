#!/usr/bin/env fish
# Recursively scans directories under --path (default: current directory).
# In any directory containing "NN - Name.flac" style files, generates an
# m3u playlist listing those tracks in order, named after the directory
# itself (e.g. a dir called "One Love" gets "One Love.m3u").
#
# Paths written into the m3u are relative filenames only (just the track's
# own filename), since the m3u lives alongside the tracks in the same dir.
#
# Usage: ./flac-make-m3u.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-make-m3u.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively scans directories and creates <dirname>.m3u in any"
    echo "directory containing .flac files, listing the tracks (by"
    echo "filename, in sorted order)."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set created 0

for d in (find "$opt_path" -type d)
    set flacs $d/*.flac
    if test (count $flacs) -gt 0
        set dirname (basename "$d")
        set out "$d/$dirname.m3u"

        if test $opt_dry_run -eq 1
            flac_log "Would create: $out"
            for f in $flacs
                flac_log_v "  "(basename "$f")
            end
        else
            rm -f "$out"
            for f in $flacs
                basename "$f" >> "$out"
            end
            flac_log "Created: $out"
        end
        set created (math "$created + 1")
    end
end

if test $opt_quiet -eq 1
    if test $opt_dry_run -eq 1
        echo "Would create: $created"
    else
        echo "Created: $created"
    end
end
