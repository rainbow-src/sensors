#!/usr/bin/perl -w

# This is an implementation of the B{GOP}-random algorithm as found in the paper:
# "Solving coverage problems in wireless sensor networks using cover sets"
# by D. Zorbas, D. Glynos, P. Kotzanikolaou and C. Douligeris
# 
# Primary author: Dimitris Glynos (daglyn/at/unipi/gr)
# Modifications by Dimitrios Zorbas (jim/at/students/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)

use strict;
use Time::HiRes qw( time );

my %point_coverage = ();  # area -> sensor, contains special _sensors member
my %sensor_coverage = (); # sensor -> area, contains special _init_freq & _badness members

my $progress_report = 0; 
my $progress_alarm = 10; 	  # in seconds

my $sets_so_far = 0;
my $max_sets = 9999999; # once we find out the maximum number of sets
			# (min. cardinality of input sets) we update this

my $max_freq = 0; # gets filled in read_data
my $max_badness = 0; # gets filled in read_data


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

sub prob_pick {
	my $array_ref = shift;
	my $max_score = shift;
	my $random = $max_score - rand($max_score);
	my $low = 0;
	my $high = scalar @$array_ref;
	my $mid = undef;
#	my $finish = undef;
#	my $start = undef;

	while ($low < $high) {
	      $mid = int ($low + (($high - $low) / 2)) ;
	      if ($random > $array_ref->[$mid]->[2]){
	      		$low = $mid + 1;
	      } else {
	      		$high = $mid;		
	      }
	}

#	$finish = $array_ref->[$low]->[2];
#	$start = ($array_ref->[$low]->[1])?($finish - $array_ref->[$low]->[1]):0;
#	printf "(%i, %f) %i %i %i %f [%f] %f %f\n",scalar @$array_ref, $max_score, $low, $mid, $high, $start, $random, $finish, $finish-$start;
	return $array_ref->[$low]->[0];
}


sub print_results {
	my $sets = shift;
	my $max_sets = shift;
	my $time_start = shift;
	my $time_finish = shift;

	exit 1 unless(evaluate($sets));

	my $i = 0;
	foreach my $ref (@$sets){
		printf "C%-5d: ",++$i;
		foreach my $sensor (@$ref){
			print "$sensor ";
		}
		print "\n";
	}

	printf "# Algorithm running time: %.6f secs\n", ($time_finish - $time_start);
	printf "# Number of generated sets %d (of %d maximum)\n", $i, $max_sets;
	printf "# %s\n", '$Id: bgop-random.pl 998 2009-11-05 13:04:23Z glynos $';
}


