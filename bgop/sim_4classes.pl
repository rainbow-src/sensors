#!/usr/bin/perl -w
#
# The BGOP Algorithm using a static priority of sensors (Best->Good->OK->Poor)  
# 
# by Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under the GPLv3 (see LICENSE file)

use strict;
use Time::HiRes qw( time );
use Tie::IxHash;

my %point_coverage = ();  # area -> sensor, contains special _sensors member
my %sensor_coverage = (); # sensor -> area, contains special _init_freq & _badness members

my $use_stack = 0; 
my $progress_report = 0; 
my $progress_alarm = 10; 	  # in seconds
my $stack_elements_per_line = 17; # how many stack elements to print on the debug line

my @stack;
my $max_sets_so_far = 0;
my $max_sets = 9999999; # once we find out the maximum number of sets
			# (min. cardinality of input sets) we update this

my $max_badness = 0; 	# gets filled in read_data

sub freq_node_in_set {
	my $node = shift;
	my $points = shift;
	my $freq = 0;

	foreach my $tmp_point (@$points){
		$freq++ if (exists $sensor_coverage{$node}{$tmp_point});
	}

	return $freq;
}

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

sub copy_sets {
	my $origin = shift;
	my @destination = ();

	foreach my $ref (@$origin){
		my @tmp_array = @$ref;
		push(@destination, \@tmp_array);
	}
	return \@destination;
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
	printf "# %s\n", '$Id: sim_4classes.pl 623 2009-02-23 19:31:53Z glynos $';
}

sub print_sorted_sensors {
	my $cur_sensor_set = shift;
	my $point_coverage = shift;

	while(my ($key, $value) = each %$cur_sensor_set){
		my @area_nodes = ();
		foreach my $area (keys %{$cur_sensor_set->{$key}}){
			next if (($area eq "_init_freq") || ($area eq "_badness"));
			push(@area_nodes, $point_coverage->{$area}{_sensors});
		}
		printf "%5i %5f %s\n", $key, $value->{_badness}, join(" ",@area_nodes);
	}
}

sub sort_candidates {
	my $cur_sensor_set = shift;
	my $cur_point_set = shift;

	my @best_nodes = (); # cover this set (completely)
	my @good_nodes = (); # cover part of this set
	my @ok_nodes = ();   # cover this set + some other points (not in set)				
	my @poor_nodes = (); # cover part of this set + some other points (not in set)
	my @all_candidates = ();			

	foreach my $node (keys %$cur_sensor_set){
              	my $freq = freq_node_in_set($node, $cur_point_set);
               	my $init_freq = $sensor_coverage{$node}{_init_freq};

		if ($freq == 0){
			next;
		} elsif (($freq == scalar @$cur_point_set) && ($freq == $init_freq)){ 
			push(@best_nodes, $node);
		} elsif ($freq == $init_freq){ # we consider all nodes (we'll sort them afterwards)
			push(@good_nodes, [ $node , $freq ]);
		} elsif (($freq == scalar @$cur_point_set) && ($freq < $init_freq)){ # ditto
			push(@ok_nodes, [ $node, $init_freq ]);
		} else { # ditto according to benefit
			my $benefit = $freq / ($init_freq - $freq);
			push(@poor_nodes, [ $node, $benefit ]);
		}
	}

	@good_nodes = map { $_->[0] } sort { $b->[1] <=> $a->[1] } @good_nodes;
	@ok_nodes = map { $_->[0] } sort { $a->[1] <=> $b->[1] } @ok_nodes;
	@poor_nodes = map { $_->[0] } sort { $b->[1] <=> $a->[1] } @poor_nodes;

	@all_candidates = (@best_nodes, @good_nodes, @ok_nodes, @poor_nodes);
#	printf "%5i %5i %5i %5i\n",scalar @best_nodes, scalar @good_nodes, scalar @ok_nodes, scalar @poor_nodes;
	
	return \@all_candidates;
}


