#!/usr/bin/perl -w
#
# Script to generate gnuplot instructions for drawing a 3d terrain
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)


use strict;
use File::Temp qw ( tempfile );

my (	$sensor_reading_radius, 
	$sensor_comm_radius,
	$base_x, $base_y, $base_z, $norm_x, $norm_y, $norm_z) = (0,0,0,0,0,0);

my @sensors = ();
my @targets = ();

die "usage: $0 <terrain_file.txt> <sensors.gnuplot> <targets.gnuplot> <instruction.gnuplot>\n" 
	unless (@ARGV == 4);

my $terrain_file = $ARGV[0];
my $sensor_file = $ARGV[1];
my $target_file = $ARGV[2];
my $instruction_file = $ARGV[3];

# COLLECT INFO FROM INPUT FILE

open(FH, "<$terrain_file") or 
	die "Error: could not open terrain file $terrain_file\n";

while(<FH>){
	chomp;
	if (/^# sensor coords: (.*)/){
		my $sens_coord = $1;
		my @coords = split(/\] /, $sens_coord);
		@sensors = map { /[0-9]+ \[([0-9]+) ([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
	} elsif (/^# target coords: (.*)/){
		my $target_coord = $1;
		my @coords = split(/\] /, $target_coord);
		@targets = map { /[A-Z]+ \[([0-9]+) ([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
	}
}
close(FH);

# CREATE GNUPLOT SENSOR DATA FILE

open(FH, ">$sensor_file");
print FH "# sensor location file, generated with: $0 ", join(" ",@ARGV),"\n";
foreach my $sensor (@sensors){
	my ($x, $y, $z) = @$sensor;
	print FH "$x $y $z\n";
}
close(FH);

# CREATE GNUPLOT TARGET DATA FILE

open(FH, ">$target_file");
print FH "# target location file, generated with: $0 ", join(" ",@ARGV),"\n";
foreach my $target (@targets){
	my ($x, $y, $z) = @$target;
	print FH "$x $y $z\n\n";
}
close(FH);

#CREATE GNUPLOT INSTRUCTION FILE
open(FH, ">$instruction_file");
print FH "# gnuplot instruction file, generated with: $0 ", join(" ",@ARGV),"\n";
print FH <<EOF;
set parametric
set angle degree
set urange [0:360]
set vrange [-90:90]
set isosample 10,10
set ticslevel 0
f(a,u,v,k)=a*cos(u)*cos(v)+k
g(a,u,v,l)=a*sin(u)*cos(v)+l
h(a,v,m)=a*sin(v)+m
a=20
EOF

print FH "splot \"$sensor_file\" title \"sensors\",\"$target_file\" title \"targets\"";
foreach my $target (@targets){
	my ($x, $y, $z) = @$target;
	print FH ",k=$x,l=$y,m=$z,f(a,u,v,k) notitle,g(a,u,v,l) notitle,h(a,v,m) notitle";
}
print FH "\n";
close(FH);
