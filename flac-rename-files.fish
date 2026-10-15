#!/usr/bin/env fish
# Renames .flac files by removing, replacing or trimming text in their
# names.
#
# Recursively renames .flac files under --path (default: current
# directory) by editing their names. All edits act on the name without
# its extension, so ".flac" is never touched, and are applied in this
# order: strip from start, strip from end, remove, replace. Files whose
# new name already exists, or would be empty, are skipped.
#
# Usage: ./flac-rename-files.fish [--remove=TEXT] [--replace=TEXT] [--with=TEXT] [--regex] [--strip-start=N] [--strip-end=N] [--all-files] [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-rename-files.fish [--remove=TEXT] [--replace=TEXT] [--with=TEXT] [--regex]"
    echo "                              [--strip-start=N] [--strip-end=N] [--all-files]"
    echo "                              [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively renames .flac files by editing their names. Edits apply"
    echo "to the name without its extension, in the order listed below."
    echo
    echo "  --strip-start=N   Remove the first N characters."
    echo "  --strip-end=N     Remove the last N characters."
    echo "  --remove=TEXT     Remove every occurrence of TEXT."
    echo "  --replace=TEXT    Replace every occurrence of TEXT with the"
    echo "  --with=TEXT       --with text (empty if not given)."
    echo "  --regex           Treat --remove and --replace as regular"
    echo "                    expressions; --with can use \$1, \$2 for groups."
    echo "  --all-files       Rename every file, not just .flac files."
    echo
    flac_common_help
    echo
    echo "Example: flac-rename-files.fish --strip-start=3 --dry-run"
    echo "Example: flac-rename-files.fish --regex --replace='^(\d+)\. ' --with='\$1 - '"
    exit 0
end

flac_parse_common_args $argv

set remove ""
set replace ""
set with ""
set strip_start 0
set strip_end 0
set use_regex 0
set all_files 0
for a in $argv
    switch $a
        case '--remove=*'
            set remove (string replace -- '--remove=' '' $a)
        case '--replace=*'
            set replace (string replace -- '--replace=' '' $a)
        case '--with=*'
            set with (string replace -- '--with=' '' $a)
        case '--strip-start=*'
            set strip_start (string replace -- '--strip-start=' '' $a)
        case '--strip-end=*'
            set strip_end (string replace -- '--strip-end=' '' $a)
        case --regex
            set use_regex 1
        case --all-files
            set all_files 1
    end
end

for n in $strip_start $strip_end
    if not string match -qr '^[0-9]+$' -- $n
        flac_err "Error: --strip-start/--strip-end need a whole number, got '$n'."
        exit 1
    end
end

if test -z "$remove"; and test -z "$replace"; and test $strip_start -eq 0; and test $strip_end -eq 0
    flac_err "Error: nothing to do. Pass at least one of --remove, --replace,"
    flac_err "--strip-start or --strip-end (see --help)."
    exit 1
end

set regex_flag
if test $use_regex -eq 1
    set regex_flag -r
    for p in $remove $replace
        test -n "$p"; or continue
        string match -qr -- $p "" 2>/dev/null
        if test $status -eq 2
            flac_err "Error: invalid regex '$p'."
            exit 1
        end
    end
end

set name_filter -iname '*.flac'
if test $all_files -eq 1
    set name_filter
end

set renamed 0
set skipped 0

for f in (find "$opt_path" -type f $name_filter -not -name '.*' | sort)
    set dir (dirname "$f")
    set base (basename "$f")
    set ext (string match -r -- '\.[^.]+$' $base)
    set stem (string replace -r -- '\.[^.]+$' '' $base)

    if test $strip_start -gt 0
        set stem (string sub -s (math "$strip_start + 1") -- "$stem")
    end
    if test $strip_end -gt 0
        set keep (math "max(0, "(string length -- "$stem")" - $strip_end)")
        set stem (string sub -l $keep -- "$stem")
    end
    if test -n "$remove"
        set stem (string replace -a $regex_flag -- $remove '' "$stem")
    end
    if test -n "$replace"
        set stem (string replace -a $regex_flag -- $replace "$with" "$stem")
    end

    set new "$stem$ext"
    if test "$new" = "$base"
        flac_log_v "$f  unchanged"
        continue
    end
    if test -z "$stem"
        flac_err "Skipping $f: new name would be empty"
        set skipped (math "$skipped + 1")
        continue
    end
    if test -e "$dir/$new"; and test (string lower -- "$new") != (string lower -- "$base")
        flac_err "Skipping $f: '$new' already exists"
        set skipped (math "$skipped + 1")
        continue
    end

    flac_log "$dir/"
    flac_log "  '$base' -> '$new'"
    if test $opt_dry_run -ne 1
        mv -- "$f" "$dir/$new"
    end
    set renamed (math "$renamed + 1")
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Renamed: $renamed"
echo "Skipped: $skipped"
