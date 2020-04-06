#!/usr/bin/perl -w
use strict;
use Graph;
use GD::SVG;
use POSIX qw(ceil floor);
use Time::HiRes qw( time );

die "$0 <cs_time_duration> <scenario.txt>\n" unless(@ARGV == 2);
my $tau = shift @ARGV; # Maximum time duration of a cover set (1tau = 1000secs)
$tau = 1000 * $tau;

my %point_coverage = ();  # area -> sensor, contains special _sensors member
my %sensor_coverage = (); # sensor -> area, contains special _init_freq member

my %init_sensors = ();

my $l_0 = 20; # Initial energy of a node
my %lifetime = (); # energy of a node throughout the process
my $e_s = 100*10**(-9); # energy consumed for sensing
my $e_r = 100*10**(-9); # energy consumed for receiving
my $e_t = 50*10**(-9); # energy consumed for transmiting
my $e_op = 100*10**(-12); # op-amp
my $pkt_size = 4000; # packet size (bits)
my $graph;
my $total_energy = 0; # total energy consumed by the sensors
my $cs_duration = 0; # actual time duration of a cover set (in time units)
my %distances = ();
my $DR = 1000;
my @criticals = ();
my %criticality = ();

### The following variables are used for figure generation ###
my $generate_figures = 0;
my %scoords = ();
my @all_sensors = ();
my @targets = ();
my ($sensor_reading_radius, $sensor_comm_radius, $base_x, $base_y, $norm_x, $norm_y) = (0, 0, 0, 0, 0, 0);


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
	printf "# Total network lifetime: %.2f h\n", $cs_duration*$tau/3600;
	printf "# Total energy consumed: %d J\n", $total_energy;
	printf "# %s\n", '$Id:$';
}


