#!/usr/bin/perl -w
#
# Script to create a connected 2D terrain of sensors and targets
#
# Author: Dimitrios Zorbas (jim/at/students/cs/unipi/gr)
# based on the terrain generator of D. Glynos
# Distributed under the GPLv3 (see LICENSE file)

use Graph;
use Math::Random;
use strict;

my $SHOW_PROGRESS=1; # make this 0 if you don't want to see anything on STDERR

# We use decimeter precision (1/10th of a meter). No two sensors shall occupy
# the same square decimeter.

my $sensor_reading_radius = 10 * 10; 	# in deci-meters
my $sensor_comm_radius = 50 * 10; 	# in deci-meters

my ($terrain_x, $terrain_y) = (1000 * 10, 1000 * 10); 	# 1km by 1km terrain

sub progress_bar {
	my $title = shift;
	my $cur_progress = shift;
	my $max_progress = shift;
	my $prev_progress = shift;

	return unless $SHOW_PROGRESS;

	return $max_progress if ($prev_progress == $max_progress);

	if ($cur_progress == 0){
		printf STDERR "%35s [", $title;
	} elsif ($cur_progress == $max_progress){
		printf STDERR ".] Done!\n";
	} else {
		my $change = int ((10*($cur_progress - $prev_progress))/ $max_progress);
		if ($change >= 1){
			print STDERR "." x $change;
			$prev_progress = $cur_progress;
		}
	}
	return $prev_progress;
}

sub distance {
	my ($x1, $x2, $y1, $y2) = @_;

	return sqrt( (($x1-$x2)*($x1-$x2))
			+(($y1-$y2)*($y1-$y2)) );
}

sub random_int {
	my $low = shift;
	my $high = shift;

	return Math::Random::random_uniform_integer(1, $low, $high);
}

(@ARGV==3) || die "usage: $0 <num_of_nodes> <num_of_points> <area_of_interest%>\n";

my $num_nodes = $ARGV[0];
my $num_points = $ARGV[1];
my $density = $ARGV[2]/100;

(($num_nodes < 2) || ($num_points < 2)) && die "num_nodes and num_points must be greater than two!\n";
(($density <= 0) || ($density > 100)) && die "area of interest must lie between 0 < x <= 100.0\n";

my $norm_x = int($terrain_x * $density);	# normalised terrain_x
my $norm_y = int($terrain_y * $density); 	# normalised terrain_y

my $base_x = int($norm_y / 2);	# x location of base node
my $base_y = int($norm_y / 2);	# y location of base node

my @points; 	# all generated points
my @nodes;  	# all generated nodes
my %areas;  	# areas currently examined

my $stats_state = 0;
my $stats_cnt = 0;
my $stats_total = 0;



### GENERATING POINTS ###

my %points_temp = ();
($stats_state, $stats_total) = (0, $num_points - 1);
for(my $i=1; $i<=$num_points; $i++){
	my ($x, $y) = (random_int(1+$sensor_reading_radius, $norm_x-$sensor_reading_radius),
		       random_int(1+$sensor_reading_radius, $norm_y-$sensor_reading_radius));

	while (exists $points_temp{$x}{$y}){
		($x, $y) = (random_int(1+$sensor_reading_radius, $norm_x-$sensor_reading_radius),
		       random_int(1+$sensor_reading_radius, $norm_y-$sensor_reading_radius));
	}
	$points_temp{$x}{$y} = 1;
	push(@points, [$x, $y] );
	$stats_state = progress_bar("Generating Points:",
		$i-1, $stats_total, $stats_state);
}

### GENERATING SENSORS ###

my %nodes_temp = ();
($stats_state, $stats_total) = (0, $num_nodes - 1);
for(my $i=1; $i<=$num_nodes; $i++){
	my ($x,$y) = (random_int(1, $norm_x), random_int(1, $norm_y));

	while (exists $nodes_temp{$x}{$y}){
		($x, $y) = (random_int(1, $norm_x), random_int(1, $norm_y));
	}
	$nodes_temp{$x}{$y} = 1;
	push(@nodes, [$x, $y]);
	$stats_state = progress_bar("Generating Sensors:",
			$i-1, $stats_total, $stats_state);
}



### GATHERING SENSORS THAT ARE WITHIN POINT RANGE ###
my %all_nodes = ();
($stats_state, $stats_total) = (0, scalar @nodes - 1);
for(my $node_num=1; $node_num <= (scalar @nodes); $node_num++){
	$all_nodes{$node_num} = $node_num;
	my ($node_x, $node_y) = @{$nodes[$node_num-1]};
	my $point_idx = "A";
	foreach my $point (@points){
		my ($point_x, $point_y) = @$point;
		if (distance($node_x, $point_x, $node_y, $point_y) < $sensor_reading_radius){
			if ( (!exists $areas{$point_idx})
				|| (!exists $areas{$point_idx}{nodes}))
			{
				$areas{$point_idx}{nodes} = [];
				$areas{$point_idx}{location} = $point;
			}
			push(@{$areas{$point_idx}{nodes}}, $node_num);
		}
		$point_idx++;
	}

	$stats_state = progress_bar("Sensors in area check:", $node_num-1,
		$stats_total, $stats_state);
}


### CREATE SENSOR GRAPH ###

# create a graph of all sensors and exclude any point not be able to be monitored

