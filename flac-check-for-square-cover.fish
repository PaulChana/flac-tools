#!/usr/bin/env fish
# Recursively scans directories under --path (default: current directory).
# For each directory containing .flac files, checks that directory's
# cover.jpg AND the embedded picture in every individual .flac file,
# reporting any that aren't square, along with their actual dimensions.
# Also flags a missing cover.jpg, and any .flac file with no embedded
# picture at all.
#
# Uses macOS's built-in `sips` tool and `metaflac` (brew install flac) —
# no extra install needed for sips.
#
# Usage: ./flac-check-for-square-cover.fish [--path=DIR] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-check-for-square-cover.fish [--path=DIR] [--verbose] [--quiet]"
    echo "Recursively scans directories with .flac files, checking cover.jpg"
    echo "AND the embedded picture in every .flac file, reporting any that"
    echo "are not square (with dimensions). Also flags a missing cover.jpg"
    echo "or a .flac with no embedded picture."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

# "Square" here means close enough that a human wouldn't notice looking at
# it — a scan that's 1-2% off isn't a real problem, it's just imprecise
# cropping. Anything past this tolerance gets flagged.
set square_tolerance_pct 2

function check_square
    set path $argv[1]
    set label $argv[2]
    set width (sips -g pixelWidth "$path" | tail -1 | string trim | string replace 'pixelWidth: ' '')
    set height (sips -g pixelHeight "$path" | tail -1 | string trim | string replace 'pixelHeight: ' '')
    set diff (math "abs($width - $height)")
    set maxdim (math "max($width, $height)")
    set pct (math "$diff / $maxdim * 100")
    if test $pct -gt $square_tolerance_pct
        flac_log "NOT SQUARE: $label ($width x $height, "(math "round($pct * 10) / 10")"% off)"
        return 1
    end
    flac_log_v "OK: $label ($width x $height)"
    return 0
end

set found_issue 0
set tmp_img (mktemp -t coverart).jpg

for d in (find "$opt_path" -type d)
    set flacs $d/*.flac
    if test (count $flacs) -gt 0
        set cover "$d/cover.jpg"

        if not test -f "$cover"
            flac_log "MISSING: $d (has .flac files, no cover.jpg)"
            set found_issue 1
        else
            check_square "$cover" "$cover"; or set found_issue 1
        end

        for f in $flacs
            rm -f "$tmp_img"
            metaflac --export-picture-to="$tmp_img" "$f" 2>/dev/null

            if not test -s "$tmp_img"
                flac_log "NO EMBEDDED ART: $f"
                set found_issue 1
            else
                check_square "$tmp_img" "$f (embedded)"; or set found_issue 1
            end
        end
    end
end

rm -f "$tmp_img"

if test $found_issue -eq 0
    flac_log "All covers checked are square."
end
