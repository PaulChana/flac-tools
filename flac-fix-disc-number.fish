#!/usr/bin/env fish
# Splits disc numbers written like 1/2 into DISCNUMBER and DISCTOTAL.
#
# Recursively scans every .flac file under --path (default: current
# directory) for a DISCNUMBER written as "N/M" (e.g. "1/2") and splits
# it: DISCNUMBER becomes N, and DISCTOTAL is set to M if the file doesn't
# already have one. --tracks does the same for TRACKNUMBER/TRACKTOTAL.
#
# Usage: ./flac-fix-disc-number.fish [--tracks] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-fix-disc-number.fish [--tracks] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively changes DISCNUMBER \"1/2\" to DISCNUMBER=1, moving the"
    echo "total to DISCTOTAL when there isn't one already."
    echo
    echo "  --tracks     Also fix TRACKNUMBER \"3/12\" the same way (into TRACKTOTAL)."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set pairs DISCNUMBER:DISCTOTAL
if contains -- --tracks $argv
    set -a pairs TRACKNUMBER:TRACKTOTAL
end

set changed 0
set checked 0

for f in (find "$opt_path" -type f -iname '*.flac' | sort)
    set checked (math "$checked + 1")
    set touched 0
    for pair in $pairs
        set number_tag (string split : -- $pair)[1]
        set total_tag (string split : -- $pair)[2]
        set value (flac_get_tag "$f" $number_tag)
        test (count $value) -eq 1; or continue
        set m (string match -r '^\s*(\d+)\s*/\s*(\d+)\s*$' -- $value); or continue
        set total (flac_get_tag "$f" $total_tag)[1]

        set msg "$number_tag '$value' -> '$m[2]'"
        flac_set_tag "$f" $number_tag $m[2]
        if test -z "$total"
            set msg "$msg, $total_tag -> '$m[3]'"
            flac_set_tag "$f" $total_tag $m[3]
        else if test "$total" != "$m[3]"
            set msg "$msg ($total_tag kept as '$total')"
        end
        flac_log "$f  $msg"
        set touched 1
    end
    set changed (math "$changed + $touched")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Checked: $checked"
echo "Changed: $changed"
