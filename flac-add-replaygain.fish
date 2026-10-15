#!/usr/bin/env fish
# Computes ReplayGain for each album folder and adds the track and album
# gain tags.
#
# Recursively finds every folder of .flac files under --path (default:
# current directory) and computes ReplayGain for it with metaflac, adding
# REPLAYGAIN_TRACK_GAIN/PEAK and REPLAYGAIN_ALBUM_GAIN/PEAK tags. Each
# folder counts as one album (so each disc of a set gets its own album
# gain). Folders whose files all have ReplayGain already are skipped
# unless --force is passed. This decodes all the audio, so it's slow —
# especially over a network share.
#
# metaflac can only do an album whose files share a sample rate, bit depth
# and mono/stereo layout. For a folder that mixes them (say 44.1 and 48 kHz)
# it uses rsgain instead if it's installed (brew install rsgain), which
# writes ReplayGain 2.0 values (-18 LUFS reference, a few dB off metaflac's
# 89 dB). Without rsgain those folders get track gain only.
#
# Usage: ./flac-add-replaygain.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-add-replaygain.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively computes ReplayGain (track and album) for each folder of"
    echo ".flac files, treating each folder as one album. Decodes all the"
    echo "audio, so it takes a while."
    echo
    echo "  --force      Recompute folders that already have ReplayGain tags."
    echo
    echo "Folders mixing sample rates or bit depths need rsgain for album gain"
    echo "(brew install rsgain); without it they get track gain only."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set force 0
if contains -- --force $argv
    set force 1
end

set done_dirs 0
set skipped 0
set failed 0

for dir in (flac_find_flac_dirs "$opt_path")
    set files (flac_files_in "$dir")
    set -q files[1]; or continue

    if test $force -eq 0
        set missing 0
        for f in $files
            if test -z "$(flac_get_tag "$f" REPLAYGAIN_TRACK_GAIN)"
                set missing 1
                break
            end
        end
        if test $missing -eq 0
            flac_log_v "$dir  already has ReplayGain"
            set skipped (math "$skipped + 1")
            continue
        end
    end

    set formats (for f in $files
        echo (metaflac --show-sample-rate --show-channels --show-bps "$f" | string join /)
    end | sort -u)
    set channels (string split / -- $formats[1])[2]
    set how metaflac
    if test (count $formats) -gt 1; or test "$channels" -gt 2
        set why "its files mix formats ("(string join ', ' -- $formats)")"
        test "$channels" -gt 2; and set why "it has $channels-channel audio"
        if type -q rsgain
            set how rsgain
        else if test "$channels" -gt 2
            flac_err "Skipped $dir — $why, which needs rsgain (brew install rsgain)"
            set failed (math "$failed + 1")
            continue
        else
            set how "track gain only"
            flac_err "Warning: $dir — $why; adding track gain only (brew install rsgain for album gain, then rerun with --force)"
        end
    end

    set using ""
    test $how != metaflac; and set using " with $how"
    if test $opt_dry_run -eq 1
        flac_log "$dir  would compute ReplayGain for "(count $files)" files$using"
        set done_dirs (math "$done_dirs + 1")
        continue
    end

    flac_log "$dir  computing ReplayGain for "(count $files)" files$using…"
    set ok 1
    switch $how
        case metaflac
            metaflac --add-replay-gain $files; or set ok 0
        case rsgain
            metaflac --remove-tag=REPLAYGAIN_TRACK_GAIN --remove-tag=REPLAYGAIN_TRACK_PEAK \
                --remove-tag=REPLAYGAIN_ALBUM_GAIN --remove-tag=REPLAYGAIN_ALBUM_PEAK \
                --remove-tag=REPLAYGAIN_REFERENCE_LOUDNESS $files
            and rsgain custom --album --tagmode=i --quiet $files
            and metaflac --set-tag="REPLAYGAIN_REFERENCE_LOUDNESS=-18.00 LUFS" $files
            or set ok 0
        case "track gain only"
            for f in $files
                metaflac --add-replay-gain "$f"
                and metaflac --remove-tag=REPLAYGAIN_ALBUM_GAIN --remove-tag=REPLAYGAIN_ALBUM_PEAK "$f"
                or set ok 0
            end
    end

    if test $ok -eq 1
        set gain (flac_get_tag "$files[1]" REPLAYGAIN_ALBUM_GAIN)[1]
        test -n "$gain"; and flac_log "    album gain: $gain"
        or flac_log "    track gain only"
        set done_dirs (math "$done_dirs + 1")
    else
        flac_err "Couldn't compute ReplayGain for $dir"
        set failed (math "$failed + 1")
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Folders done: $done_dirs"
echo "Already had ReplayGain: $skipped"
echo "Skipped or failed: $failed"
