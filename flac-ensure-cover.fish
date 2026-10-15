#!/usr/bin/env fish
# Turns a folder.jpg or front.jpg into cover.jpg in every album folder.
#
# Recursively finds every folder.jpg and front.jpg (or .jpeg, or .png)
# under --path (default: current directory) and makes it cover.jpg: JPEGs
# are renamed, PNGs converted to JPEG with sips and then removed. Skips
# any directory that already has a cover.jpg (flags it rather than
# overwriting). Where a directory has several, the first of folder.jpg,
# folder.jpeg, front.jpg, front.jpeg, folder.png, front.png wins and the
# rest are flagged and left in place.
#
# Usage: ./flac-ensure-cover.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]

set script_dir (dirname (status --current-filename))
source "$script_dir/flac-lib.fish"

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: flac-ensure-cover.fish [--path=DIR] [--dry-run] [--verbose] [--quiet]"
    echo "Recursively turns every folder.jpg and front.jpg (or .jpeg, or .png)"
    echo "into cover.jpg: JPEGs are renamed, PNGs converted to JPEG."
    echo "Flags (does not overwrite) any directory that already has a cover.jpg;"
    echo "where several exist, folder beats front and JPEG beats PNG."
    echo
    flac_common_help
    exit 0
end

flac_parse_common_args $argv

set renamed 0
set conflicts 0
set claimed

set candidates
for n in folder.jpg folder.jpeg front.jpg front.jpeg folder.png front.png
    set -a candidates (find "$opt_path" -type f -iname $n)
end

for f in $candidates
    set d (dirname "$f")
    set dest "$d/cover.jpg"
    set name (basename "$f")

    if test -f "$dest"; or contains -- "$d" $claimed
        flac_log "CONFLICT: $d already has cover.jpg — $name left in place"
        set conflicts (math "$conflicts + 1")
    else
        if string match -qi '*.png' -- "$f"
            if test $opt_dry_run -eq 1
                flac_log "Converted: $f -> $dest"
            else
                set tmp (mktemp -d -t flac-cover)
                if sips -s format jpeg -s formatOptions 92 "$f" --out "$tmp/cover.jpg" >/dev/null
                    and cp -X "$tmp/cover.jpg" "$dest"
                    rm "$f"
                    flac_log "Converted: $f -> $dest"
                else
                    flac_err "Couldn't convert $f to JPEG — left in place"
                    rm -rf "$tmp"
                    continue
                end
                rm -rf "$tmp"
            end
        else
            flac_log "Renamed: $f -> $dest"
            if test $opt_dry_run -eq 0
                mv "$f" "$dest"
            end
        end
        set -a claimed "$d"
        set renamed (math "$renamed + 1")
    end
end

echo
if test $opt_dry_run -eq 1
    echo "(dry run — no files were changed)"
end
echo "Renamed or converted: $renamed"
echo "Conflicts (cover.jpg already there): $conflicts"