sub algorithm {
	my %cur_sensor_set;
	my @cur_point_set;
	my @sets = ();

	my %freqs = ();

	return \@sets if (scalar keys %point_coverage == 0);

	%cur_sensor_set = %sensor_coverage;

	while(scalar keys %cur_sensor_set != 0){
		my $cur_set = [];

		@cur_point_set = keys %point_coverage;

		foreach my $node (keys %cur_sensor_set){
			$freqs{$node} = $sensor_coverage{$node}{_init_freq};
		}

		while(scalar @cur_point_set != 0){
			my $selected_node = undef;

			my $best_node = undef; # covers the set of points exactly
			my $gop_node = undef; # good (part of set), ok (all of set & others), poor (part of set & others) 

			my $max_gop_benefit = 0;
			my $prev_gop_badness = $max_badness + 1;

			my $total_best_badness = 0;
			my $total_gop_benefit = 0;
			my @best_sensors = ();
			my @gop_sensors = ();

			while (my ($node, $freq) = each %freqs){
                         	my $init_freq = $sensor_coverage{$node}{_init_freq};
				my $badness = $sensor_coverage{$node}{_badness};

				if (($freq == scalar @cur_point_set) && ($freq == $init_freq)){
					$badness = $max_badness - $badness;
					$total_best_badness += $badness;
					# we need both $badness and the current sum of $total_best_badness
					# in order to do a binary search on ranges later
					push(@best_sensors, [$node, $badness, $total_best_badness]);
				} else { # good, ok, poor nodes
					my $in = $freq;
					my $out = $init_freq - $freq;
					
					my $a = $sets_so_far / $max_sets;
					my $b = 1 - $badness/$max_badness;

					my $benefit = $in / ($out+1)**$a + $b; 
					$total_gop_benefit += $benefit;

#					printf  "in:%i out:%i a:%f b:%f benefit=%f\n", $in, $out, $a, $b, $benefit;
					push(@gop_sensors, [$node, $benefit, $total_gop_benefit]);
				}
			}


			if (scalar @best_sensors != 0){
				$selected_node = prob_pick(\@best_sensors, $total_best_badness);			
			} elsif (scalar @gop_sensors != 0) {
				$selected_node = prob_pick(\@gop_sensors, $total_gop_benefit);
			}

#			printf STDERR "--------------------------------------------------\n";

			return \@sets if (!defined $selected_node);

			my @remaining_pts = ();
			foreach my $pt (@cur_point_set){
				if (!exists $sensor_coverage{$selected_node}{$pt}){
					push(@remaining_pts, $pt);			
				} else {
					foreach my $nd (keys %{$point_coverage{$pt}}){
						next if ($nd eq "_sensors");
						if (exists $freqs{$nd}){
							if ($freqs{$nd} > 1){
								$freqs{$nd} -= 1;
							} else {
								delete $freqs{$nd};
							}
						}
					}
				}
			}

			@cur_point_set = @remaining_pts;
			push(@$cur_set, $selected_node);
			delete $cur_sensor_set{$selected_node};
			delete $freqs{$selected_node};
		}
		push(@sets, $cur_set); # end of a set
		$sets_so_far = scalar @sets;
		return \@sets if ($sets_so_far == $max_sets);
	}
	return \@sets;
}


sub read_data {
	my $min_sensors_per_point = 9999999;
	my $max_sensors_per_point = 0;

	while(<>){
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
	}

	# the maximum number of generated sets is bounded by the minimum cardinality of input sets
	$max_sets = $min_sensors_per_point;

	foreach my $sensor (keys %sensor_coverage){	
		$sensor_coverage{$sensor}{_badness} = 0;
		foreach my $point (keys %{$sensor_coverage{$sensor}}){
			next if (($point eq "_init_freq") || ($point eq "_badness"));

			my $diff = ($max_sensors_per_point - $point_coverage{$point}{_sensors} + 1) * 1.0;
			
			# watch for an overflow here...
			$sensor_coverage{$sensor}{_badness} += ($diff ** 3);
			if ($sensor_coverage{$sensor}{_badness} > $max_badness){
				$max_badness = $sensor_coverage{$sensor}{_badness};
			}
		}
	}
}
 
read_data();

my $time_start = 0;
my $time_finish = 0;
my $last_set_count = 0;
my $last_time_count = 0;
my $ETA = 0;
my $last_ETA = 0;

if ($progress_report == 1){
	alarm $progress_alarm;
	$SIG{ALRM} = sub
	{
		if (($sets_so_far != 0) && ($sets_so_far != $last_set_count)){
			my $cur_time = time;

			$ETA = $cur_time + (($max_sets - $sets_so_far)*
				($cur_time - $last_time_count)/($sets_so_far - $last_set_count));

			$last_time_count = $cur_time;
			$last_set_count = $sets_so_far;
			$last_ETA = $ETA;
		}

		printf STDERR "%5d/%-5d %6.2f%% done [ETA: %s]\n",
			scalar $sets_so_far, $max_sets, ($sets_so_far / $max_sets)*100, 
			$ETA ? (scalar localtime(int($ETA))):"unknown";			
		alarm $progress_alarm; 
	};
}

$time_start = time;
$last_time_count = $time_start;

my $sets_ref = algorithm();
$time_finish = time;

print_results($sets_ref, $max_sets, $time_start, $time_finish);
