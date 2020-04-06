#!/usr/bin/perl -w
#
# Script to show a 2d terrain in gnuplot
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)

use File::Temp qw ( tempfile );

my $favorite_png_viewer = "gwenview";
my $terrain_maker = "./draw_terrain_2d.pl";

die "usage: $0 <terrain_file.txt>\n" unless (@ARGV == 1);

my $terrain = $ARGV[0];

my ($fh, $tmpfile) = 
	tempfile("show_terrainXXXXXX", SUFFIX => '.svg', DIR => '/tmp');

`$terrain_maker $terrain $tmpfile`;

`$favorite_png_viewer $tmpfile`;

unlink($tmpfile);
