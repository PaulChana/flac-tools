#!/usr/bin/env fish
# Names tracks from MusicBrainz: renames files to "NN - Title.flac" and
# sets their TITLE tags, replacing any title already there.
#
# Recursively scans directories under --path (default: current directory).
# For each directory of .flac files, works out the artist/album from the
# folder names (walking up an extra level for "Disc N"/"CD N" subfolders),
# looks up the release on MusicBrainz and picks the first match whose disc
# has as many tracks as the folder has files. Each file is matched to a
# track by the number at the start of its name (or its TRACKNUMBER tag),
# then renamed and tagged. Albums with no release of the right length are
# skipped.
#
# Uses the free MusicBrainz API (rate-limited to ~1 request/sec, which
# this script respects).
#
# Requires: curl, jq (brew install jq), metaflac (brew install flac)
#
# Usage: ./flac-fill-track-names.fish [--no-rename] [--no-tags] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-fill-track-names.fish [--no-rename] [--no-tags] [--path=DIR]"
    echo "                                  [--dry-run] [--verbose] [--quiet]"
    echo "Looks up each album folder's Artist/Album on MusicBrainz, then renames"
    echo "its files to 'NN - Title.flac' and sets their TITLE tags. Files"
    echo "are matched to tracks by the number at the start of their name (or"
    echo "their TRACKNUMBER tag). Only releases with the same number of tracks"
    echo "as the folder has files are used; other albums are skipped."
    echo
    echo "  --no-rename   Don't rename files, only write tags."
    echo "  --no-tags     Don't write tags, only rename files."
    flac_common_help
    echo
    echo "Requires jq (brew install jq)."
    exit 0
end

flac_parse_common_args $argv

for cmd in jq metaflac curl
    if not type -q $cmd
        flac_err "Error: '$cmd' not found."
        exit 1
    end
end

set do_rename 1
contains -- --no-rename $argv; and set do_rename 0
set do_tags 1
contains -- --no-tags $argv; and set do_tags 0

if test $do_rename -eq 0; and test $do_tags -eq 0
    flac_err "Nothing to do: --no-rename and --no-tags were both given."
    exit 1
end

