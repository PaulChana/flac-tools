#!/usr/bin/env fish
# Finds the albums in an MP3 library that you also have in a FLAC library,
# and prints a shell script that moves those MP3 albums out of the way into
# a subfolder of the MP3 library (default: _duplicates-of-flac), keeping
# their Artist/Album layout. Nothing is moved until you run that script.
#
# Both libraries are read as Artist/Album folders. Names are compared
# ignoring case, accents, punctuation, a leading "The", and extras such as
# "(1999)", "[FLAC]", "(320kbps)" or "1999 - " in front. Albums that look
# close but don't match exactly (one name containing the other, under the
# same artist) are listed at the end of the script as commented-out moves,
# for you to check and uncomment.
#
# A summary goes to stderr, so redirecting stdout gives a clean script.
#
# Usage: ./mp3-albums-with-flac.fish FLAC_DIR MP3_DIR [--into=NAME] > moves.sh

if contains -- --help $argv; or contains -- -h $argv
    echo "Usage: mp3-albums-with-flac.fish FLAC_DIR MP3_DIR [--into=NAME] > moves.sh"
    echo "Prints a script that moves the MP3 albums you also have as FLAC into"
    echo "MP3_DIR/NAME, keeping Artist/Album folders. Review it, then run it"
    echo "with: sh moves.sh"
    echo
    echo "  --into=NAME  Folder inside MP3_DIR to move them to"
    echo "               (default: _duplicates-of-flac)."
    exit 0
end

set into _duplicates-of-flac
for a in $argv
    if string match -q -- '--into=*' $a
        set into (string replace -- '--into=' '' $a)
    end
end
set dirs (string match -v -- '--*' $argv)
if test (count $dirs) -ne 2
    echo "Usage: mp3-albums-with-flac.fish FLAC_DIR MP3_DIR [--into=NAME] > moves.sh" >&2
    exit 1
end
set flac_dir (string trim -r -c / -- $dirs[1])
set mp3_dir (string trim -r -c / -- $dirs[2])
for d in $flac_dir $mp3_dir
    if not test -d "$d"
        echo "Not a folder: $d" >&2
        exit 1
    end
end
if string match -q -- '*/*' $into; or test -z "$into"
    echo "--into should be a single folder name, not a path" >&2
    exit 1
end

set program '
use strict; use warnings; use Unicode::Normalize;
my ($flac_root, $mp3_root, $dest) = @ARGV[0..2];
@ARGV = ();
my $Q = chr(39);
sub shq { my $s = shift; $s =~ s/$Q/$Q"$Q"$Q/g; return "$Q$s$Q" }
sub norm {
    my $s = NFD(shift);
    $s =~ s/\p{Mn}//g;
    $s = lc $s;
    $s =~ s/\[[^\]]*\]|\{[^}]*\}/ /g;
    $s =~ s{\(([^)]*)\)}{ $1 =~ /\b(?:19|20)\d\d\b|\b(?:flac|mp3|aac|ogg|lossless|\d+\s*kbps|320|256|192|v0|v2|vbr|cbr|web|vinyl|\d+\s*bit|remaster(?:ed)?)\b/ ? " " : " $1 " }ge;
    $s =~ s/^\s*(?:19|20)\d\d\s*-\s*//;
    $s =~ s/\s+-\s*(?:19|20)\d\d\s*$//;
    $s =~ s/&/ and /g;
    $s =~ s/^\s*the\s+//;
    $s =~ s/[^a-z0-9]+//g;
    return $s;
}

my (%flac, @mp3, $flac_count);
while (my $line = <STDIN>) {
    chomp $line;
    my ($side, $path) = split /\t/, $line, 2;
    my $root = $side eq "F" ? $flac_root : $mp3_root;
    my $rel = substr($path, length($root) + 1);
    my ($artist, $album) = split m{/}, $rel, 2;
    my ($ak, $bk) = (norm($artist), norm($album));
    next if $ak eq "" || $bk eq "";
    if ($side eq "F") { $flac{$ak}{$bk} = $rel; $flac_count++ }
    else { push @mp3, [$path, $artist, $album, $ak, $bk] }
}

my (@matches, @near);
for my $m (sort { $a->[0] cmp $b->[0] } @mp3) {
    my ($path, $artist, $album, $ak, $bk) = @$m;
    my $albums = $flac{$ak} or next;
    if (my $rel = $albums->{$bk}) { push @matches, [$m, $rel]; next }
    for my $fk (sort keys %$albums) {
        my ($short, $long) = length($fk) < length($bk) ? ($fk, $bk) : ($bk, $fk);
        if (length($short) >= 4 && index($long, $short) >= 0) { push @near, [$m, $albums->{$fk}]; last }
    }
}

sub moves {
    my ($list, $prefix) = @_;
    my $last = "";
    for (@$list) {
        my ($m, $rel) = @$_;
        my ($path, $artist) = @{$m}[0, 1];
        print "# Similar FLAC album: $rel\n" if $prefix;
        if ($artist ne $last || $prefix) { print $prefix, "mkdir -p ", shq("$dest/$artist"), "\n"; $last = $artist }
        print $prefix, "mv -n ", shq($path), " ", shq("$dest/$artist/"), "\n";
    }
}

print "#!/bin/sh\n";
print "# MP3 albums that are also in the FLAC library, moved into $dest\n";
print "# FLAC: $flac_root\n# MP3:  $mp3_root\n";
print "# Review, then run with: sh this-file.sh\n";
print "# mv -n never overwrites: an album already in the destination is left where it is.\n\n";
moves(\@matches, "");
if (@near) {
    print "\n# --- Near misses: similar names under the same artist. Uncomment the ones that are the same album. ---\n";
    moves(\@near, "# ");
}
printf STDERR "FLAC albums: %d\nMP3 albums:  %d\nMatched:     %d\nNear misses: %d (commented out)\n",
    $flac_count // 0, scalar @mp3, scalar @matches, scalar @near;
'

begin
    find "$flac_dir" -mindepth 2 -maxdepth 2 -type d -not -path '*/.*' | string replace -r '^' F\t
    find "$mp3_dir" -mindepth 2 -maxdepth 2 -type d -not -path '*/.*' -not -path "$mp3_dir/$into/*" \
        | string replace -r '^' M\t
end | perl -CSDA -e "$program" "$flac_dir" "$mp3_dir" "$mp3_dir/$into"
