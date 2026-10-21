#!/usr/bin/env fish
# Sets ALBUMARTIST to each file's ARTIST.
#
# Recursively copies the ARTIST tag into ALBUMARTIST on every .flac file
# under --path (default: current directory), exactly as written and
# overwriting whatever ALBUMARTIST was before. Files with no ARTIST are
# left alone. Album folders whose tracks have more than one ARTIST
# (compilations, guest spots) are skipped and flagged, since giving each
# track its own album artist splits the album up in most players; pass
# --mixed to copy them anyway.
#
# Usage: ./flac-copy-artist-to-albumartist.fish [--mixed] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-copy-artist-to-albumartist.fish [--mixed] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively sets ALBUMARTIST to each file's ARTIST, exactly as"
    echo "written, overwriting what was there. Files with no ARTIST are left"
    echo "alone. Album folders with more than one ARTIST are skipped."
    echo
    echo "  --mixed   Also copy in folders whose tracks have different"
    echo "            artists (each track gets its own ALBUMARTIST)."
    flac_common_help
    echo
    echo "To set one name on every file instead, use flac-set-albumartist.fish."
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set mixed 0
contains -- --mixed $argv; and set mixed 1

set files_changed 0
set folders_skipped 0

for d in (flac_find_flac_dirs "$opt_path")
    set files (flac_files_in "$d")
    set artists
    for f in $files
        set a (flac_get_tag "$f" ARTIST)
        # One entry per file, empty when it has no ARTIST.
        set -a artists "$a[1]"
    end

    set distinct (printf '%s\n' $artists | string match -v '' | sort -u)
    if test (count $distinct) -gt 1; and test $mixed -eq 0
        flac_log "SKIP: $d has "(count $distinct)" different artists (use --mixed to copy anyway)"
        set folders_skipped (math "$folders_skipped + 1")
        continue
    end

    for i in (seq (count $files))
        set f $files[$i]
        set artist $artists[$i]
        if test -z "$artist"
            flac_log_v "$f  no ARTIST, left alone"
            continue
        end
        set old (flac_get_tag "$f" ALBUMARTIST)
        if test "$old" = "$artist"
            flac_log_v "$f  unchanged"
            continue
        end
        flac_log "$f"
        flac_log "  ALBUMARTIST: '$old' -> '$artist'"
        flac_set_tag "$f" ALBUMARTIST "$artist"
        set files_changed (math "$files_changed + 1")
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Files changed: $files_changed"
echo "Folders skipped (several artists): $folders_skipped"
