#!/usr/bin/env fish
# Recursively scans every directory under --path (default: current
# directory) that contains .flac files. In each one, finds cover.jpg/
# cover.jpeg/Folder.jpg/Folder.jpeg (any case, legacy "folder" naming
# included) and renames it to cover.jpg if needed, then embeds that image
# into every .flac file in the directory — skipping files that already
# have an embedded picture.
#
# Usage: ./flac-embed-cover-art.fish [--replace] [--dry-run] [--path=DIR] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-embed-cover-art.fish [--replace] [--dry-run] [--path=DIR] [--verbose] [--quiet]"
    echo "Recursively scans every directory containing .flac files, renames"
    echo "cover.jpg/Folder.jpg (any case) to cover.jpg if needed, and embeds"
    echo "it into every .flac file (skipping files that already have art)."
    echo
    echo "  --replace   Replace existing embedded art instead of skipping it."
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

if not type -q metaflac
    flac_err "Error: 'metaflac' not found. Install with: brew install flac"
    exit 1
end

set replace 0
if contains -- --replace $argv
    set replace 1
end

set dirs_processed 0
set dirs_no_cover 0
set files_embedded 0
set files_replaced 0
set files_skipped_has_art 0
set files_failed 0

for d in (flac_find_flac_dirs "$opt_path")
    set flacs $d/*.flac
    set count_flacs (count $flacs)
    if test $count_flacs -eq 0
        continue
    end

    flac_log "== $d ($count_flacs flac files) =="
    set dirs_processed (math "$dirs_processed + 1")

    set cover "$d/cover.jpg"

    if not test -f "$cover"
        # Look for a source image under another name/case to rename.
        set found (find -E "$d" -maxdepth 1 -type f -iregex '.*/(cover|folder)\.(jpg|jpeg)$')
        if test (count $found) -gt 0
            set src $found[1]
            flac_log "  Renaming: "(basename "$src")" -> cover.jpg"
            if test $opt_dry_run -eq 0
                mv "$src" "$cover"
            end
        else
            flac_log "  SKIP DIR: no cover.jpg/folder.jpg found in this directory"
            set dirs_no_cover (math "$dirs_no_cover + 1")
            continue
        end
    end

    for f in $flacs
        set fname (basename "$f")
        set has_art 0
        metaflac --list --block-type=PICTURE "$f" | grep -q .
        and set has_art 1

        if test $has_art -eq 1; and test $replace -eq 0
            flac_log_v "  SKIP: $fname (already has embedded art)"
            set files_skipped_has_art (math "$files_skipped_has_art + 1")
        else if test $opt_dry_run -eq 1
            if test $has_art -eq 1
                flac_log "  (dry run) Would replace: $fname"
                set files_replaced (math "$files_replaced + 1")
            else
                flac_log "  (dry run) Would embed: $fname"
                set files_embedded (math "$files_embedded + 1")
            end
        else
            if test $has_art -eq 1
                metaflac --remove --block-type=PICTURE "$f" 2>/dev/null
            end

            if metaflac --import-picture-from="$cover" "$f" 2>/dev/null
                if test $has_art -eq 1
                    flac_log "  REPLACED: $fname"
                    set files_replaced (math "$files_replaced + 1")
                else
                    flac_log "  EMBEDDED: $fname"
                    set files_embedded (math "$files_embedded + 1")
                end
            else
                flac_err "  FAILED: $fname (metaflac import error)"
                set files_failed (math "$files_failed + 1")
            end
        end
    end
end

echo
echo "== Summary =="
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Directories processed: $dirs_processed"
echo "Directories with no cover image: $dirs_no_cover"
echo "Files embedded: $files_embedded"
echo "Files replaced: $files_replaced"
echo "Files skipped (already had art): $files_skipped_has_art"
echo "Files failed: $files_failed"