sub algorithm_w_stack {
	my %cur_sensor_set;
	my @cur_point_set = keys %point_coverage;
	my $cur_set = [];
	my @sets = ();
	my $saved_sets = [];
	my $stack_i = 0;
	my $max_coverage = 0; # the maximum number of points we could be covering


#	%cur_sensor_set = %sensor_coverage;

	# perl magic: take the keys of %sensor_coverage hash, sort them in ascending _badness order,
	# then create new hash preserving this ordering (first in, first out key-wise)
	tie %cur_sensor_set, 'Tie::IxHash', map { $_ => $sensor_coverage{$_} } 
		sort { $sensor_coverage{$a}{_badness} <=> $sensor_coverage{$b}{_badness} } 
		keys %sensor_coverage;

	return \@sets if ((scalar @cur_point_set == 0) || (scalar keys %cur_sensor_set == 0));

	foreach my $node (keys %cur_sensor_set){
		$max_coverage += $cur_sensor_set{$node}{_init_freq};
	}

	do {
		while ( $stack[$stack_i] != 0){ # zero signifies that we've completely covered this
			my $selected_node = undef;

			if ($max_coverage < scalar @cur_point_set){ # can't even finish this set?
				$stack[$stack_i] = 0;
				last;
			}

			my $gross_sets = (($max_coverage - scalar @cur_point_set)/
					  (scalar keys %point_coverage)) + scalar @sets + 1;

			# heuristic: by adding up all remaining sensor init_freq's is it possible
			#            to fill up more sets than we have already generated?
			if ($gross_sets < ($max_sets_so_far + 1) ){
				$stack[$stack_i] = 0;
				last;
			}

			my $candidates = sort_candidates(\%cur_sensor_set, \@cur_point_set);
			my $num_cand = scalar @$candidates;

			if ($num_cand == 0){			# no candidates
				if (scalar @sets > $max_sets_so_far){
					$max_sets_so_far = scalar @sets;
					$saved_sets = copy_sets(\@sets); 
				}
				$stack[$stack_i] = 0;
			} else { 				
				if ($stack[$stack_i] == -1){ 	# first time here
					$stack[$stack_i] += $num_cand;
					$selected_node = $candidates->[0];
				} else {			# we've visited this node before
					$stack[$stack_i]--;
					$selected_node = $candidates->[$num_cand - $stack[$stack_i] - 1];
				}

				@cur_point_set = grep { 
					(!exists $sensor_coverage{$selected_node}{$_}) 
				} @cur_point_set;
				push(@$cur_set, $selected_node);
				$max_coverage -= $cur_sensor_set{$selected_node}{_init_freq};
				delete $cur_sensor_set{$selected_node};

				if (scalar @cur_point_set == 0){ # end of a set
					push (@sets, $cur_set);
					return \@sets if (scalar @sets == $max_sets);

					@cur_point_set = keys %point_coverage;
					$cur_set = [];
				}
				$stack_i++;
			}
		}

		# backtracking stuff ...

		if ((scalar @sets != 0) || (scalar @$cur_set != 0)){ # have at least one sensor in the bag
			if (scalar @$cur_set == 0){
				$cur_set = $sets[-1];
				pop (@sets);
			}

			my $tmp_node = pop(@$cur_set);

			# BIG NOTE HERE -----------------------------------------------------]
			# If you play with a hash (insert/delete items), nothing prevents you
			# from finding a different ordering of the keys in the future.
			# BUT.. since we re-insert the last item we had deleted, it is
			# safe to assume that the ordering of keys will be kept the same.
			# This is very important since we depend on sort_candidates to 
			# produce identical results when supplied with the same parameters.
			# -------------------------------------------------------------------]

			$cur_sensor_set{$tmp_node} = $sensor_coverage{$tmp_node};
			$max_coverage += $cur_sensor_set{$tmp_node}{_init_freq};
			@cur_point_set = map { 
				my @ret_val = ($_);
				foreach my $tmp_node2 (@$cur_set){
					if (exists $sensor_coverage{$tmp_node2}{$ret_val[0]}){
						@ret_val = ();
						last;
					}	
				}
				@ret_val;
			} keys %point_coverage;	
		}
		$stack[$stack_i--] = -1;
	} until ($stack_i < 0);

	return $saved_sets;
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
		my $max_points = scalar @cur_point_set;

		foreach my $node (keys %cur_sensor_set){
			$freqs{$node} = $sensor_coverage{$node}{_init_freq};
		}

		while(scalar @cur_point_set != 0){
			my $selected_node = undef;

			my $best_node = undef; # covers the set of points exactly
			my $good_node = undef; # covers part of this set but nothing else
			my $ok_node   =	undef; # covers this set completely + other points (not in set)
			my $poor_node = undef; # covers part of this set + other points (not in set) 

			my $min_best_badness = 	$max_badness + 1;
			my $min_good_badness = 	$max_badness + 1;
			my $min_ok_badness   = 	$max_badness + 1;
			my $min_poor_badness = 	$max_badness + 1;

			my $max_freq_good_nodes = 0;
			my $min_init_freq_ok_nodes = $max_points + 1;
			my $max_benefit = 0;

			while(my ($node, $freq) = each %freqs){
                         	my $init_freq = $sensor_coverage{$node}{_init_freq};
				my $badness = $sensor_coverage{$node}{_badness};

				if (($freq == scalar @cur_point_set) && ($freq == $init_freq)){
					if ($badness < $min_best_badness){
						$min_best_badness = $badness;
						$best_node = $node;
					}
				} elsif ($freq == $init_freq){
					if ($freq > $max_freq_good_nodes){
						$max_freq_good_nodes = $freq;
						$min_good_badness = $badness;
						$good_node = $node;
					} elsif (($freq == $max_freq_good_nodes) && ($badness < $min_good_badness)){
						$min_good_badness = $badness;
						$good_node = $node;
					}
				} elsif (($freq == scalar @cur_point_set) && ($freq < $init_freq)){
	 	               		if ($init_freq < $min_init_freq_ok_nodes){
				       		$min_init_freq_ok_nodes = $init_freq;
						$min_ok_badness = $badness;
				       		$ok_node = $node;
			       		} elsif (($init_freq == $min_init_freq_ok_nodes) && ($badness < $min_ok_badness)){
						$min_ok_badness = $badness;
						$ok_node = $node;
					}
				} else { # TODO: we need to minmax between ($init_freq-$freq) and $freq
					my $benefit = $freq / ($init_freq - $freq);

					if ($benefit > $max_benefit){
						$max_benefit = $benefit;
						$min_poor_badness = $badness;
						$poor_node = $node;
					} elsif (($benefit == $max_benefit) && ($badness < $min_poor_badness)){
						$min_poor_badness = $badness;
						$poor_node = $node;
					}
				}
			}

#			printf STDERR "%i %i %i %i (%i pts, %i sens) (good=%i ok=%i poor=%.1f)\n", $best_node?1:0, $good_node?1:0, $ok_node?1:0, $poor_node?1:0, scalar @cur_point_set, scalar keys %cur_sensor_set, $max_freq_good_nodes, $min_init_freq_ok_nodes, $max_benefit;

			$selected_node = $best_node || $good_node || $ok_node || $poor_node;

#			printf STDERR "pts left=[%s] \n", join("," , map { $_ => $point_coverage{$_}{_sensors} } @cur_point_set) if (!defined $selected_node);
			
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
		push (@sets, $cur_set); # end of a set
		$max_sets_so_far = scalar @sets;
		return \@sets if ($max_sets_so_far == $max_sets);
	}
	return \@sets;
}


