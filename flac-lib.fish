# flac-lib.fish — shared functions for the flac-*.fish toolkit.
# Not a standalone script: sourced by the other scripts via
#   source (dirname (status --current-filename))/flac-lib.fish
# Must live in the same directory as the scripts that use it.

# --- Common flag parsing -----------------------------------------------
# Sets these globals from $argv: opt_path, opt_dry_run, opt_verbose,
# opt_quiet. Does NOT consume --help (each script owns its own help text
# since the flags differ) or remove recognized flags from $argv — callers
# should test $argv themselves for script-specific flags.
function flac_parse_common_args
    set -g opt_path "."
    set -g opt_dry_run 0
    set -g opt_verbose 0
    set -g opt_quiet 0

    for a in $argv
        if string match -q '--path=*' -- $a
            set -g opt_path (string replace '--path=' '' -- $a)
        end
    end

    if contains -- --dry-run $argv
        set -g opt_dry_run 1
    end
    if contains -- --verbose $argv
        set -g opt_verbose 1
    end
    if contains -- --quiet $argv
        set -g opt_quiet 1
    end

    if not test -d "$opt_path"
        flac_err "Path not found: $opt_path"
        exit 1
    end
end

# The --path/--dry-run/--verbose/--quiet block for --help output. Callers
# echo this after their own script-specific flags.
function flac_common_help
    echo "  --path=DIR   Operate under DIR instead of the current directory."
    echo "  --dry-run    Print what would change without writing anything."
    echo "  --verbose    Print extra detail (queries made, per-check results)."
    echo "  --quiet      Suppress per-item output; only warnings and the"
    echo "               final summary are shown."
end

# --- Logging (respects --quiet / --verbose) ------------------------------
# Normal per-item output — suppressed by --quiet.
function flac_log
    if test "$opt_quiet" != 1
        echo $argv
    end
end

# Extra detail — only shown with --verbose (and not suppressed by --quiet
# being off; if both are passed, --quiet wins).
function flac_log_v
    if test "$opt_verbose" = 1; and test "$opt_quiet" != 1
        echo $argv
    end
end

# Errors/warnings — always shown, even in --quiet mode.
function flac_err
    echo $argv >&2
end

# --- Tag helpers ----------------------------------------------------------
# Reads TAG from FILE, stripped of the "KEY=" prefix regardless of the
# case metaflac stored the key name in.
function flac_get_tag
    set file $argv[1]
    set tag $argv[2]
    metaflac --show-tag=$tag "$file" | string replace -r '^[^=]*=' ''
end

# Sets TAG=VALUE on FILE, replacing any existing value. Respects
# $opt_dry_run (does nothing but the caller is still responsible for its
# own dry-run logging).
function flac_set_tag
    set file $argv[1]
    set tag $argv[2]
    set value $argv[3]
    if test "$opt_dry_run" != 1
        metaflac --remove-tag=$tag "$file"
        metaflac --set-tag=$tag="$value" "$file"
    end
end

# --- Roman numeral fix ------------------------------------------------
# Fixes album names where roman numerals were typed with lowercase L
# instead of uppercase I (e.g. "lll" instead of "III") — a common
# scene-rip naming quirk that breaks MusicBrainz lookups.
function flac_normalize_roman
    set album $argv[1]
    set last_word (string split ' ' -- $album)[-1]
    if string match -rq '^[lvLV]{1,5}$' -- "$last_word"
        set fixed (string upper "$last_word" | string replace -a 'L' 'I')
        set album (string replace -r "$last_word\$" "$fixed" -- "$album")
    end
    echo $album
end

# --- Folder-structure resolution ---------------------------------------
# Given a flac-containing directory, resolves it to the album name,
# walking up one extra level if the directory itself looks like a
# "Disc N"/"CD N"/"Disk N" subfolder.
function flac_resolve_album_name
    set dir $argv[1]
    set leaf (basename "$dir")
    if string match -rq '^(disc|cd|disk) ?[0-9]+$' -- (string lower "$leaf")
        basename (dirname "$dir")
    else
        echo "$leaf"
    end
end

# Given a flac-containing directory, resolves the artist name (one level
# up from the album, or two levels up if it's a Disc N subfolder).
function flac_resolve_artist_name
    set dir $argv[1]
    set leaf (basename "$dir")
    if string match -rq '^(disc|cd|disk) ?[0-9]+$' -- (string lower "$leaf")
        basename (dirname (dirname "$dir"))
    else
        basename (dirname "$dir")
    end
end

# True (exit 0) if the leaf directory name looks like a "Disc N"/"CD N"
# subfolder.
function flac_is_disc_subfolder
    set leaf (basename "$argv[1]")
    string match -rq '^(disc|cd|disk) ?[0-9]+$' -- (string lower "$leaf")
end

# --- Discovery ------------------------------------------------------------
# Every unique directory under DIR that directly contains .flac files,
# sorted.
function flac_find_flac_dirs
    set dir $argv[1]
    find "$dir" -type f -iname '*.flac' -exec dirname {} \; | sort -u
end

# --- MusicBrainz ------------------------------------------------------
set -g FLAC_MB_USER_AGENT "flac-toolkit.fish/1.0 (paulchana homelab scripts)"
