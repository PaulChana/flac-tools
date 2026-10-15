#!/usr/bin/env fish
# Makes file extensions lowercase, so .FLAC becomes .flac and .JPG
# becomes .jpg.
#
# Recursively renames files under --path (default: current directory) so
# their extensions are lowercase: "01 - Intro.FLAC" -> "01 - Intro.flac",
# "Cover.JPG" -> "Cover.jpg". Only the extension changes. Pass --flac-only
# to leave everything but FLAC files alone. Hidden files are skipped, and
# so is any file whose lowercase name is already taken by a different file
# (possible on case-sensitive volumes).
#
# Usage: ./flac-ensure-lowercase-extensions.fish [--flac-only] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-ensure-lowercase-extensions.fish [--flac-only] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively makes file extensions lowercase (.FLAC -> .flac,"
    echo ".JPG -> .jpg). Only the extension is changed."
    echo
    echo "  --flac-only  Only rename FLAC files."
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set name_filter -name '*.*'
if contains -- --flac-only $argv
    set name_filter -iname '*.flac'
end

set renamed 0
set skipped 0

for f in (find "$opt_path" -type f $name_filter -not -name '.*' | sort -V)
    set base (basename "$f")
    set ext (string match -r -- '\.[^.]+$' $base)
    set lower (string lower -- "$ext")
    if test "$ext" = "$lower"
        continue
    end

    set dir (dirname "$f")
    set new (string replace -r -- '\.[^.]+$' "$lower" $base)

    if test -e "$dir/$new"; and test (stat -f %i "$dir/$new") != (stat -f %i "$f")
        flac_err "Skipping $f: '$new' already exists as a separate file"
        set skipped (math "$skipped + 1")
        continue
    end

    flac_log "$dir/"
    flac_log "  '$base' -> '$new'"
    if test $opt_dry_run -ne 1
        if not mv -- "$f" "$dir/$new"
            flac_err "Failed to rename $f"
            set skipped (math "$skipped + 1")
            continue
        end
    end
    set renamed (math "$renamed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Renamed: $renamed"
echo "Skipped: $skipped"
