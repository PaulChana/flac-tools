#!/usr/bin/env fish
# Consolidated tag-filler, replacing the separate flac-fill-albumartist,
# flac-set-composer, flac-set-discnumber, flac-set-date, and
# flac-set-genre scripts. Each field is filled only where it's currently
# empty (unless --replace), and only if its flag is passed:
#
#   --albumartist   ALBUMARTIST <- ARTIST, Title Cased (per file, local)
#   --composer      COMPOSER <- ALBUMARTIST (per file, local)
#   --discnumber    DISCNUMBER <- 1, or N from a "Disc N"/"CD N" folder
#                   (per file, local)
#   --date          DATE <- MusicBrainz release-group first-release-date
#                   (per album, one API lookup pair per album)
#   --genre         GENRE <- MusicBrainz genre votes, aggregated across
#                   an artist's whole discography, with an interactive
#                   pick-one-of-3/custom/skip/stop prompt (per artist)
#   --all           Shorthand for --albumartist --composer --discnumber
#                   --date (NOT --genre, since that one is interactive
#                   and needs to be requested explicitly)
#
# Walks --path (default: current directory) as Artist/Album[/Disc N]/*.flac.
# --albumartist/--composer/--discnumber need no network access. --date and
# --genre use the free MusicBrainz API (rate-limited to ~1 req/sec, which
# this script respects) and need jq.
#
# Usage: ./flac-fill-tags.fish [--albumartist] [--composer] [--discnumber]
#                               [--date] [--genre] [--all]
#                               [--replace] [--dry-run] [--path=DIR]
#                               [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-fill-tags.fish [--albumartist] [--composer] [--discnumber] [--date] [--genre] [--all]"
    echo "                           [--replace] [--dry-run] [--path=DIR] [--verbose] [--quiet]"
    echo "Fills in missing FLAC tags. Nothing happens unless you pass at"
    echo "least one of these to choose what to fill:"
    echo
    echo "  --albumartist   ALBUMARTIST <- ARTIST (Title Cased). Per file,"
    echo "                  no network access."
    echo "  --composer      COMPOSER <- ALBUMARTIST. Per file, no network."
    echo "  --discnumber    DISCNUMBER <- 1, or N from a 'Disc N' folder."
    echo "                  Per file, no network."
    echo "  --date          DATE <- MusicBrainz initial release date. One"
    echo "                  lookup per album."
    echo "  --genre         GENRE <- MusicBrainz genre votes aggregated"
    echo "                  across an artist's whole discography, with an"
    echo "                  interactive prompt per artist (pick one of the"
    echo "                  top 3, type your own, skip, or stop the run)."
    echo "  --all           Shorthand for --albumartist --composer"
    echo "                  --discnumber --date (not --genre, since that's"
    echo "                  interactive and disruptive to run unasked)."
    echo
    flac_common_help
    echo "  --replace    Overwrite existing values too (default: only fill"
    echo "               where empty)."
    echo
    echo "Requires jq (brew install jq) for --date/--genre."
    exit 0
end

flac_parse_common_args $argv

set do_albumartist 0
set do_composer 0
set do_discnumber 0
set do_date 0
set do_genre 0

if contains -- --all $argv
    set do_albumartist 1
    set do_composer 1
    set do_discnumber 1
    set do_date 1
end
if contains -- --albumartist $argv
    set do_albumartist 1
end
if contains -- --composer $argv
    set do_composer 1
end
if contains -- --discnumber $argv
    set do_discnumber 1
end
if contains -- --date $argv
    set do_date 1
end
if contains -- --genre $argv
    set do_genre 1
end

set replace 0
if contains -- --replace $argv
    set replace 1
end

if test $do_albumartist -eq 0; and test $do_composer -eq 0; and test $do_discnumber -eq 0; and test $do_date -eq 0; and test $do_genre -eq 0
    flac_err "Nothing to do — pass at least one of --albumartist, --composer, --discnumber, --date, --genre, --all."
    exit 1
end

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

if test $do_date -eq 1; or test $do_genre -eq 1
    if not type -q jq
        flac_err "Error: 'jq' not found (needed for --date/--genre). Install with: brew install jq"
        exit 1
    end
end

