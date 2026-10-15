#!/usr/bin/env fish
# Removes unwanted tags, keeping a sensible set by default.
#
# Recursively scans every .flac file under --path (default: current
# directory) and removes the tags you don't want. By default that's every
# tag outside a sensible list: ARTIST, ARTISTS, ALBUMARTIST, TITLE, ALBUM,
# TRACKNUMBER, TRACKTOTAL, DISCNUMBER, DISCTOTAL, DATE, YEAR, GENRE and
# REPLAYGAIN_*. Embedded pictures are kept (including art stored as a
# METADATA_BLOCK_PICTURE tag). --keep adds tags to the list; --only
# removes just the tags named instead.
#
# Usage: ./flac-remove-tags.fish [--keep=TAGS] [--only=TAGS] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-remove-tags.fish [--keep=TAGS] [--only=TAGS] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively removes unwanted tags from every .flac file. By default"
    echo "keeps only ARTIST, ARTISTS, ALBUMARTIST, TITLE, ALBUM, TRACKNUMBER,"
    echo "TRACKTOTAL, DISCNUMBER, DISCTOTAL, DATE, YEAR, GENRE and REPLAYGAIN_*."
    echo
    echo "  --keep=TAGS  Also keep these (comma-separated, e.g. --keep=COMPOSER,ISRC)."
    echo "  --only=TAGS  Remove only these tags (comma-separated) and keep the rest."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set keep ARTIST ARTISTS ALBUMARTIST TITLE ALBUM TRACKNUMBER TRACKTOTAL \
    DISCNUMBER DISCTOTAL DATE YEAR GENRE 'REPLAYGAIN_*' METADATA_BLOCK_PICTURE
set only
for a in $argv
    if string match -q -- '--keep=*' $a
        set -a keep (string upper -- (string split , -- (string replace -- '--keep=' '' $a)) | string trim)
    else if string match -q -- '--only=*' $a
        set -a only (string upper -- (string split , -- (string replace -- '--only=' '' $a)) | string trim)
    end
end

function unwanted --no-scope-shadowing --argument-names name
    if set -q only[1]
        contains -- $name $only
        return
    end
    for pattern in $keep
        string match -q -- $pattern $name; and return 1
    end
    return 0
end

set changed 0
set checked 0
set removed_total 0

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    set checked (math "$checked + 1")
    set names (metaflac --list --block-type=VORBIS_COMMENT "$f" \
        | string match -r '^\s+comment\[\d+\]: ([^=]+)=' | string match -rv '^\s+comment' \
        | string upper | sort -u)
    set drop
    for n in $names
        unwanted $n; and set -a drop $n
    end
    if not set -q drop[1]
        flac_log_v "$f  nothing to remove"
        continue
    end

    flac_log "$f  removing: "(string join ', ' -- $drop)
    if test $opt_dry_run -eq 0
        metaflac --remove-tag=$drop "$f"; or flac_err "Couldn't update $f"
    end
    set changed (math "$changed + 1")
    set removed_total (math "$removed_total + "(count $drop))
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Checked: $checked"
echo "Files changed: $changed"
echo "Tags removed: $removed_total"
