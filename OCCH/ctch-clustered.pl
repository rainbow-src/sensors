#!/usr/bin/perl -w
use strict;
use Graph;
use POSIX qw(ceil floor);
use Time::HiRes qw( time );

die "$0 <cs_time_duration> <scenario.txt>\n" unless(@ARGV == 2);
my $t = shift @ARGV; # time duration of a cover set

my %point_coverage = ();  # area -> sensor, contains special _sensors member
my %sensor_coverage = (); # sensor -> area, contains special _init_freq member

my %init_sensors = ();

my $sets_so_far = 1;

my $ie = 20; # Initial energy of a node
my %lifetime = (); # energy of a node throughout the process
my $e_s = 0.1 * $t; # energy consumed for sensing
my $e_r = 0.1 * $t; # energy consumed for receiving
my $e_t = 0.05 * $t; # energy consumed for transmiting
my $pkt_size = 4; # packet size (Kbits)
my $graph;
my $total_energy = 0; # total energy consumed by the sensors
my $cs_duration = 0; # actual time duration of a cover set (in time units)
my %distances = ();
my %DR = ();


sub print_results {
	my $sets = shift;
	my $time_start = shift;
	my $time_finish = shift;

	my $i = 0;
	foreach my $ref (@$sets){
		printf "C%-5d: ",++$i;
		foreach my $sensor (@$ref){
			print "$sensor ";
		}
		print "\n";
	}

	printf "# Algorithm running time: %.6f secs\n", ($time_finish - $time_start);
	printf "# Number of generated sets %.1f\n", $i;
	printf "# Total network lifetime: %.2f\n", $cs_duration;
	printf "# Total energy consumed: %d J\n", $total_energy;
	printf "# %s\n", '$Id: ctch-clustered.pl 1168 2010-04-04 23:36:14Z jim $';
}