sub read_data {
	my $min_sensors_per_point = 9999999;
	my $max_sensors_per_point = 0;
	my $num_areas = 0;

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

		$num_areas++;
	}
	# the maximum number of generated sets is bounded by the minimum cardinality
	# of input sets
	$max_sets = $min_sensors_per_point;

	foreach my $sensor (keys %sensor_coverage){
		$sensor_coverage{$sensor}{_badness} = 0;
		foreach my $point (keys %{$sensor_coverage{$sensor}}){
			next if (($point eq "_init_freq") || ($point eq "_badness"));

			my $diff = ($max_sensors_per_point - $point_coverage{$point}{_sensors} + 1) * 1.0;
			
			# watch for an overflow here...
			$sensor_coverage{$sensor}{_badness} += ($diff ** 3);
		}
		if ($sensor_coverage{$sensor}{_badness} > $max_badness){
			$max_badness = $sensor_coverage{$sensor}{_badness};
		}
	}
}
 
read_data();
@stack = (-1) x ((scalar keys %sensor_coverage) + 1);

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
		if ($use_stack){
			my $stack_sz = scalar @stack;
			my $bigger = ($stack_sz > $stack_elements_per_line)? 
				$stack_elements_per_line : $stack_sz;
			for(my $i=0; $i<$bigger; $i++){
				printf STDERR "%3i ", $stack[$i];
			}
			printf STDERR "[%i/%i]\n", $max_sets_so_far, $max_sets;
		} else {
			if (($max_sets_so_far != 0) && ($max_sets_so_far != $last_set_count)){
				my $cur_time = time;

				$ETA = $cur_time + (($max_sets - $max_sets_so_far)*
					($cur_time - $last_time_count)/($max_sets_so_far - $last_set_count));

				$last_time_count = $cur_time;
				$last_set_count = $max_sets_so_far;
				$last_ETA = $ETA;
			}

			printf STDERR "%5d/%-5d %6.2f%% done [ETA: %s]\n",
				scalar $max_sets_so_far, $max_sets, ($max_sets_so_far / $max_sets)*100, 
				$ETA ? (scalar localtime(int($ETA))):"unknown";			
		}

		alarm $progress_alarm; 
	};
}

$time_start = time;
$last_time_count = $time_start;

my $sets_ref = ($use_stack)?algorithm_w_stack():algorithm();

$time_finish = time;
print_results($sets_ref, $max_sets, $time_start, $time_finish);