# --- ALBUMARTIST title-casing (with stylized-name exceptions) -----------
function fill_title_case
    set exceptions \
        "AC/DC" \
        "will.i.am" \
        "iamamiwhoami" \
        "deadmau5" \
        "P!nk" \
        "Ke\$ha"

    set input $argv[1]

    for ex in $exceptions
        if test (string lower -- "$input") = (string lower -- "$ex")
            echo $ex
            return
        end
    end

    set words (string split ' ' -- $input)
    set result
    for w in $words
        if test -n "$w"
            set first (string sub -l 1 -- $w | string upper)
            set rest (string sub -s 2 -- $w | string lower)
            set result $result "$first$rest"
        else
            set result $result ""
        end
    end
    string join ' ' -- $result
end

# --- MusicBrainz: DATE ------------------------------------------------
function lookup_release_date
    set artist $argv[1]
    set album $argv[2]

    set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND releasegroup:\"" + $b + "\" AND primarytype:album" | @uri')
    set url "https://musicbrainz.org/ws/2/release-group/?query=$query&fmt=json&limit=1"
    set date (curl -s -A "$FLAC_MB_USER_AGENT" "$url" | jq -r '.["release-groups"][0]["first-release-date"] // empty')

    if test -z "$date"
        set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND releasegroup:\"" + $b + "\"" | @uri')
        set url "https://musicbrainz.org/ws/2/release-group/?query=$query&fmt=json&limit=1"
        set date (curl -s -A "$FLAC_MB_USER_AGENT" "$url" | jq -r '.["release-groups"][0]["first-release-date"] // empty')
    end

    sleep 1
    echo $date
end

# --- MusicBrainz: GENRE -------------------------------------------------
function lookup_album_genres
    set artist $argv[1]
    set album $argv[2]

    set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND releasegroup:\"" + $b + "\" AND primarytype:album" | @uri')
    set url "https://musicbrainz.org/ws/2/release-group/?query=$query&fmt=json&limit=1"
    set rgid (curl -s -A "$FLAC_MB_USER_AGENT" "$url" | jq -r '.["release-groups"][0].id // empty')

    if test -z "$rgid"
        set query (jq -rn --arg a "$artist" --arg b "$album" '"artist:\"" + $a + "\" AND releasegroup:\"" + $b + "\"" | @uri')
        set url "https://musicbrainz.org/ws/2/release-group/?query=$query&fmt=json&limit=1"
        set rgid (curl -s -A "$FLAC_MB_USER_AGENT" "$url" | jq -r '.["release-groups"][0].id // empty')
    end

    sleep 1

    if test -z "$rgid"
        return
    end

    set lookup_url "https://musicbrainz.org/ws/2/release-group/$rgid?inc=genres&fmt=json"
    curl -s -A "$FLAC_MB_USER_AGENT" "$lookup_url" | jq -r '(.genres // [])[] | "\(.name)\t\(.count)"'
    sleep 1
end

function apply_genre_to_files
    set chosen $argv[1]
    set files $argv[2..-1]
    set n 0
    for f in $files
        set cur (flac_get_tag "$f" GENRE)
        if test -n "$cur"; and test $replace -eq 0
            continue
        end
        flac_set_tag "$f" GENRE "$chosen"
        set n (math "$n + 1")
    end
    echo $n
end

# --- Main walk: artist -> album -> file ---------------------------------
set stopped 0