sub algorithm {
	my %cur_sensor_set;
	my @cur_point_set;
	my @sets = ();
	my %freqs = ();
	my %sensing_data = ();
	my %agg_sensing_data = ();

	my $init_targets = scalar keys %point_coverage;

	return \@sets if (scalar keys %point_coverage == 0);

	my @E = $graph->edges;
	foreach my $edge (@E){
		my ($u, $v) = @$edge;
		next if ((grep (/H/, $u)) || (grep (/H/, $v)));
		my $weight = ($e_t/1000 + 0.0001/1000 * $distances{$u}{$v}**2);
		$graph->set_edge_weight($u, $v, $weight);
	}

	# as there are available sensors, do ...
	while(scalar keys %sensor_coverage > 0){
		my $cur_set = [];
		my %consumed = ();

		my $max_degree = 0;
		foreach my $s (keys %sensor_coverage){
			my $degree = $graph->degree($s);
			if (!defined $degree){
				delete $sensor_coverage{$s};
			}elsif ($degree > $max_degree){
				$max_degree = $degree;
			}
		}

		%cur_sensor_set = %sensor_coverage;
		@cur_point_set = keys %point_coverage;

		foreach my $node (keys %cur_sensor_set){
			$freqs{$node} = $sensor_coverage{$node}{_init_freq};
		}

		# as there are uncovered targets, do ...
		while((scalar @cur_point_set) > 0){
			my $selected_node = undef;
			my $max_CF = 0;

			# all available sensors are examined
			while (my ($node, $freq) = each %freqs){
                         	my $init_freq = $sensor_coverage{$node}{_init_freq};
				my $uncovered = $freq;
				my $covered = $init_freq - $freq;
				my $coverage = $uncovered / ($covered+1);
				my @neighbors = $graph->neighbors($node);

				my $CF = $coverage + (scalar @neighbors)/$max_degree + $lifetime{$node}/$ie;

				if ($CF > $max_CF){
					$max_CF = $CF;
					$selected_node = $node;
				}
			}

			if (!defined $selected_node){
				return \@sets;
			}

			my @remaining_pts = ();
			my @covered_targets = ();

			foreach my $pt (@cur_point_set){
				if (!exists $sensor_coverage{$selected_node}{$pt}){
					push(@remaining_pts, $pt);
				} else {
					push (@covered_targets, $pt);
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

			foreach my $t (@covered_targets){
				$sensing_data{$selected_node} += $DR{$t};
			}
			@cur_point_set = @remaining_pts;
			push(@$cur_set, $selected_node);
			delete $freqs{$selected_node};

			my @ne = $graph->neighbors($selected_node);
			foreach my $n_ (@ne){
				my $wt = $graph->get_edge_weight($selected_node, $n_);
				$graph->set_edge_weight($selected_node, $n_, $wt + $ie/$lifetime{$selected_node});
			}

			delete $cur_sensor_set{$selected_node};
		}
		my @sensing_nodes = @$cur_set;

# 		searching for relay nodes

		my @V = $graph->vertices;
		my @E = $graph->edges;
		printf "Searching for relay sensors (set %d)\n", scalar @sets + 1;
		printf "SPT computation for %d vertices and %d edges\n", scalar @V, scalar @E;
		my $sptg = $graph->SPT_Dijkstra("bs");

		my @relay_sensors = ();
		foreach my $s (@$cur_set){
			my @path = $graph->SP_Dijkstra("bs", $s);
			if (scalar @path < 2){
				return \@sets;
			}
			foreach my $n (@path){
				printf "%s,", $n;
				if ((!(grep {$_ eq $n} @sensing_nodes)) && (!(grep {$_ eq $n} @relay_sensors))){
					push (@relay_sensors, $n);
				}
			}
			printf "\n";
		}

		foreach my $s (@relay_sensors){
			next if ($s eq "bs");
			push (@$cur_set, $s);
		}

		foreach my $n (@$cur_set){
			my @neib = $graph->neighbours($n);
			foreach my $n_ (@neib){
				my $wt = $graph->get_edge_weight($n, $n_);
				$graph->set_edge_weight($n, $n_, $wt + $ie/$lifetime{$n});
			}
		}

		@V = $sptg->vertices;
		foreach my $v (@V){
			next if ($v eq "bs");
			if (!(grep {$_ eq $v} @$cur_set)){
				$sptg->delete_vertex($v);
			}
		}

# 		Compute the number of successor sensing nodes of a relay node and their consumed energy
		foreach my $n (@$cur_set){
			my $u = $sptg->get_vertex_attribute($n, 'p');
			my $factor_r = 0;
			my $factor_t = 0;
			if (grep {$_ eq $n} @sensing_nodes){
				$agg_sensing_data{$n} = ceil($sensing_data{$n} / $pkt_size) * $pkt_size;
				$consumed{$n} += $e_s * $sensing_data{$n} + ($e_t + 0.0001 * $distances{$n}{$u}**2) * $agg_sensing_data{$n};
			}
			my $sptg_tmp = $sptg->deep_copy_graph;
			$sptg_tmp->delete_vertex($u);
			my @reachable = $sptg_tmp->all_neighbours($n);
			foreach my $r (@reachable){
				if (grep {$_ eq $r} @sensing_nodes){
					$factor_r += $agg_sensing_data{$r};
					$factor_t += $sensing_data{$r};
				}
			}
			$agg_sensing_data{$n} = ceil($factor_t / $pkt_size) * $pkt_size;
			$consumed{$n} += ($e_r * $factor_r +  ($e_t + 0.0001 * $distances{$n}{$u}**2) * $agg_sensing_data{$n});
		}

		my $min_duration = 1;
		foreach my $n (@$cur_set){
			if ($lifetime{$n} / $consumed{$n} < $min_duration){
				$min_duration = $lifetime{$n} / $consumed{$n};
			}
		}
		$cs_duration += $min_duration;
		printf "md: %.2f\n", $min_duration;

		foreach my $n (@$cur_set){
			$lifetime{$n} -= $consumed{$n} * $min_duration;
			$total_energy += $consumed{$n} * $min_duration;
			if ($lifetime{$n} < 1){
				$graph->delete_vertex($n);
				delete $sensor_coverage{$n};
				delete $cur_sensor_set{$n};
				delete $freqs{$n};
				printf "%s -> %d\n", $n, $lifetime{$n};
			}
			$consumed{$n} = 0;
			$sensing_data{$n} = 0;
			$agg_sensing_data{$n} = 0;
		}

		@V = $graph->vertices;
		foreach my $s (@V){
			if (!$graph->same_connected_components($s, "bs")){
				$graph->delete_vertex($s);
				delete $sensor_coverage{$s} if (exists $sensor_coverage{$s});
			}
		}
		$graph->SPT_Dijkstra_clear_cache;

		push (@sets, $cur_set); # end of a set
		$sets_so_far = scalar @sets;
		printf "Total lifetime (real): %.2f / %d\n", $cs_duration, scalar @sets;
		return \@sets if (scalar keys %sensor_coverage == 0);
	}
	return \@sets;
}

sub distance {
	my ($x1, $x2, $y1, $y2) = @_;

	return sqrt( (($x1-$x2)*($x1-$x2))
			+(($y1-$y2)*($y1-$y2)) ) / 10;
}

sub read_data {
	my $min_sensors_per_point = 9999999;
	my $max_sensors_per_point = 0;
	my $temp_graph = 0;
	my @all_sensors = ();
	my @heads = ();

	while(<>){
		if (/^# sensor coords: (.*)/){
			my $sens_coord = $1;
			my @coords = split(/\] /, $sens_coord);
			@all_sensors = map {/([0-9]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3];} @coords;
		}

		if (/^# cluster head coords: (.*)/){
			my $head_coord = $1;
			my @coords = split(/\] /, $head_coord);
			@heads = map {/(H[0-9]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3];} @coords;
		}

		if (/^# Graph: (.*)/){
			$temp_graph = $1;
		}

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

	$graph = Graph::Undirected->new;
	my @edges = split(/,/, $temp_graph);
	foreach my $edge (@edges){
		chomp ($edge);
		my ($v1, $v2) = split(/=/,$edge);
		$graph->add_weighted_edge($v1, $v2, 0);
	}

	foreach my $head (@heads){
		my ($h, $x, $y) = @$head;
		my @N = $graph->neighbors($h);
		if (grep {$_ eq "bs"} @N){
			$distances{$s}{"bs"} = distance($x, $base_x, $y, $base_y);
			$distances{"bs"}{$s} = distance($x, $base_x, $y, $base_y);
		}
		foreach my $head_ (@heads){
			my ($h_, $x_, $y_) = @$head_;
			if (!(grep {$_ eq $h_} @N)){
				$distances{$h}{$h_} = undef;
			}else{
				$distances{$h}{$h_} = distance($x, $x_, $y, $y_);
			}
		}
		foreach my $sensor_ (@all_sensors){
			my ($s_, $x_, $y_) = @$sensor_;
			if (!(grep {$_ eq $s_} @N)){
				$distances{$h}{$s_} = undef;
				$distances{$s_}{$h} = undef;
			}else{
				$distances{$h}{$s_} = distance($x, $x_, $y, $y_);
				$distances{$s_}{$h} = distance($x, $x_, $y, $y_);
			}
		}
	}
	foreach my $sensor (@all_sensors){
		my ($s, $x, $y) = @$sensor;
		my @N = $graph->neighbors($s);
		if (grep {$_ eq "bs"} @N){
			$distances{$s}{"bs"} = distance($x, 1, $y, 1);
			$distances{"bs"}{$s} = distance($x, 1, $y, 1);
		}
		foreach my $sensor_ (@all_sensors){
			my ($s_, $x_, $y_) = @$sensor_;
			if (!(grep {$_ eq $s_} @N)){
				$distances{$s}{$s_} = undef;
			}else{
				$distances{$s}{$s_} = distance($x, $x_, $y, $y_);
			}
		}
	}

	foreach my $t (keys %point_coverage){
#  		$DR{$t} = rand(19) + 1;
		$DR{$t} = 2;
	}

	foreach my $sensor (@all_sensors){
		my ($s, $x, $y) = @$sensor;
		$lifetime{$s} = $ie;
	}
	foreach my $head (@heads){
		my ($h, $x, $y) = @$head;
		$lifetime{$h} = 4 * $ie;
	}
}

read_data();

%init_sensors = %sensor_coverage;

my $time_start = 0;
my $time_finish = 0;
$time_start = time;
my $sets_ref = algorithm();
$time_finish = time;

print_results($sets_ref, $time_start, $time_finish);