# Prints "id<TAB>medium<TAB>description" for the first release in a
# MusicBrainz search whose disc has $n tracks, preferring CD and digital
# releases (vinyl and cassette track lists are sometimes reordered). medium is the 1-based disc,
# or 0 when it's the whole release that has $n tracks (e.g. vinyl sides).
function pick_release
    set artist $argv[1]
    set album $argv[2]
    set n $argv[3]
    set disc $argv[4]

    set filter '[.releases[]? | . as $r | ($r.media // []) as $m |
        if $disc != "" then
            ($disc | tonumber) as $d |
            if ($m | length) >= $d and $m[$d - 1]["track-count"] == $n then {r: $r, medium: $d} else empty end
        else
            ([range(0; $m | length) | select($m[.]["track-count"] == $n)] | first) as $i |
            if $i != null then {r: $r, medium: ($i + 1)}
            elif $r["track-count"] == $n then {r: $r, medium: 0}
            else empty end
        end]
        | sort_by(if any(.r.media[]?; (.format // "") | test("CD|Digital")) then 0 else 1 end)
        | first // empty |
        "\(.r.id)\t\(.medium)\t\(.r.title) (\([.r.date, .r.country, (.r.media | map(.format // "?") | unique | join("+"))] | map(select(. != null and . != "")) | join(", ")))"'

    for strict in 1 0
        set q '"artist:\"" + $a + "\" AND release:\"" + $b + "\""'
        if test $strict -eq 1
            set q "$q"' + " AND primarytype:album AND status:official"'
        end
        set query (jq -rn --arg a "$artist" --arg b "$album" "$q | @uri")
        set url "https://musicbrainz.org/ws/2/release/?query=$query&fmt=json&limit=25"
        flac_log_v "  GET $url"
        set hit (curl -s --retry 3 --retry-delay 2 -A "$FLAC_MB_USER_AGENT" "$url" | jq -r --argjson n $n --arg disc "$disc" "$filter")
        sleep 1
        if test -n "$hit"
            echo $hit
            return
        end
    end
end

# Prints the track titles of one disc (or the whole release if medium is
# 0), one per line, in order.
function release_titles
    set id $argv[1]
    set medium $argv[2]
    set url "https://musicbrainz.org/ws/2/release/$id?inc=recordings&fmt=json"
    flac_log_v "  GET $url"
    curl -s --retry 3 --retry-delay 2 -A "$FLAC_MB_USER_AGENT" "$url" | jq -r --argjson m $medium \
        '(if $m == 0 then .media else [.media[$m - 1]] end) | [.[]?.tracks[]?] | .[].title'
    sleep 1
end

function straighten_quotes
    string replace -a -- '’' "'" $argv[1] | string replace -a -- '‘' "'" | string replace -a -- '“' '"' | string replace -a -- '”' '"'
end

# Makes a title safe as a file name, on macOS and on SMB/NAS shares.
function filename_safe
    string replace -a -- / - $argv[1] \
        | string replace -a -- : ' -' \
        | string replace -a -- '"' "'" \
        | string replace -ra -- '[?*<>|\\\\]' '' \
        | string replace -r -- '^\.+' '' \
        | string replace -ra -- '\s+' ' ' \
        | string trim
end

set albums_done 0
set albums_skipped 0
set renamed 0
set tagged 0

for d in (flac_find_flac_dirs "$opt_path")
    set files (flac_files_in "$d")
    set n (count $files)
    test $n -gt 0; or continue

    set album (flac_normalize_roman (flac_resolve_album_name "$d"))
    set artist (flac_resolve_artist_name "$d")
    set disc ""
    if flac_is_disc_subfolder "$d"
        set disc (string match -rg '([0-9]+)$' -- (basename "$d"))
        set disc (math $disc)
    end

    # Work out each file's track number before going online, so folders
    # that can't be matched up don't cost a lookup.
    set nums
    set bad ""
    for f in $files
        set num (string match -rg '^\s*([0-9]+)' -- (basename "$f"))
        if test -z "$num"
            set num (string match -rg '^\s*([0-9]+)' -- (flac_get_tag "$f" TRACKNUMBER))
        end
        if test -z "$num"
            set bad "no track number in '"(basename "$f")"'"
            break
        end
        set num (math $num)
        if test $num -lt 1; or test $num -gt $n
            set bad "track $num in '"(basename "$f")"' is outside 1-$n"
            break
        end
        if contains -- $num $nums
            set bad "track $num appears twice"
            break
        end
        set nums $nums $num
    end
    if test -n "$bad"
        flac_err "SKIP: $d ($bad)"
        set albums_skipped (math "$albums_skipped + 1")
        continue
    end

    set label "$artist - $album"
    test -n "$disc"; and set label "$label (disc $disc)"
    flac_log_v "Searching MusicBrainz: $label, $n tracks"

    set hit (pick_release "$artist" "$album" $n "$disc")
    if test -z "$hit"
        flac_log "NOT FOUND: $label (no release with $n tracks)"
        set albums_skipped (math "$albums_skipped + 1")
        continue
    end
    set parts (string split \t -- $hit)
    set release_id $parts[1]
    set medium $parts[2]

    set titles (release_titles $release_id $medium)
    if test (count $titles) -ne $n
        flac_log "NOT FOUND: $label (track list for $release_id has "(count $titles)" tracks, expected $n)"
        set albums_skipped (math "$albums_skipped + 1")
        continue
    end

    flac_log "$d/"
    flac_log "  MusicBrainz: $parts[3]  https://musicbrainz.org/release/$release_id"
    set albums_done (math "$albums_done + 1")

    set width 2
    test $n -ge 100; and set width 3

    for i in (seq $n)
        set f $files[$i]
        set num $nums[$i]
        set title (straighten_quotes "$titles[$num]")
        set base (basename "$f")

        if test $do_tags -eq 1
            set cur (flac_get_tag "$f" TITLE)
            if test "$cur" != "$title"
                flac_log "  $base  TITLE: '$cur' -> '$title'"
                flac_set_tag "$f" TITLE "$title"
                set tagged (math "$tagged + 1")
            end
        end

        if test $do_rename -eq 1
            set new (printf "%0*d" $width $num)" - "(filename_safe "$title")".flac"
            if test "$new" = "$base"
                flac_log_v "  $base  unchanged"
                continue
            end
            if test -e "$d/$new"; and test (string lower -- "$new") != (string lower -- "$base")
                flac_err "  Skipping $base: '$new' already exists"
                continue
            end
            flac_log "  '$base' -> '$new'"
            if test $opt_dry_run -ne 1
                mv -- "$f" "$d/$new"
            end
            set renamed (math "$renamed + 1")
        end
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Albums matched: $albums_done"
echo "Albums skipped: $albums_skipped"
echo "Files renamed:  $renamed"
echo "Titles set:     $tagged"
