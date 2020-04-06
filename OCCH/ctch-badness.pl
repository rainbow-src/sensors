#!/usr/bin/perl -w

# This is an implementation of the occh-badness algorithm as presented in the paper:
# "Connected coverage in WSNs based on critical targets"
# by D. Zorbas and C. Douligeris
#
# Author: Dimitrios Zorbas (jim/at/students/unipi/gr)
# based on "b{gop}" coverage algorithn of D. Glynos
# Distributed under the GPLv3 (see LICENSE file)

use strict;
use Graph;
use GD::SVG;
use POSIX qw(ceil floor);
use Time::HiRes qw( time );

die "$0 <cs_time_duration> <scenario.txt>\n" unless(@ARGV == 2);
my $tau = shift @ARGV; # time duration of a cover set (1tau = 1000secs)
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
my %badness = ();
my $max_badness = 0; # gets filled in read_data

### The following variables are used for figure generation ###
my $generate_figures = 1;
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
	printf "# %s\n", '$Id: ctch-badness.pl 1666 2011-06-21 20:51:24Z jim $';
}


sub algorithm {
	my %cur_sensor_set;
	my @cur_point_set;
	my @sets = ();
	my %freqs = ();
	my %sensing_data = ();
	my %sensing_pkts = ();
	my @exhausted = ();

	my $init_targets = scalar keys %point_coverage;

	return \@sets if (scalar keys %point_coverage == 0);

#	Initialise the weights of the graph
	my @E = $graph->edges;
	foreach my $edge (@E){
		my ($u, $v) = @$edge;
		my $wt = ($e_t + $e_op*$distances{$u}{$v}**2) / $e_t;
		$graph->set_edge_weight($u, $v, $wt);
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

 		my @ed = $graph->edges;
		foreach my $edge (@ed){
			my ($u, $v) = @$edge;
			next if ((!exists $sensor_coverage{$u}) && (!exists $sensor_coverage{$v}));
			my $wt = $graph->get_edge_weight($u, $v);
			if ((exists $badness{$u}) && (!exists $badness{$v})){
				$wt = $wt * $badness{$u};
			}elsif ((exists $badness{$v}) && (!exists $badness{$u})){
				$wt = $wt * $badness{$v};
			}elsif ((exists $badness{$u}) && (exists $badness{$v})){
				$wt = $wt * max($badness{$u},$badness{$v});
			}
			$graph->set_edge_weight($u, $v, $wt);
		}

		# as there are uncovered targets, do ...
		while((scalar @cur_point_set) > 0){
			my $selected_node = undef;
			my $max_CF = 0;
			my $prev_badness = $max_badness + 1;

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
					$prev_badness = $badness{$node};
				}elsif (($CF == $max_CF) && ($badness{$node} < $prev_badness)){
					$selected_node = $node;
					$prev_badness = $badness{$node};
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

			my @ne = $graph->neighbors($selected_node);
			foreach my $n_ (@ne){
				my $wt = $graph->get_edge_weight($selected_node, $n_);
				$graph->set_edge_weight($selected_node, $n_, $wt * ($max_badness/$badness{$selected_node}));
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

#		Compute the time length of the cover set
		my $min_duration = 1;
		my $weak_node = undef;
		foreach my $n (@$cur_set){
			if ($lifetime{$n} / ($consumed{$n}*$tau) < $min_duration){
				$min_duration = $lifetime{$n} / ($consumed{$n}*$tau);
				$weak_node = $n;
			}
		}
		$cs_duration += $min_duration;
		printf "# md: %.3f\n", $min_duration*$tau/3600;

#		Delete sensors with no redundant energy
		foreach my $n (@$cur_set){
			$lifetime{$n} -= $consumed{$n} * $min_duration * $tau;
			$total_energy += $consumed{$n} * $min_duration * $tau;
			my @N = $graph->neighbors($n);
			my $max_dist = 0;
			foreach my $n_ (@N){
				if ($distances{$n}{$n_} > $max_dist){
					$max_dist = $distances{$n}{$n_};
				}
			}
			if ($lifetime{$n} < ($e_r + $e_t + $e_op*$max_dist**2)*$pkt_size){
				$graph->delete_vertex($n);
				push (@exhausted, $n);
				delete $sensor_coverage{$n};
				delete $cur_sensor_set{$n};
				delete $freqs{$n};
				delete $badness{$n};
				printf "# %d -> %d\n", $n, $lifetime{$n};
			}
			$consumed{$n} = 0;
			$sensing_data{$n} = 0;
			$sensing_pkts{$n} = 0;
		}

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
			image($sptg, \@V, \%energy, $max_energy, \%lifetime, \@exhausted, $weak_node, $min_duration*$tau/3600, scalar @sets+1);
		}

		@ed = $graph->edges;
		foreach my $edge (@ed){
			my ($u, $v) = @$edge;
			next if ((!exists $sensor_coverage{$u}) && (!exists $sensor_coverage{$v}));
			my $wt = $graph->get_edge_weight($u, $v);
			if ((exists $badness{$u}) && (!exists $badness{$v})){
				$wt = $wt / $badness{$u};
			}elsif ((exists $badness{$v}) && (!exists $badness{$u})){
				$wt = $wt / $badness{$v};
			}elsif ((exists $badness{$u}) && (exists $badness{$v})){
				$wt = $wt / max($badness{$u},$badness{$v});
			}
			$graph->set_edge_weight($u, $v, $wt);
		}

 		foreach my $n (@$cur_set){
			next if (!$graph->has_vertex($n));
			my @neib = $graph->neighbours($n);
			foreach my $n_ (@neib){
				my $wt = $graph->get_edge_weight($n, $n_);
				if (grep {$_ eq $n} @sensing_nodes){
					$wt = $wt / ($max_badness/$badness{$n});
				}
				if ($n_ ne "bs"){
					$graph->set_edge_weight($n, $n_, $wt + $l_0/min($lifetime{$n}, $lifetime{$n_}));
				}else{
					$graph->set_edge_weight($n, $n_, $wt + $l_0/$lifetime{$n});
				}
			}
		}

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

sub max {
	my ($x, $y) = @_;
	if ($x > $y){
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

 	foreach my $s (keys %sensor_coverage){
 		$badness{$s} = 0;
 		foreach my $t (keys %{$sensor_coverage{$s}}){
 			next if ($t eq "_init_freq");
 			my $diff = ($max_sensors_per_point - $point_coverage{$t}{_sensors} + 1) * 1.0;
 			# watch for an overflow here...
 			$badness{$s} += ($diff ** 3);
 			if ($badness{$s} > $max_badness){
 				$max_badness = $badness{$s};
 			}
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
	my $exhausted = shift;
	my $weak_node = shift;
	my $duration = shift;
	my $ref = shift;
	my ($display_x, $display_y) = (800, 800); # 800x800 pixel display pane
	my $im = new GD::SVG::Image($display_x, $display_y);
	my $enmap = new GD::SVG::Image($display_x, $display_y);
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
		$im->line($x1, $y1, $x2, $y2, $black);
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
			$enmap->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $enmap->colorAllocate(255,0,0));
		}elsif ((${$energy}{$s} <= 255) && (${$energy}{$s} > 20)){
			$im->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $im->colorAllocate(255,int(255-${$energy}{$s}*255/$max_energy),0));
			$enmap->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $enmap->colorAllocate(255,int(255-${$energy}{$s}*255/$max_energy),0));
		}elsif (${$energy}{$s} <= 20){
			$im->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $yellow);
			$enmap->arc($x,$y,
				 2 * int(($sensor_reading_radius*$display_x)/$norm_x),
				 2 * int(($sensor_reading_radius*$display_y)/$norm_y),
				 0, 360, $enmap->colorAllocate(255,255,0));
		}
	}
	
	foreach my $sensor (@all_sensors){
		my ($s, $x, $y) = @$sensor;
		($x, $y) = (int(($x * $display_x)/ $norm_x), int(($y * $display_y)/ $norm_y));

		if ((grep {$_ eq $s} @active) && (!(grep {$_ eq $s} @$exhausted))){
			$im->string(gdSmallFont,$x-2,$y-12,$s,$im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
			$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
			$enmap->filledArc($x, $y, 20, 20, 0, 360, $enmap->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
		}elsif ((!(grep {$_ eq $s} @active)) && (!(grep {$_ eq $s} @$exhausted))){
			$im->string(gdSmallFont,$x-2,$y-12,$s,$grey);
			$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $grey);
			$enmap->filledArc($x, $y, 20, 20, 0, 360, $enmap->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
		}elsif (grep {$_ eq $s} @$exhausted){
			$enmap->filledArc($x, $y, 20, 20, 0, 360, $enmap->colorAllocate(128,128,128));
		}
		
		if ($s == $weak_node){
			$im->string(gdSmallFont,$x-2,$y-12,$s,$im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
			$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $im->colorAllocate(255,int(255-${$lifetime}{$s}*255/20),0));
			$im->arc($x, $y, 14, 14, 0, 360, $black);
		}
	}

	$im->filledRectangle( ($base_x * $display_x)/$norm_x-5, ($base_y * $display_y)/$norm_y-5,
		($base_x * $display_x)/$norm_x+5, ($base_y * $display_y)/$norm_y+5, $red);

	$im->arc(($base_x * $display_x)/$norm_x,
		($base_y * $display_y)/$norm_y,
		2 * int(($sensor_comm_radius * $display_x)/$norm_x),
		2 * int(($sensor_comm_radius * $display_y)/$norm_y),
		0, 360, $black);

	$enmap->filledRectangle( ($base_x * $display_x)/$norm_x-5, ($base_y * $display_y)/$norm_y-5,
		($base_x * $display_x)/$norm_x+5, ($base_y * $display_y)/$norm_y+5, $enmap->colorAllocate(255,0,0));

	$enmap->arc(($base_x * $display_x)/$norm_x,
		($base_y * $display_y)/$norm_y,
		2 * int(($sensor_comm_radius * $display_x)/$norm_x),
		2 * int(($sensor_comm_radius * $display_y)/$norm_y),
		0, 360, $enmap->colorAllocate(0,0,0));

	my $image_file = undef;
	my $image_enmap = undef;
	if ($ref < 10){
		$ref = join ('', "0", $ref);
		$image_file = join('.', "set", $ref, "svg");
		$image_enmap = join('.', "enmap", $ref, "svg");
	}else{
		$image_file = join('.', "set", $ref, "svg");
		$image_enmap = join('.', "enmap", $ref, "svg");
	}

	open(FILEOUT, ">$image_file") or
		die "could not open file $image_file for writing!";
	binmode FILEOUT;
	print FILEOUT $im->svg;
	close FILEOUT;

	open(FILEOUT, ">$image_enmap") or
		die "could not open file $image_enmap for writing!";
	binmode FILEOUT;
	print FILEOUT $enmap->svg;
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
