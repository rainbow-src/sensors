#!/usr/bin/perl -w

# This is an auxiliary script to calculate the "theoretical maximum" number
# of possible output sets from an input file describing a sensor network.
#
# Primary author: Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)


use strict;

sub read_data {
	my %point_coverage = ();  # area -> sensor, contains special _sensors member
	my $min_sensors_per_point = 9999999;

	while(<>){
		next if (/^\#/); # skip comments
		chomp;
		my @input = split(/ /);
		my $point = shift @input;

		foreach my $sensor (@input){
			$point_coverage{$point}{$sensor} = 1;
			$point_coverage{$point}{_sensors}++;
		}

		if ($point_coverage{$point}{_sensors} < $min_sensors_per_point){
			$min_sensors_per_point = $point_coverage{$point}{_sensors};
		}
	}

	# the maximum number of generated sets is bounded by the minimum cardinality of input sets
	return $min_sensors_per_point;
}

die "usage: $0 <inputfile>\n" unless (@ARGV == 1);
my $max_sets = read_data();
print "max_sets = $max_sets\n";
