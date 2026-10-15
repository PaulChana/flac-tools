#!/usr/bin/env fish
# Strips stray ID3 tags, left behind by MP3 tools, from .flac files.
#
# Recursively scans .flac files under --path (default: current directory)
# for ID3 tags — an ID3v2 block stuck in front of the FLAC data and/or an
# ID3v1 "TAG" block on the end — and strips them. These are leftovers from
# MP3 tools: they're not part of the FLAC format, players disagree about
# them, and the trailing ID3v1 block makes `flac -t` report decode errors.
# The FLAC's own tags (Vorbis comments) and pictures are untouched.
#
# Each file is rewritten to a temporary copy first; the copy only replaces
# the original once it's been checked to start with a valid FLAC header.
# Pass --scan to just list affected files.
#
# Usage: ./flac-remove-id3.fish [--scan] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-remove-id3.fish [--scan] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively strips ID3v2 (leading) and ID3v1 (trailing) tags from"
    echo ".flac files. The FLAC's own tags and pictures are kept."
    echo
    echo "  --scan       Only list files that have ID3 tags (same as --dry-run)."
    flac_common_help
    exit 0
end

flac_parse_common_args $argv
if contains -- --scan $argv
    set opt_dry_run 1
end

function bytes_at
    head -c $argv[2] "$argv[1]" | od -An -v -tu1 | string split -n ' '
end

set found 0
set stripped 0
set failed 0

for f in (find "$opt_path" -type f -iname '*.flac' -not -name '.*' | sort -V)
    set size (stat -f %z "$f")
    set front 0
    set back 0

    set kinds
    while true
        set h (tail -c +(math $front + 1) "$f" | head -c 10 | od -An -v -tu1 | string split -n ' ')
        if test (count $h) -eq 10; and test "$h[1] $h[2] $h[3]" = "73 68 51"
            set len (math "bitand($h[7], 127) * 2097152 + bitand($h[8], 127) * 16384 + bitand($h[9], 127) * 128 + bitand($h[10], 127) + 10")
            if test (math "bitand($h[6], 16)") -ne 0
                set len (math $len + 10)
            end
            set front (math $front + $len)
            set -a kinds ID3v2
        else
            break
        end
    end

    if test $size -gt 128
        set t (tail -c 128 "$f" | head -c 3 | od -An -v -tu1 | string split -n ' ')
        if test "$t" = "84 65 71"
            set back 128
            set -a kinds ID3v1
        end
    end

    if test $front -eq 0; and test $back -eq 0
        flac_log_v "clean: $f"
        continue
    end
    set found (math $found + 1)

    set magic (tail -c +(math $front + 1) "$f" | head -c 4)
    if test "$magic" != fLaC
        flac_err "SKIP (no FLAC data after the ID3 tag — unexpected layout): $f"
        set failed (math $failed + 1)
        continue
    end

    flac_log "$f"
    flac_log "  "(string join " + " $kinds)" ("(math $front + $back)" bytes)"
    if test $opt_dry_run -eq 1
        continue
    end

    set tmp (dirname "$f")/.(basename "$f").id3strip
    tail -c +(math $front + 1) "$f" | head -c (math $size - $front - $back) >"$tmp"
    chmod (stat -f %Lp "$f") "$tmp"
    if test (head -c 4 "$tmp") = fLaC; and test (stat -f %z "$tmp") -eq (math $size - $front - $back)
        mv -f -- "$tmp" "$f"
        set stripped (math $stripped + 1)
    else
        rm -f "$tmp"
        flac_err "  FAILED: the stripped copy didn't check out; original left as it was"
        set failed (math $failed + 1)
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Files with ID3 tags: $found"
echo "Stripped: $stripped"
echo "Failed: $failed"
test $failed -eq 0
