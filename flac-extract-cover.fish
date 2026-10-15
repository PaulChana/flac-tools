#!/usr/bin/env fish
# Extracts the cover art embedded in one .flac file and saves it as
# cover.jpg in the same directory. Uses the front-cover picture if the
# file has one, otherwise the first picture. PNG (or any non-JPEG) art is
# converted to JPEG with sips, so cover.jpg is always a real JPEG. An
# existing cover.jpg is left alone unless --force is passed.
#
# Usage: ./flac-extract-cover.fish FLAC_FILE [--force] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-extract-cover.fish FLAC_FILE [--force] [--dry-run] [--verbose] [--quiet]"
    echo "Saves the cover art embedded in FLAC_FILE as cover.jpg next to it."
    echo "Prefers the front-cover picture; converts PNG art to JPEG."
    echo
    echo "  --force      Overwrite an existing cover.jpg."
    echo "  --dry-run    Print what would happen without writing anything."
    echo "  --verbose    Print extra detail (which picture block was used)."
    echo "  --quiet      Only print warnings and the result."
    echo
    echo "Example: flac-extract-cover.fish \"01 - Intro.flac\""
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set file (string match -v -- '--*' $argv)[1]
if test -z "$file"
    flac_err "Error: no FLAC file given."
    flac_err "Usage: flac-extract-cover.fish FLAC_FILE [--force] [--dry-run]"
    exit 1
end
if not test -f "$file"
    flac_err "Error: file not found: $file"
    exit 1
end

set force 0
if contains -- --force $argv
    set force 1
end

set dest (dirname "$file")/cover.jpg

set block ""
set mime ""
set first_block ""
set first_mime ""
set current ""
set current_type ""
for line in (metaflac --list --block-type=PICTURE "$file")
    if set -l m (string match -r '^METADATA block #(\d+)' -- $line)
        set current $m[2]
        set current_type ""
    else if set -l m (string match -r '^\s+type: (\d+) \(' -- $line)
        if test "$m[2]" != 6; or test -n "$current_type"
            set current_type $m[2]
        else
            set current_type block
        end
    else if set -l m (string match -r '^\s+MIME type: (.*)$' -- $line)
        if test -z "$first_block"
            set first_block $current
            set first_mime $m[2]
        end
        if test "$current_type" = 3; and test -z "$block"
            set block $current
            set mime $m[2]
        end
    end
end

if test -z "$first_block"
    flac_err "No embedded picture in $file"
    exit 1
end
if test -z "$block"
    flac_log_v "No front-cover picture; using the first picture (block $first_block)."
    set block $first_block
    set mime $first_mime
else
    flac_log_v "Using the front-cover picture (block $block, $mime)."
end

if test -e "$dest"; and test $force -ne 1
    flac_err "$dest already exists — pass --force to overwrite it."
    exit 1
end

if test $opt_dry_run -eq 1
    flac_log "Would write $dest from block $block ($mime)"
    echo
    echo "(dry run — no files were changed)"
    exit 0
end

if string match -qr '^image/jpe?g$' -- "$mime"
    metaflac --block-number=$block --export-picture-to="$dest" "$file"; or exit 1
else
    set tmp (mktemp -d -t flac-cover)
    metaflac --block-number=$block --export-picture-to="$tmp/picture" "$file"
    and sips -s format jpeg -s formatOptions 92 "$tmp/picture" --out "$tmp/cover.jpg" >/dev/null
    and cp -X "$tmp/cover.jpg" "$dest"
    set ok $status
    rm -rf "$tmp"
    if test $ok -ne 0
        flac_err "Couldn't convert the $mime picture to JPEG."
        exit 1
    end
end

set dims (sips -g pixelWidth -g pixelHeight "$dest" 2>/dev/null | string match -r '\d+$')
echo "Saved $dest"(test (count $dims) -eq 2; and echo " ($dims[1]×$dims[2])")
