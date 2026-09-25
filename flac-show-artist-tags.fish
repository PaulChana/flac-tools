#!/usr/bin/env fish
# Recursively prints the ARTIST and ALBUMARTIST tags for every .flac file
# under --path (default: current directory). Read-only — --dry-run is
# accepted for interface consistency with the rest of the toolkit but has
# no effect, since this script never writes anything.
#
# Usage: ./flac-show-artist-tags.fish [--path=DIR] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-show-artist-tags.fish [--path=DIR] [--quiet]"
    echo "Recursively prints the ARTIST and ALBUMARTIST tags for every"
    echo ".flac file. Read-only."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    if test $opt_quiet -eq 1
        set artist (flac_get_tag "$f" ARTIST)
        set albumartist (flac_get_tag "$f" ALBUMARTIST)
        echo "$f | ARTIST=$artist | ALBUMARTIST=$albumartist"
    else
        echo "$f"
        metaflac --show-tag=ARTIST --show-tag=ALBUMARTIST "$f"
        echo
    end
end
