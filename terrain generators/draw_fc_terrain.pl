#!/usr/bin/perl -w
#
# Script to create svg file from 2d terrain data
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# several midifications by Dimitris Zorbas (jim/at/students/cs/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)

use GD::SVG;
use strict;

my ($display_x, $display_y) = (800, 800); # 800x800 pixel display pane

my (	$sensor_reading_radius, 
	$sensor_comm_radius,
	$base_x, $base_y, $norm_x, $norm_y) = (0, 0, 0, 0, 0, 0);

my @sensors = ();
my @targets = ();

die "usage: $0 <terrain_file.txt> <output.svg>\n" 
	unless (@ARGV == 2);

my $terrain_file = $ARGV[0];
my $output_file = $ARGV[1];


# COLLECT INFO FROM INPUT FILE

open(FH, "<$terrain_file") or 
	die "Error: could not open terrain file $terrain_file\n";

while(<FH>){
	chomp;
	if (/^# stats: (.*)/){
		my $stats_line = $1;
		my $one_pt_sz = 1;

		if ($stats_line =~ /sensor_sz=([0-9]+\.[0-9]+)m\^2/){
			$one_pt_sz = sqrt($1); 
		}
		if ($stats_line =~ /sensor_reading_radius=([0-9]+\.[0-9]+)m/){
			$sensor_reading_radius = $1 / $one_pt_sz;
		}
		if ($stats_line =~ /sensor_comm_radius=([0-9]+\.[0-9]+)m/){
			$sensor_comm_radius = $1 / $one_pt_sz;
		}
	} elsif (/^# base station coords: \[([0-9]+) ([0-9]+)\]/){
		($base_x, $base_y) = ($1, $2);	
	} elsif (/^# terrain map \[([0-9]+) x ([0-9]+)\]/){
		($norm_x, $norm_y) = ($1, $2);
	} elsif (/^# sensor coords: (.*)/){
		my $sens_coord = $1;
		my @coords = split(/\] /, $sens_coord);
		@sensors = map { /([0-9]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
	} elsif (/^# target coords: (.*)/){
		my $target_coord = $1;
		my @coords = split(/\] /, $target_coord);
		@targets = map { /([A-Z]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
	}
}
close(FH);


sub distance {
	my ($x1, $x2, $y1, $y2) = @_;

	return sqrt( (($x1-$x2)*($x1-$x2))
			+(($y1-$y2)*($y1-$y2)) );
}

### GENERATE SVG IMAGE OF TERRAIN ###

if ((scalar @targets) == 0){
	die "Error: no input targets to make image. bailing out...\n"; 
} else {
	my $im = new GD::SVG::Image($display_x, $display_y);
	my $white = $im->colorAllocate(255,255,255);
	my $blue = $im->colorAllocate(0,0,255);
	my $green = $im->colorAllocate(200,255,200);
	my $black = $im->colorAllocate(0,0,0);
	my $red = $im->colorAllocate(255,0,0);
	
	
	foreach my $sensor (@sensors){
		my ($s, $x, $y) = @$sensor;
		($x, $y) = (int(($x * $display_x)/ $norm_x), int(($y * $display_y)/ $norm_y));
		
		if (distance($x, ($base_x * $display_x)/$norm_x, $y, ($base_y * $display_y)/$norm_y) <= 
				(int(($sensor_comm_radius*$display_x)/$norm_x))){
			$im->line($x, $y, ($base_x * $display_x)/$norm_x, ($base_y * $display_y)/$norm_y, $green);
		}
		
		foreach my $sensor_t (@sensors){
			next if ($sensor == $sensor_t);
			my ($s_t, $x_t, $y_t) = @$sensor_t;
			($x_t, $y_t) = (int(($x_t * $display_x)/ $norm_x), int(($y_t * $display_y)/ $norm_y));
			if (distance($x_t, $x, $y_t, $y) <= (int(($sensor_comm_radius*$display_x)/$norm_x))){
				$im->line($x, $y, $x_t, $y_t, $green);
			}
		}
		
		$im->string(gdSmallFont,$x-2,$y-12,$s,$black);
		$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $black);
	}

	foreach my $target (@targets){
		my ($s, $x, $y) = @$target;
		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));

		$im->rectangle($x-5, $y-5, $x+5, $y+5, $red);
		$im->string(gdMediumBoldFont,$x-2,$y-20,$s,$blue); 
		$im->arc($x,$y, 
			2 * int(($sensor_reading_radius*$display_x)/$norm_x), 
			2 * int(($sensor_reading_radius*$display_y)/$norm_y), 
			0, 360, $red);
	}

	$im->filledRectangle( ($base_x * $display_x)/$norm_x-5, ($base_y * $display_y)/$norm_y-5,
			($base_x * $display_x)/$norm_x+5, ($base_y * $display_y)/$norm_y+5, $red);

	$im->arc(($base_x * $display_x)/$norm_x,
		($base_y * $display_y)/$norm_y,
		2 * int(($sensor_comm_radius * $display_x)/$norm_x),
		2 * int(($sensor_comm_radius * $display_y)/$norm_y),
		0, 360, $black);

	open(FILEOUT, ">$output_file") or 
		die "could not open file $output_file for writing!";
	binmode FILEOUT;
	print FILEOUT $im->svg;
	close FILEOUT;
}
