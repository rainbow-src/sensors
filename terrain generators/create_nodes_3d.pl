#!/usr/bin/perl -w
#
# Script to generate 3D terrain of sensors and targets
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# - Primary Author
# and Dimitrios Zorbas (jim/at/students/cs/unipi/gr)
# - Modifications for a-lifetime
# Distributed under the GPLv3 (see LICENSE file)

use Graph;
use Math::Random;
use strict;

my $SHOW_PROGRESS=1; # make this 0 if you don't want to see anything on STDERR

# We use decimeter precision (1/10th of a meter). No two sensors shall occupy
# the same square decimeter.

# both of these are considered in a sphere-like fashion

my $sensor_reading_radius = 10 * 10; 	# in deci-meters
my $sensor_comm_radius = 50 * 10; 	# in deci-meters

my ($terrain_x, $terrain_y, $terrain_z) = (1000 * 10, 1000 * 10, 100 * 10); # 1000m by 1000m by 100m terrain

sub progress_bar {
	my $title = shift;
	my $cur_progress = shift;
	my $max_progress = shift;
	my $prev_progress = shift;

	return unless $SHOW_PROGRESS;

	if ($max_progress == -1){
		printf STDERR "%35s (this might take a while)\n",$title;
		return 0;
	}

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
	my ($x1, $x2, $y1, $y2, $z1, $z2) = @_;

	return sqrt( (($x1-$x2)*($x1-$x2)) 
			+(($y1-$y2)*($y1-$y2)) + (($z1-$z2)*($z1-$z2)));
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
my $norm_z = int($terrain_z * $density);	# normalised terrain_z

my $base_x = 1;			# x location of base node
my $base_y = int($norm_y / 2);	# y location of base node
my $base_z = int($norm_z / 2);  # z location of base node

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
	my ($x, $y, $z) = (random_int(1, $norm_x), random_int(1, $norm_y),
			   random_int(1, $norm_z));

	while (exists $points_temp{$x}{$y}{$z}){
		($x, $y, $z) = (random_int(1, $norm_x), random_int(1, $norm_y),
			        random_int(1, $norm_z));
	}
	$points_temp{$x}{$y}{$z} = 1;
	push(@points, [$x, $y, $z] );
	$stats_state = progress_bar("Generating Points:", 
		$i-1, $stats_total, $stats_state);
}



### GENERATING SENSORS ###

my %nodes_temp = ();
($stats_state, $stats_total) = (0, $num_nodes - 1);
for(my $i=1; $i<=$num_nodes; $i++){
	my ($x,$y,$z) = (random_int(1, $norm_x), random_int(1, $norm_y),
			 random_int(1, $norm_z));

	while (exists $nodes_temp{$x}{$y}{$z}){
		($x, $y, $z) = (random_int(1, $norm_x), random_int(1, $norm_y),
				random_int(1, $norm_z));
	}
	$nodes_temp{$x}{$y}{$z} = 1;
	push(@nodes, [$x, $y, $z]);
	$stats_state = progress_bar("Generating Sensors:",
			$i-1, $stats_total, $stats_state);
}



### GATHERING SENSORS THAT ARE WITHIN POINT RANGE ###

