#!/usr/bin/env fish
# Splits a single whole-album FLAC file into individual tracks using its
# accompanying cue sheet, naming each output file "NN - Track Title.flac"
# and tagging each with the correct artist/album/title/track number from
# the cue sheet.
#
# By default, split tracks are written to a "tracks" subdirectory alongside
# the source FLAC, so the original file is never overwritten or matched
# by the tagging step. FLAC_FILE/CUE_FILE/OUTPUT_DIR are resolved relative
# to --path (default: current directory) if given as relative paths.
#
# Requires: shntool, cuetools, flac (Homebrew: brew install shntool cuetools flac)
#
# Usage: ./flac-from-cue.fish FLAC_FILE CUE_FILE [OUTPUT_DIR] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-from-cue.fish FLAC_FILE CUE_FILE [OUTPUT_DIR] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Splits FLAC_FILE into individual tracks according to CUE_FILE,"
    echo "naming each 'NN - Title.flac' and tagging it from the cue sheet."
    echo
    echo "  OUTPUT_DIR   Where to write the split tracks (default: a 'tracks'"
    echo "               subdirectory next to FLAC_FILE)."
    echo
    flac_common_help
    echo "               (here: relative FLAC_FILE/CUE_FILE/OUTPUT_DIR are"
    echo "               resolved against this directory)"
    echo
    echo "Requires shntool, cuetools, and flac (brew install shntool cuetools flac)."
    exit 0
end

flac_parse_common_args $argv

set positional
for a in $argv
    if not string match -rq '^--' -- "$a"
        set positional $positional "$a"
    end
end

if test (count $positional) -lt 2
    flac_err "Error: need a FLAC file and a cue file."
    flac_err "Usage: flac-from-cue.fish FLAC_FILE CUE_FILE [OUTPUT_DIR]"
    exit 1
end

function resolve_path
    set p $argv[1]
    set base $argv[2]
    if string match -rq '^/' -- "$p"
        echo "$p"
    else
        echo "$base/$p"
    end
end

set flac_file (resolve_path "$positional[1]" "$opt_path")
set cue_file (resolve_path "$positional[2]" "$opt_path")

if not test -f "$flac_file"
    flac_err "Error: FLAC file not found: $flac_file"
    exit 1
end

if not test -f "$cue_file"
    flac_err "Error: cue file not found: $cue_file"
    exit 1
end

for cmd in shnsplit cuetag.sh flac
    if not type -q $cmd
        flac_err "Error: '$cmd' not found. Install with: brew install shntool cuetools flac"
        exit 1
    end
end

if test (count $positional) -ge 3
    set output_dir (resolve_path "$positional[3]" "$opt_path")
else
    set output_dir (dirname "$flac_file")/tracks
end

if test $opt_dry_run -eq 1
    echo "(dry run) Would split '$flac_file' using '$cue_file' into: $output_dir"
    exit 0
end

mkdir -p "$output_dir"

flac_log_v "Running shnsplit..."
shnsplit -f "$cue_file" -t '%n - %t' -o flac -O always -d "$output_dir" "$flac_file"

# shntool has no reliable manual zero-padding syntax for track numbers, so
# force two digits ourselves. This also matters for cuetag.sh below, which
# assigns tags by alphabetical filename order — unpadded numbers would sort
# "10" before "2" on any album with 10+ tracks and mis-tag everything.
for f in "$output_dir"/*.flac
    set base (basename "$f")
    if string match -rq '^[0-9] - ' -- "$base"
        set newname (string replace -r '^([0-9]) - ' '0$1 - ' "$base")
        mv "$f" "$output_dir/$newname"
        flac_log_v "Renamed: $base -> $newname"
    end
end

flac_log_v "Running cuetag.sh..."
cuetag.sh "$cue_file" "$output_dir"/*.flac

flac_log "Done. Tracks written to: $output_dir"
