#!/usr/bin/perl -w
#
# Script to evaluate the validity of the output sensor sets
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under GPLv3 (see LICENSE file)

use strict;

my %point_coverage = ();  # area -> sensor, contains special _sensors member
my %sensor_coverage = (); # sensor -> area, contains special _init_freq & _badness members

my $max_sets = 9999999; # once we find out the maximum number of sets
			# (min. cardinality of input sets) we update this
my $sets;

sub evaluate {
	my $sets = shift;
	my %seen = ();
	my $max_covers = 0;
	my $min_covers = 99999999;

	my $set_number = 1;

	foreach my $set (@$sets){
		my @points_to_cover = keys %point_coverage;
		my $covers = 0;
		foreach my $node (@$set){
			if (!exists $sensor_coverage{$node}){
				printf "# Error: Unknown Node %i in set %i\n", $node, $set_number;
				return 0;
			}
			# subtracting 2 to avoid counting _badness + _init_freq special elements
			$covers += ((keys %{$sensor_coverage{$node}}) - 2);
			if (exists $seen{$node}){
				printf "# Error: Node %i (set %i) has been used before (set %i)\n",
					$node, $set_number, $seen{$node};
				return 0;
			} else {
				$seen{$node} = $set_number;
			}
			# this is _badness + _init_freq agnostic
			@points_to_cover = grep { (!exists $sensor_coverage{$node}{$_}) } 
				@points_to_cover;
		}
		if (scalar @points_to_cover != 0){
			printf "# Error: Set %i did not cover all points\n", $set_number;
			return 0;
		}
		$covers -= (scalar keys %point_coverage);
		if ($covers > $max_covers){
			$max_covers = $covers;
		}
		if ($covers < $min_covers){
			$min_covers = $covers;
		}
		$set_number++;
	}
	printf "# min_extra_covers=%ipts, max_extra_covers=%ipts\n", $min_covers, $max_covers; 
	return 1;
}


sub read_data {
	my $FH = shift;
	my $min_sensors_per_point = 9999999;
	my $max_sensors_per_point = 0;
	my $num_areas = 0;

	while(<$FH>){
		next if (/^\#/); # skip comments
		chomp;
		my @input = split(/ /);
		my $point = shift @input;

		foreach my $sensor (@input){
			$point_coverage{$point}{$sensor} = 1;
			$point_coverage{$point}{_sensors}++;
			$sensor_coverage{$sensor}{$point} = 1;
			$sensor_coverage{$sensor}{_init_freq}++;
		}

		if ($point_coverage{$point}{_sensors} < $min_sensors_per_point){
			$min_sensors_per_point = $point_coverage{$point}{_sensors};
		}

		if ($point_coverage{$point}{_sensors} > $max_sensors_per_point){
			$max_sensors_per_point = $point_coverage{$point}{_sensors};
		}

		$num_areas++;
	}
	# the maximum number of generated sets is bounded by the minimum cardinality
	# of input sets
	$max_sets = $min_sensors_per_point;

	foreach my $sensor (keys %sensor_coverage){
		$sensor_coverage{$sensor}{_badness} = 0;
		foreach my $point (keys %{$sensor_coverage{$sensor}}){
			next if (($point eq "_init_freq") || ($point eq "_badness"));

			my $diff = ($max_sensors_per_point - $point_coverage{$point}{_sensors}) * 1.0;
			
			# watch for an overflow here...
			$sensor_coverage{$sensor}{_badness} += ($diff ** 3);
		}
	}

}

sub read_output {
	my $fh = shift;
	my $sets = [];
	while(<$fh>){
		next if (/^\#/); # skip comments
		chomp;
		/^(C[0-9]+)\s+:\s+(.*)/;
		my @sensors = split(/\s+/,$2);
		push(@$sets, \@sensors);
	}
	return $sets;
}

 
die "usage: evaluate.pl <field_def.txt> <simul_output.txt>\n" unless (@ARGV == 2);

my $input_file = $ARGV[0];
my $output_file = $ARGV[1];

die "Error: could not open input file\n" unless (-r $input_file);
die "Error: could not open output file\n" unless (-r $output_file);

open(FH, "<$input_file");
read_data(*FH);
close(FH);

open(FH, "<$output_file");
$sets = read_output(*FH);
close(FH);

printf "# evaluate.pl %s %s\n", $input_file, $output_file;
printf "# %s\n", '$Id: evaluate.pl 623 2009-02-23 19:31:53Z glynos $';
exit 1 unless evaluate($sets);