my $graph = Graph::Undirected->new;
($stats_state, $stats_total, $stats_cnt) = (0, (scalar keys %all_nodes) - 1, 0);

foreach my $nd (keys %all_nodes){
	my ($nd_x, $nd_y) = @{$nodes[$nd-1]};
	my $touched = 0;
	if (distance($nd_x, $base_x, $nd_y, $base_y) <=	$sensor_comm_radius){
		$graph->add_edge($nd, "bs");
		$touched++;
	}

	foreach my $nd_t (keys %all_nodes){
		next if ($nd_t == $nd);
		my ($nd_t_x, $nd_t_y) = @{$nodes[$nd_t-1]};
		if (distance($nd_x, $nd_t_x, $nd_y, $nd_t_y) <= $sensor_comm_radius){
			$graph->add_edge($nd, $nd_t);
			$touched++;
		}
	}

	if (!$touched){
 		delete $all_nodes{$nd};
		foreach my $area (keys %areas){
			foreach my $s (@{$areas{$area}{nodes}}){
				if ($s == $nd){
					my $index = -1;
					for (my $i=0; $i<@{$areas{$area}{nodes}}; $i++){
						if ($areas{$area}{nodes}[$i] == $s){
							$index = $i;
						}
					}
					delete $areas{$area}{nodes}[$index];
					if (scalar @{$areas{$area}{nodes}} == 0){
						delete $areas{$area}{nodes};
						delete $areas{$area}{location};
						delete $areas{$area};
					}
				}
			}
		}
 	}

	$stats_state = progress_bar("Deleting Solitary Sensors:",
		$stats_cnt, $stats_total, $stats_state);
	$stats_cnt++;
}



### REMOVE BASE-UNREACHABLE SENSORS ###

($stats_state, $stats_total, $stats_cnt) = (0, (scalar keys %all_nodes)-1, 0);

foreach my $n (keys %all_nodes){
	if (!$graph->same_connected_components($n, "bs")){
		delete $all_nodes{$n};
		$graph->delete_vertex($n);
		foreach my $area (keys %areas){
			foreach my $s (@{$areas{$area}{nodes}}){
				if ($s == $n){
					my $index = -1;
					for (my $i=0; $i<@{$areas{$area}{nodes}}; $i++){
						if ($areas{$area}{nodes}[$i] == $s){
							$index = $i;
						}
					}
					delete $areas{$area}{nodes}[$index];
					if (scalar @{$areas{$area}{nodes}} == 0){
						delete $areas{$area}{nodes};
						delete $areas{$area}{location};
						delete $areas{$area};
					}
				}
			}
		}
	}

	$stats_state = progress_bar("Deleting base-unreachable areas:",
	$stats_cnt, $stats_total, $stats_state);
	$stats_cnt++;
}


### PRINT AREAS, COLLECT STATISTICS ###

my $min_cardinality = $num_nodes;
my $max_times_seen = 0;
my $mean_times_seen = 0;
my $min_times_seen = $num_points;
my %seen;

foreach my $area (sort keys %areas){
	my $i = 0;

	printf "%s", $area;

	foreach my $node_num (@{$areas{$area}{nodes}}){
		if (exists $seen{$node_num}){
			$seen{$node_num}{times}++;
		} else {
			$seen{$node_num}{times} = 1;
			$seen{$node_num}{location} = $nodes[$node_num-1];
		}

		if ($seen{$node_num}{times} > $max_times_seen){
			$max_times_seen = $seen{$node_num}{times};
		}

		if ($seen{$node_num}{times} < $min_times_seen){
			$min_times_seen = $seen{$node_num}{times};
		}

		print " $node_num";
		$i++;
	}

	if ($i < $min_cardinality){
		$min_cardinality = $i;
	}
	print "\n";
}

printf "# terrain map [%i x %i]\n", $norm_x, $norm_y;

print "# sensor coords:";
foreach my $tmp_node (keys %seen){
	$mean_times_seen += ( $seen{$tmp_node}{times} / (scalar keys %seen) );
}
foreach my $nd (sort keys %all_nodes){
	my ($x, $y) = @{$nodes[$nd-1]};
	printf " %i [%i %i]", $nd, $x, $y;
}
print "\n";

print "# target coords:";
foreach my $pt (keys %areas){
	my ($x, $y) = @{$areas{$pt}{location}};
	printf " %s [%i %i]", $pt, $x, $y;
}
print "\n";

printf "# base station coords: [%i %i]\n", $base_x, $base_y;


if ((scalar keys %seen) == 0){
	$min_times_seen = 0;
	$min_cardinality = 0;
}

print  	"# generated with: $0 ",join(" ",@ARGV),"\n";
printf 	"# stats: sensors=%i points=%i min_cardinality=%i ".
       	"min_node_occur=%i max_node_occur=%i mean_node_occur=%.1f ".
	"terrain=%.1fm^2 sensor_sz=%.2fm^2 sensor_reading_radius=%.2fm ".
	"sensor_comm_radius=%.2fm\n",
	scalar keys %seen, scalar keys %areas, $min_cardinality,
	$min_times_seen, $max_times_seen, $mean_times_seen,
	($norm_x * $norm_y) / 100, 0.1 * 0.1, $sensor_reading_radius / 10,
	$sensor_comm_radius / 10;
printf "# Graph: %s\n", $graph;
printf 	"# %s\n", '$Id: generate_fc_terrain-center.pl 1480 2011-01-23 21:36:54Z jim $';
