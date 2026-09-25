#!/usr/bin/env fish
# Recursively scans every .flac file under --path (default: current
# directory) and reports any that are missing common metadata: TITLE,
# ARTIST, ALBUM, TRACKNUMBER, ALBUMARTIST, or an embedded picture.
#
# --extended additionally checks GENRE, DATE, DISCNUMBER, and COMPOSER.
# --verify additionally runs a full decode integrity test (flac -t) on
# each file — a corrupted audio stream can make some players report
# "missing info" even when every tag is actually present.
# --dupes additionally flags files with more than one value for the same
# tag (e.g. two ARTIST fields), which confuses some players.
# --dump prints every tag actually stored on each file instead of running
# the missing-field checks — pass specific files as arguments (once
# identified in whatever player is complaining) to inspect exactly what's
# there, rather than guessing which fields it cares about.
#
# Usage: ./flac-find-missing-info.fish [--no-art] [--extended] [--verify] [--dupes] [--dump]
#                                       [--path=DIR] [--verbose] [--quiet] [FILE ...]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-find-missing-info.fish [--no-art] [--extended] [--verify] [--dupes] [--dump]"
    echo "                                    [--path=DIR] [--verbose] [--quiet] [FILE ...]"
    echo "Recursively scans .flac files and reports any missing TITLE,"
    echo "ARTIST, ALBUM, TRACKNUMBER, ALBUMARTIST, or embedded cover art."
    echo
    echo "  --no-art     Skip the embedded cover art check."
    echo "  --extended   Also check GENRE, DATE, DISCNUMBER, and COMPOSER."
    echo "  --verify     Also run a decode integrity test (flac -t) on each"
    echo "               file — catches corruption that can look like"
    echo "               'missing info' in some players even when tags"
    echo "               are actually fine."
    echo "  --dupes      Also flag files with duplicate values for the same"
    echo "               tag (e.g. two ARTIST fields)."
    echo "  --dump       Instead of checking, print every tag actually"
    echo "               stored on each file. Pass specific FILE paths to"
    echo "               inspect just those (e.g. files your player flags)"
    echo "               rather than scanning everything."
    echo
    flac_common_help
    echo
    echo "If FILE arguments are given, only those files are processed"
    echo "(scan mode or dump mode); otherwise every .flac under --path is"
    echo "scanned."
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set check_art 1
if contains -- --no-art $argv
    set check_art 0
end

set extended 0
if contains -- --extended $argv
    set extended 1
end

set verify 0
if contains -- --verify $argv
    set verify 1
    if not type -q flac
        flac_err "Error: 'flac' (the CLI tool) not found for --verify. Install with: brew install flac"
        exit 1
    end
end

set check_dupes 0
if contains -- --dupes $argv
    set check_dupes 1
end

set dump_mode 0
if contains -- --dump $argv
    set dump_mode 1
end

set check_tags TITLE ARTIST ALBUM TRACKNUMBER ALBUMARTIST
if test $extended -eq 1
    set check_tags $check_tags GENRE DATE DISCNUMBER COMPOSER
end

# Placeholder values that count as "not really set" even though the tag
# is technically non-empty — whitespace-only, or generic filler text a
# player might reasonably treat as fake. Deliberately conservative: words
# like "none" or "various" are excluded because they're legitimate real
# titles/artist values (e.g. Meshuggah's "None" EP, "Various Artists" on
# compilations) and would false-positive.
set placeholders "unknown" "unknown artist" "unknown album" "unknown title" \
    "n/a" "na" "untitled" "-" "tbd"

function is_placeholder
    set val (string trim -- $argv[1])
    if test -z "$val"
        return 0
    end
    set lower (string lower -- $val)
    for p in $argv[2..-1]
        if test "$lower" = "$p"
            return 0
        end
    end
    return 1
end

# Any non-flag arguments are treated as explicit files to process.
set explicit_files
for a in $argv
    if not string match -rq '^--' -- "$a"
        set explicit_files $explicit_files "$a"
    end
end

if test (count $explicit_files) -gt 0
    set file_list $explicit_files
else
    set file_list (find "$opt_path" -type f -iname '*.flac' | sort)
end

if test $dump_mode -eq 1
    for f in $file_list
        echo "== $f =="
        metaflac --export-tags-to=- "$f"
        if metaflac --list --block-type=PICTURE "$f" | grep -q .
            echo "(has embedded picture)"
        else
            echo "(no embedded picture)"
        end
        echo
    end
    exit 0
end

set flagged 0
set total 0

for f in $file_list
    set total (math "$total + 1")
    set missing

    for tag in $check_tags
        set val (flac_get_tag "$f" $tag)

        if contains -- $tag TITLE ARTIST ALBUM
            if is_placeholder "$val" $placeholders
                set missing $missing "$tag (empty or placeholder)"
            end
        else
            if test -z (string trim -- $val)
                set missing $missing $tag
            end
        end
    end

    if test $check_art -eq 1
        if not metaflac --list --block-type=PICTURE "$f" | grep -q .
            set missing $missing "COVER ART"
        end
    end

    if test $check_dupes -eq 1
        for tag in $check_tags
            set count (metaflac --show-tag=$tag "$f" | count)
            if test $count -gt 1
                set missing $missing "DUPLICATE $tag"
            end
        end
    end

    if test $verify -eq 1
        if not flac -t -s "$f" 2>/dev/null
            set missing $missing "FAILED INTEGRITY CHECK"
        end
    end

    if test (count $missing) -gt 0
        flac_log "$f"
        flac_log "  Missing: "(string join ', ' $missing)
        set flagged (math "$flagged + 1")
    else
        flac_log_v "$f — OK"
    end
end

echo
echo "Total .flac files scanned: $total"
echo "Flagged (missing at least one field): $flagged"
