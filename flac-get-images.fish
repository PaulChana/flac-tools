#!/usr/bin/env fish
# Recursively scans directories under --path (default: current directory).
# For any directory containing .flac files with no existing cover.jpg,
# works out the artist/album (walking up an extra level for "Disc 1"/
# "CD 2" style multi-disc subfolders, and correcting scene-rip roman
# numerals typed with lowercase L instead of uppercase I), looks up the
# release on MusicBrainz, and downloads the front cover from the Cover
# Art Archive as cover.jpg — rejecting anything under 500px on either side.
#
# Uses the MusicBrainz/Cover Art Archive public APIs — free, no API key,
# but rate-limited to ~1 request/sec, which this script respects.
#
# Requires: curl, jq (brew install jq), sips (built into macOS)
#
# Usage: ./flac-get-images.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-get-images.fish [--force] [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively scans directories with .flac files, looks up Artist/"
    echo "Album on MusicBrainz (handling multi-disc 'Disc N' subfolders and"
    echo "lowercase-L roman numerals) and downloads the front cover from"
    echo "the Cover Art Archive as cover.jpg. Rejects anything under 500px"
    echo "on either side."
    echo
    echo "  --force   Overwrite cover.jpg even if one already exists."
    flac_common_help
    echo
    echo "Requires jq (brew install jq)."
    exit 0
end

flac_parse_common_args $argv

if not type -q jq
    flac_err "Error: 'jq' not found. Install with: brew install jq"
    exit 1
end

set force 0
if contains -- --force $argv
    set force 1
end

set min_dimension 500
# "Square" means close enough a human wouldn't notice — a scan 1-2% off
# is just imprecise cropping, not a real problem.
set square_tolerance_pct 2

for d in (flac_find_flac_dirs "$opt_path")
    set flacs $d/*.flac
    if test (count $flacs) -gt 0
        set cover "$d/cover.jpg"

        if test -f "$cover"; and test $force -eq 0
            flac_log_v "SKIP (exists): $d"
            continue
        end

        set album (flac_normalize_roman (flac_resolve_album_name "$d"))
        set artist (flac_resolve_artist_name "$d")

        # Query the release entity (not release-group) filtered to official
        # albums. Pull several candidates (limit=5), not just one — there
        # are often many official editions (original pressing, remaster,
        # regional variant) of a famous album, and only some of them have
        # art actually uploaded to the Cover Art Archive, so the single
        # top search hit can easily be one that has none.
        flac_log_v "Searching MusicBrainz: $artist - $album"
        set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND release:\"" + $b + "\" AND primarytype:album AND status:official" | @uri')
        set search_url "https://musicbrainz.org/ws/2/release/?query=$query&fmt=json&limit=5"

        set release_ids (curl -s -A "$FLAC_MB_USER_AGENT" "$search_url" | jq -r '.releases[]?.id')

        # Fall back to an unfiltered search if the strict one finds nothing
        # (some releases are tagged inconsistently).
        if test (count $release_ids) -eq 0
            set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND release:\"" + $b + "\"" | @uri')
            set search_url "https://musicbrainz.org/ws/2/release/?query=$query&fmt=json&limit=5"
            set release_ids (curl -s -A "$FLAC_MB_USER_AGENT" "$search_url" | jq -r '.releases[]?.id')
        end

        sleep 1

        if test (count $release_ids) -eq 0
            flac_log "NOT FOUND: $artist - $album"
            continue
        end

        if test $opt_dry_run -eq 1
            flac_log "(dry run) Would download cover art for: $d"
            continue
        end

        set got_art 0
        for release_id in $release_ids
            set art_url "https://coverartarchive.org/release/$release_id/front"
            if curl -sL -f -A "$FLAC_MB_USER_AGENT" -o "$cover" "$art_url"
                set got_art 1
                break
            end
        end

        if test $got_art -eq 1
            set width (sips -g pixelWidth "$cover" | tail -1 | string trim | string replace 'pixelWidth: ' '')
            set height (sips -g pixelHeight "$cover" | tail -1 | string trim | string replace 'pixelHeight: ' '')

            if test "$width" -lt $min_dimension; or test "$height" -lt $min_dimension
                flac_log "TOO SMALL: $d ($width x $height, min is $min_dimension) — removed"
                rm -f "$cover"
            else
                set diff (math "abs($width - $height)")
                set maxdim (math "max($width, $height)")
                set pct (math "$diff / $maxdim * 100")
                if test $pct -gt $square_tolerance_pct
                    flac_log "DOWNLOADED BUT NOT SQUARE: $d ($width x $height, "(math "round($pct * 10) / 10")"% off) — check manually"
                else
                    flac_log "OK: $d ($width x $height)"
                end
            end
        else
            flac_log "NO COVER ART: $artist - $album"
            rm -f "$cover"
        end

        sleep 1
    end
end