($stats_state, $stats_total) = (0, scalar @nodes - 1);
for(my $node_num=1; $node_num <= (scalar @nodes); $node_num++){
	my ($node_x, $node_y, $node_z) = @{$nodes[$node_num-1]};
	my $point_idx = "A";
	foreach my $point (@points){
		my ($point_x, $point_y, $point_z) = @$point;
		if (distance($node_x, $point_x, $node_y, $point_y, 
			     $node_z, $point_z) < $sensor_reading_radius){
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



### CREATE AREA GRAPH ###

# create a graph of all areas and exclude any area not connected to any
# other (or the base station)

my $area_graph = Graph::Undirected->new;
($stats_state, $stats_total, $stats_cnt) = (0, (scalar keys %areas) - 1, 0);
foreach my $area (keys %areas){
	my ($area_x, $area_y, $area_z) = @{$areas{$area}{location}};
	my $touched = 0;

	if (distance($area_x, $base_x, $area_y, $base_y, $area_z, $base_z) <  
		( $sensor_comm_radius - $sensor_reading_radius) )
	{
		$area_graph->add_edge($area, "base");
		$touched++;
	}

	foreach my $area_temp (keys %areas){
		next if ($area_temp eq $area);

		my ($area_temp_x, $area_temp_y, $area_temp_z) = 
			@{$areas{$area_temp}{location}};

		if (distance($area_x, $area_temp_x, $area_y, $area_temp_y,
			     $area_z, $area_temp_z) <  
			( $sensor_comm_radius - (2*$sensor_reading_radius)) )
		{
			$area_graph->add_edge($area, $area_temp);
			$touched++;
		}	
	}

	if (!$touched){
		delete $areas{$area}{nodes};
		delete $areas{$area}{location};
		delete $areas{$area};
	}

	$stats_state = progress_bar("Deleting Solitary Areas:", 
		$stats_cnt, $stats_total, $stats_state);
	$stats_cnt++;
}



### REMOVE BASE-UNREACHABLE AREAS ###

progress_bar(sprintf("Check Connectivity and compute hops-parents for %i areas",scalar keys %areas),
	,0,-1,0);
my %hop = ();
my %parent = ();
# delete any area not being able to send to the base station
($stats_state, $stats_total, $stats_cnt) = (0, (scalar keys %areas)-1, 0);
my $tcg = $area_graph->APSP_Floyd_Warshall(attribute_name => 'height');
foreach my $area (keys %areas){

	if (!$area_graph->same_connected_components($area, "base")){
		delete $areas{$area}{nodes};
		delete $areas{$area}{location};
		delete $areas{$area};
		$area_graph->delete_vertex($area);
	}else{
		$hop{$area} = $tcg->path_length($area, "base");
		if ($hop{$area} > 1){
			$parent{$area} = $tcg->path_predecessor("base", $area);
		}else{
			$parent{$area} = "bs";
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

printf "# terrain map [%i x %i x %i]\n", $norm_x, $norm_y, $norm_z;
print "# sensor coords:";
foreach my $tmp_node (keys %seen){
	my ($x, $y, $z) = @{$seen{$tmp_node}{location}};
	$mean_times_seen += ( $seen{$tmp_node}{times} / (scalar keys %seen) );
	printf " %i [%i %i %i]", $tmp_node, $x, $y, $z;
}
print "\n";

print "# target coords:";
foreach my $pt (sort keys %areas){
	my ($x, $y, $z) = @{$areas{$pt}{location}};
	printf " %s [%i %i %i]", $pt, $x, $y, $z;
}
print "\n";

print "# hops:";
foreach my $pt (sort keys %areas){
	printf " %s [%d]", $pt, $hop{$pt};
}
print "\n";

print "# parent:";
foreach my $pt (sort keys %areas){
	printf " %s [%s]", $pt, $parent{$pt};
}
print "\n";

printf "# base station coords: [%i %i %i]\n", $base_x, $base_y, $base_z;


if ((scalar keys %seen) == 0){
	$min_times_seen = 0;
	$min_cardinality = 0;
}

print  	"# generated with: $0 ",join(" ",@ARGV),"\n";
printf 	"# stats: sensors=%i points=%i min_cardinality=%i ".
       	"min_node_occur=%i max_node_occur=%i mean_node_occur=%.1f ".
	"terrain=%.1fm^3 sensor_sz=%.3fm^3 ".
	"sensor_reading_radius=%.2fm sensor_comm_radius=%.2fm\n",
	scalar keys %seen, scalar keys %areas, $min_cardinality, 
	$min_times_seen, $max_times_seen, $mean_times_seen, 
	($norm_x * $norm_y * $norm_z)/1000 , 0.1 * 0.1 * 0.1, 
	$sensor_reading_radius / 10, $sensor_comm_radius / 10;
printf 	"# %s\n", '$Id: create_nodes_3d.pl 753 2009-05-10 14:27:42Z jim $';