for artist_dir in $opt_path/*/
    if test $stopped -eq 1
        break
    end

    set artist_name (string trim -r -c / -- (basename "$artist_dir"))
    set flac_dirs (flac_find_flac_dirs "$artist_dir")
    if test (count $flac_dirs) -eq 0
        continue
    end

    # --- GENRE: needs the whole artist's discography aggregated first ---
    if test $do_genre -eq 1
        set albums
        for d in $flac_dirs
            set album (flac_normalize_roman (flac_resolve_album_name "$d"))
            if not contains -- "$album" $albums
                set albums $albums "$album"
            end
        end

        flac_log "== $artist_name ("(count $albums)" album(s)) =="

        set agg_names
        set agg_counts
        for album in $albums
            flac_log_v "  Looking up genres: $artist_name - $album"
            for line in (lookup_album_genres "$artist_name" "$album")
                set name (string split -m1 \t -- $line)[1]
                set cnt (string split -m1 \t -- $line)[2]
                set idx (contains -i -- "$name" $agg_names)
                if test -n "$idx"
                    set agg_counts[$idx] (math "$agg_counts[$idx] + $cnt")
                else
                    set agg_names $agg_names "$name"
                    set agg_counts $agg_counts $cnt
                end
            end
        end

        set all_flac_files
        for d in $flac_dirs
            set all_flac_files $all_flac_files $d/*.flac
        end

        if test (count $agg_names) -eq 0
            echo "  No genre data found on MusicBrainz for this artist."
            read -P "  Enter a genre to use (blank to skip): " manual
            if test -n "$manual"
                echo "  Applying GENRE: $manual"
                set n (apply_genre_to_files "$manual" $all_flac_files)
                if test $opt_dry_run -eq 1
                    echo "  (dry run) Would have set $n file(s)."
                else
                    echo "  Set $n file(s)."
                end
                read -P "  Stop here? (y/N): " stop_ans
                if string match -riq 'y*' -- "$stop_ans"
                    set stopped 1
                end
            else
                echo "  Skipped."
            end
            echo
        else
            set ranked (for i in (seq (count $agg_names)); echo "$agg_counts[$i]:$agg_names[$i]"; end | sort -t: -k1,1nr)
            set top_n (math "min(3, "(count $ranked)")")
            set top (for line in $ranked[1..$top_n]; string split -m1 : -- $line | tail -1; end)

            echo "  Pick a genre for all of $artist_name's albums:"
            for i in (seq (count $top))
                echo "    $i) $top[$i]"
            end
            echo "    c) Enter your own"
            echo "    s) Skip this artist"
            read -P "  > " choice

            set chosen ""
            if test "$choice" = "s"
                echo "  Skipped."
            else if test "$choice" = "c"
                read -P "  Enter genre: " custom
                if test -n "$custom"
                    set chosen "$custom"
                else
                    echo "  Skipped."
                end
            else if string match -rq '^[0-9]+$' -- "$choice"; and test "$choice" -ge 1; and test "$choice" -le (count $top)
                set chosen $top[$choice]
            else
                echo "  Invalid choice, skipping this artist."
            end

            if test -n "$chosen"
                echo "  Applying GENRE: $chosen"
                set n (apply_genre_to_files "$chosen" $all_flac_files)
                if test $opt_dry_run -eq 1
                    echo "  (dry run) Would have set $n file(s)."
                else
                    echo "  Set $n file(s)."
                end
                read -P "  Stop here? (y/N): " stop_ans
                if string match -riq 'y*' -- "$stop_ans"
                    set stopped 1
                end
            end
            echo
        end
    end

    if test $stopped -eq 1
        break
    end

    # --- Per-album work: DATE ---------------------------------------
    set seen_albums
    for d in $flac_dirs
        set album (flac_normalize_roman (flac_resolve_album_name "$d"))
        set album_date ""

        if test $do_date -eq 1; and not contains -- "$album" $seen_albums
            set seen_albums $seen_albums "$album"
            flac_log_v "  Looking up date: $artist_name - $album"
            set album_date (lookup_release_date "$artist_name" "$album")
            if test -z "$album_date"
                flac_log "$d -> DATE: not found on MusicBrainz"
            else
                flac_log "$d -> DATE: $album_date"
            end
        end

        # --- Per-file work: ALBUMARTIST, COMPOSER, DISCNUMBER, DATE ---
        for f in $d/*.flac
            if test $do_albumartist -eq 1
                set cur (flac_get_tag "$f" ALBUMARTIST)
                if test -z "$cur"; or test $replace -eq 1
                    set src (flac_get_tag "$f" ARTIST)
                    if test -n "$src"
                        set new (fill_title_case "$src")
                        flac_log "$f  ALBUMARTIST: '$cur' -> '$new'"
                        flac_set_tag "$f" ALBUMARTIST "$new"
                    end
                end
            end

            if test $do_composer -eq 1
                set cur (flac_get_tag "$f" COMPOSER)
                if test -z "$cur"; or test $replace -eq 1
                    set src (flac_get_tag "$f" ALBUMARTIST)
                    if test -n "$src"
                        flac_log "$f  COMPOSER: '$cur' -> '$src'"
                        flac_set_tag "$f" COMPOSER "$src"
                    end
                end
            end

            if test $do_discnumber -eq 1
                set cur (flac_get_tag "$f" DISCNUMBER)
                if test -z "$cur"; or test $replace -eq 1
                    set discnum 1
                    set m (string match -rg '^(?:disc|cd|disk) ?([0-9]+)$' -- (string lower (basename "$d")))
                    if test -n "$m"
                        set discnum $m
                    end
                    flac_log "$f  DISCNUMBER: '$cur' -> '$discnum'"
                    flac_set_tag "$f" DISCNUMBER "$discnum"
                end
            end

            if test $do_date -eq 1; and test -n "$album_date"
                set cur (flac_get_tag "$f" DATE)
                if test -z "$cur"; or test $replace -eq 1
                    flac_set_tag "$f" DATE "$album_date"
                end
            end
        end
    end
end

echo "Done."
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
