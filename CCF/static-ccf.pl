#!/usr/bin/perl -w

# This is an implementation of the static-CCF algorithm as presented in the paper:
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

my %init_sensors = ();

my $debugging = 0;
my $progress_report = 0;
my $progress_alarm = 10; 	  # in seconds

my $sets_so_far = 0;
my $max_sets = 9999999; # once we find out the maximum number of sets
			# (min. cardinality of input sets) we update this

my $max_freq = 0; # gets filled in read_data
my $max_badness = 0; # gets filled in read_data
my $double_coverings = 0;

my $w = 1; # max number of sets, a node will be part of. It is read from the cmdline
my %lifetime = ();
my $a = 0;
my $b = 0;
my $c = 0;

sub evaluate {
	my $sets = shift;
	my %seen = ();
	my $max_covers = 0;
	my $min_covers = 99999999;

	my $set_number = 1;

	%sensor_coverage = %init_sensors;

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
				$seen{$node} += 1;
				if ($seen{$node} > $w){
					printf "# Error: Node %i (set %i) has been used more than %i times\n",
						$node, $set_number, $w;
					return 0;
				}
			} else {
				$seen{$node} = 1;
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
	printf "# Total network lifetime: %.2f * sensor lifetime\n", $i / $w;
	printf "# Total number of double-coverings: %d\n", $double_coverings;
	printf "# %s\n", '$Id: static-ccf.pl 1436 2011-01-04 00:37:01Z jim $';
}


sub algorithm {
	my %cur_sensor_set;
	my @cur_point_set;
	my @sets = ();
	my %freqs = ();
	my $min_point = undef;

	return \@sets if (scalar keys %point_coverage == 0);

	# as there are available sensors, do ...
	while(scalar keys %sensor_coverage != 0){
		my $cur_set = [];
		%cur_sensor_set = %sensor_coverage;
		@cur_point_set = keys %point_coverage;
		my $ct = 0;

		foreach my $node (keys %cur_sensor_set){
			$freqs{$node} = $sensor_coverage{$node}{_init_freq};
		}
		my @points_to_cover = keys %point_coverage;

		# as there are uncovered targets, do ...
		while(scalar @cur_point_set != 0){
			my $selected_node = undef;
			my $max_CCF = 0;
			my $prev_badness = $max_badness + 1;

			# all available sensors are examined
			while (my ($node, $freq) = each %freqs){
                         	my $init_freq = $sensor_coverage{$node}{_init_freq};
				my $badness = $sensor_coverage{$node}{_badness};

				my $uncovered = $freq;
				my $covered = $init_freq - $freq;

				my $r = 1 - (scalar @cur_point_set) / (scalar keys %point_coverage);

				my $coverage = $uncovered / ($covered+1)**$r ;

				my $CCF = $a*$coverage/(scalar @cur_point_set) + $b*(1 - $badness/$max_badness) + $c*$lifetime{$node}/$w;

				printf STDERR "in:%i out:%i r:%f cvrg:%f life:%i B:%f CCF:%f node:%i\n", $uncovered, $covered, $r, $coverage, $lifetime{$node}, 1 - $badness/$max_badness, $CCF, $node if $debugging==1;

				if ($CCF > $max_CCF){
					$max_CCF = $CCF;
					$selected_node = $node;
					$prev_badness = $badness;
				} elsif (($CCF == $max_CCF) && ($badness < $prev_badness)){
					$selected_node = $node;
					$prev_badness = $badness;
				}
			}

			printf STDERR "-->init:%i life:%i B:%f CCF:%f node:%i\n", $sensor_coverage{$selected_node}{_init_freq}, $lifetime{$selected_node}, 1-$sensor_coverage{$selected_node}{_badness}/$max_badness, $max_CCF, $selected_node if(defined $selected_node) && ($debugging==1);

			return \@sets if (!defined $selected_node);

			my @remaining_pts = ();

			foreach my $pt (keys %{$sensor_coverage{$selected_node}}){
				next if (($pt eq "_init_freq") || ($pt eq "_badness"));
				$ct++;
			}

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
			delete $freqs{$selected_node};

			$lifetime{$selected_node} -= 1;

			delete $cur_sensor_set{$selected_node};
			if ($lifetime{$selected_node} == 0){
				delete $sensor_coverage{$selected_node};
			}

		}
		$double_coverings += ($ct - (scalar keys %point_coverage));
		push (@sets, $cur_set); # end of a set
		$sets_so_far = scalar @sets;
		return \@sets if ($sets_so_far == $max_sets);
		printf STDERR "===============================END=OF=A=SET====================================\n" if $debugging==1;
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
	$max_sets = $min_sensors_per_point * $w;

	foreach my $sensor (keys %sensor_coverage){
		if ($sensor_coverage{$sensor}{_init_freq} > $max_freq){
			$max_freq = $sensor_coverage{$sensor}{_init_freq};
		}
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
		$lifetime{$sensor} = $w;
	}
}

die "$0 <max_sets_per_sensor> <a> <b> <scenario.txt>\n" unless(@ARGV == 4);
$w = shift @ARGV;
$a = shift @ARGV;
$b = shift @ARGV;

if (($a==0) && ($b==0)){
	$a = 0.35;
	$b = 0.02;
}
$c = 1 - $a - $b;

read_data();

%init_sensors = %sensor_coverage;

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