sub algorithm {
	my %cur_sensor_set;
	my @cur_point_set;
	my @sets = ();
	my %freqs = ();
	my %sensing_data = ();
	my %sensing_pkts = ();

	my $init_targets = scalar keys %point_coverage;

	return \@sets if (scalar keys %point_coverage == 0);

#	Initialise the weights of the graph
	my @E = $graph->edges;
	foreach my $edge (@E){
		my ($u, $v) = @$edge;
		my $wt = ($e_t + $e_op*$distances{$u}{$v}**2) / $e_t;
		$graph->set_edge_weight($u, $v, $wt);
	}

	my $rho = 65536;

	my $min_point = undef;
	@criticals = ();
	my $min_energy_per_point = 9999999;
	my %cardinality = ();
	foreach my $pt (keys %point_coverage){
		my $i = 0;
		foreach my $nd (keys %{$point_coverage{$pt}}){
			next if ($nd eq "_sensors");
			if (exists $freqs{$nd}){
				$i += $lifetime{$nd};
			}
		}
		$cardinality{$pt} = $i;
		if ($i < $min_energy_per_point){
			$min_energy_per_point = $i;
			$min_point = $pt;
		}
	}
	foreach my $pt (keys %point_coverage){
		if ($cardinality{$pt} < ($min_energy_per_point+$l_0)){
			push(@criticals, $pt);
 		}
 	}
 	%criticality = ();
 	foreach my $t (@criticals){
 		foreach my $s (keys %{$point_coverage{$t}}){
 			next if ($s eq "_sensors");
 			$criticality{$s} = 1;
 		}
 	}

	# as there are available sensors, do ...
	while(scalar keys %sensor_coverage > 0){
		my $cur_set = [];
		my %consumed = ();
		my $ct = 0;

		%cur_sensor_set = %sensor_coverage;
		@cur_point_set = keys %point_coverage;

		foreach my $node (keys %cur_sensor_set){
			$freqs{$node} = $sensor_coverage{$node}{_init_freq};
		}

		foreach my $s (keys %sensor_coverage){
			if (exists $criticality{$s}){
				my @ne = $graph->neighbors($s);
				foreach my $n_ (@ne){
					my $wt = $graph->get_edge_weight($s, $n_);
					$graph->set_edge_weight($s, $n_, $wt * $rho);
				}
			}
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

				my $CF = $coverage + $lifetime{$node}/$l_0;

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

			foreach my $pt (keys %{$sensor_coverage{$selected_node}}){
				next if ($pt eq "_init_freq");
				push (@covered_targets, $pt);
			}
			$ct += scalar @covered_targets;

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

			foreach my $t (@covered_targets){
				$sensing_data{$selected_node} += $DR;
				$sensing_pkts{$selected_node} += 1;
			}
			@cur_point_set = @remaining_pts;
			push(@$cur_set, $selected_node);
			delete $freqs{$selected_node};

			if (!exists $criticality{$selected_node}){
				my @ne = $graph->neighbors($selected_node);
				foreach my $n_ (@ne){
#					next if ($n_ eq "bs");
					my $wt = $graph->get_edge_weight($selected_node, $n_);
					$graph->set_edge_weight($selected_node, $n_, $wt * $rho);
				}
			}

			delete $cur_sensor_set{$selected_node};
		}
		printf "# %d / %d\n", $ct, $init_targets;
		my @sensing_nodes = @$cur_set;

# 		Compute the SPT
		my @V = $graph->vertices;
		my @E = $graph->edges;
		printf "# Searching for relay sensors (set %d)\n", scalar @sets + 1;
		printf "# SPT computation for %d vertices and %d edges\n", scalar @V, scalar @E;
 		my $sptg = $graph->SPT_Dijkstra("bs");

#		Find the relay nodes
		my @relay_sensors = ();

		foreach my $s (@$cur_set){
			printf "# ";
			my @path = $graph->SP_Dijkstra("bs", $s);
			if (!(grep {$_ eq "bs"} @path)){
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

#		Put relay nodes into the current cover set
		foreach my $s (@relay_sensors){
			next if ($s eq "bs");
			push (@$cur_set, $s);
		}

#		delete unused vertices from SPT
		@V = $sptg->vertices;
		foreach my $v (@V){
			next if ($v eq "bs");
			if (!(grep {$_ eq $v} @$cur_set)){
				$sptg->delete_vertex($v);
			}
		}

# 		Compute the number of successor sensing nodes of a relay sensor and their consumed energy
		foreach my $n (@$cur_set){
			my $u = $sptg->get_vertex_attribute($n, 'p');
			my $factor_r_t = 0;
			if (grep {$_ eq $n} @sensing_nodes){
				$consumed{$n} = $e_s * $sensing_data{$n} + ($e_t + $e_op*$distances{$n}{$u}**2) * $sensing_pkts{$n} * $pkt_size;
			}
			my $sptg_tmp = $sptg->copy_graph;
			$sptg_tmp->delete_vertex($u);
			my @reachable = $sptg_tmp->all_neighbours($n);
			foreach my $r (@reachable){
				if (grep {$_ eq $r} @sensing_nodes){
					$factor_r_t += $sensing_pkts{$r} * $pkt_size;
				}
			}
			$consumed{$n} += ($e_r * $factor_r_t  +  ($e_t + $e_op*$distances{$n}{$u}**2) * $factor_r_t);
		}

#		Compute the time duration of the cover set
		my $min_duration = 1;
		foreach my $n (@$cur_set){
			if ($lifetime{$n} / ($consumed{$n}*$tau) < $min_duration){
				$min_duration = $lifetime{$n} / ($consumed{$n}*$tau);
			}
		}
		$cs_duration += $min_duration;
		printf "# md: %.3f\n", $min_duration*$tau/3600;

		if ($generate_figures){
			my %energy = ();
			my $max_energy = 0;
			foreach my $t (keys %point_coverage){
				foreach my $s (keys %{$point_coverage{$t}}){
					next if (($s eq "_sensors") || (!exists $lifetime{$s}));
					$energy{$t} += $lifetime{$s};
				}
				if ($energy{$t} > $max_energy){
					$max_energy = $energy{$t};
				}
			}

			@V = $graph->vertices;
			image($sptg, \@V, \%energy, $max_energy, \%lifetime, $min_duration*$tau/3600, scalar @sets+1);
		}

#		Delete sensors with no redundant energy
		foreach my $n (@$cur_set){
			$lifetime{$n} -= $consumed{$n} * $min_duration * $tau;
			$total_energy += $consumed{$n} * $min_duration * $tau;
			if ($lifetime{$n} <= 0.00000015){
				$graph->delete_vertex($n);
				delete $sensor_coverage{$n};
				delete $cur_sensor_set{$n};
				delete $freqs{$n};
				printf "# %d -> %d\n", $n, $lifetime{$n};
			}
			$consumed{$n} = 0;
			$sensing_data{$n} = 0;
			$sensing_pkts{$n} = 0;
		}

		foreach my $s (keys %sensor_coverage){
			if (exists $criticality{$s}){
				my @ne = $graph->neighbors($s);
				foreach my $n_ (@ne){
					my $wt = $graph->get_edge_weight($s, $n_);
					$graph->set_edge_weight($s, $n_, $wt / $rho);
				}
			}
		}

 		foreach my $n (@$cur_set){
			next if (!$graph->has_vertex($n));
			my @neib = $graph->neighbours($n);
			foreach my $n_ (@neib){
				my $wt = $graph->get_edge_weight($n, $n_);
#				if ((grep {$_ eq $n} @sensing_nodes) && ($n_ ne "bs") && (!exists $criticality{$n})){
				if ((grep {$_ eq $n} @sensing_nodes) && (!exists $criticality{$n})){
					$wt = $wt / $rho;
				}
				if ($n_ ne "bs"){
					$graph->set_edge_weight($n, $n_, $wt + $l_0/min($lifetime{$n}, $lifetime{$n_}));
				}else{
					$graph->set_edge_weight($n, $n_, $wt + $l_0/$lifetime{$n});
				}
			}
		}

#		Delete all unreachable nodes
# 		@V = $graph->vertices;
# 		foreach my $s (@V){
# 			if (!$graph->same_connected_components($s, "bs")){
# 				$graph->delete_vertex($s);
# 				delete $sensor_coverage{$s} if (exists $sensor_coverage{$s});
# 			}
# 		}
		$graph->SPT_Dijkstra_clear_cache;

		push (@sets, $cur_set); # end of a set
		printf "# Total lifetime (real): %.4f h\n", $cs_duration*$tau/3600;
		return \@sets if (scalar keys %sensor_coverage == 0);
	}
	return \@sets;
}

sub distance {
	my ($x1, $x2, $y1, $y2) = @_;

	return sqrt( (($x1-$x2)*($x1-$x2))
			+(($y1-$y2)*($y1-$y2)) ) / 10;
}

sub min {
	my ($x, $y) = @_;
	if ($x < $y){
		return $x;
	}else{
		return $y;
	}
}

sub read_data {
	my $min_sensors_per_point = 9999999;
	my $max_sensors_per_point = 0;
	my $temp_graph = 0;

	while(<>){
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
			$scoords{"bs"} = [$base_x, $base_y];
		} elsif (/^# terrain map \[([0-9]+) x ([0-9]+)\]/){
			($norm_x, $norm_y) = ($1, $2);
		} elsif (/^# sensor coords: (.*)/){
			my $sens_coord = $1;
			my @coords = split(/\] /, $sens_coord);
			@all_sensors = map {/([0-9]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3];} @coords;
		} elsif (/^# target coords: (.*)/){
			my $target_coord = $1;
			my @coords = split(/\] /, $target_coord);
			@targets = map { /([A-Z]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
		} elsif (/^# Graph: (.*)/){
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
	foreach my $sensor (@all_sensors){
		my ($s, $x, $y) = @$sensor;
		$scoords{$s} = [$x, $y];
		my @N = $graph->neighbors($s);
		if (grep {$_ eq "bs"} @N){
			$distances{$s}{"bs"} = distance($x, $base_x, $y, $base_y);
			$distances{"bs"}{$s} = distance($x, $base_x, $y, $base_y);
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

	my @V = $graph->vertices;
	foreach my $v (@V){
		next if ($v eq "bs");
		$lifetime{$v} = $l_0;
	}
}

sub image() {
	my $sptg = shift;
	my $sensors = shift;
	my $energy = shift;
	my $max_energy = shift;
	my $lifetime = shift;
	my $duration = shift;
	my $ref = shift;
	my ($display_x, $display_y) = (800, 800); # 800x800 pixel display pane
	my $im = new GD::SVG::Image($display_x, $display_y);
	my $blue = $im->colorAllocate(0,0,255);
	my $green = $im->colorAllocate(200,255,200);
	my $black = $im->colorAllocate(0,0,0);
	my $red = $im->colorAllocate(255,0,0);
	my $white = $im->colorAllocate(255,255,255);
	my $grey = $im->colorAllocate(128,128,128);
	my $yellow = $im->colorAllocate(255,255,0);

	$im->string(gdSmallFont,5,780,$duration,$black);

	my @edges = split(/,/, $sptg);
	my @active = ();
	foreach my $e (@edges){
		my ($e1, $e2) = split(/=/, $e);
		push (@active, $e1);
		push (@active, $e2);
		my ($x1, $y1) = ($scoords{$e1}[0], $scoords{$e1}[1]);
		($x1, $y1) = (int(($x1 * $display_x)/ $norm_x), int(($y1 * $display_y)/ $norm_y));
		my ($x2, $y2) = ($scoords{$e2}[0], $scoords{$e2}[1]);
		($x2, $y2) = (int(($x2 * $display_x)/ $norm_x), int(($y2 * $display_y)/ $norm_y));
		$im->line($x1, $y1, $x2, $y2, $green);
	}

	foreach my $sensor (@all_sensors){
		my ($s, $x, $y) = @$sensor;
		next if (!(grep {$_ eq $s} @$sensors));
		($x, $y) = (int(($x * $display_x)/ $norm_x), int(($y * $display_y)/ $norm_y));

		if (grep {$_ eq $s} @active){
			$im->string(gdSmallFont,$x-2,$y-12,$s,$im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
			$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
		}else{
			$im->string(gdSmallFont,$x-2,$y-12,$s,$grey);
			$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $grey);
		}
	}

	foreach my $target (@targets){
		my ($s, $x, $y) = @$target;
		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));

		$im->rectangle($x-5, $y-5, $x+5, $y+5, $red);
		$im->string(gdMediumBoldFont,$x-2,$y-20,$s,$blue);

		if (${$energy}{$s} > 255){
			$im->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $red);
		}elsif ((${$energy}{$s} <= 255) && (${$energy}{$s} > 20)){
			$im->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $im->colorAllocate(255,int(255-${$energy}{$s}*255/$max_energy),0));
		}elsif (${$energy}{$s} <= 20){
			$im->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $yellow);
		}
	}

	$im->filledRectangle( ($base_x * $display_x)/$norm_x-5, ($base_y * $display_y)/$norm_y-5,
		($base_x * $display_x)/$norm_x+5, ($base_y * $display_y)/$norm_y+5, $red);

	$im->arc(($base_x * $display_x)/$norm_x,
		($base_y * $display_y)/$norm_y,
		2 * int(($sensor_comm_radius * $display_x)/$norm_x),
		2 * int(($sensor_comm_radius * $display_y)/$norm_y),
		0, 360, $black);

	my $image_file = undef;
	if ($ref < 10){
		$ref = join ('', "0", $ref);
		$image_file = join('.', "set", $ref, "svg");
	}else{
		$image_file = join('.', "set", $ref, "svg");
	}

	open(FILEOUT, ">$image_file") or
		die "could not open file $image_file for writing!";
	binmode FILEOUT;
	print FILEOUT $im->svg;
	close FILEOUT;
}

read_data();

%init_sensors = %sensor_coverage;

my $time_start = 0;
my $time_finish = 0;
$time_start = time;
my $sets_ref = algorithm();
$time_finish = time;

print_results($sets_ref, $time_start, $time_finish);
