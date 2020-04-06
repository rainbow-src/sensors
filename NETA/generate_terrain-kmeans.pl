#!/usr/bin/perl -w
# Script for targets, sensors and base stations generation
# Distributed under the GPLv3 (see LICENSE file)

use strict;
use GD::SVG;
use Math::Random;
use Algorithm::Cluster;

# We use decimeter precision (1/10th of a meter). No two sensors shall occupy
# the same square decimeter.

my $sensor_reading_radius = 10 * 10; 	# in deci-meters
my $sensor_comm_radius = 50 * 10; 	# in deci-meters

my ($terrain_x, $terrain_y) = (1000 * 10, 1000 * 10); 	# 1km by 1km terrain

sub distance {
	my ($x1, $x2, $y1, $y2) = @_;
	return sqrt( ($x1-$x2)*($x1-$x2) + ($y1-$y2)*($y1-$y2) );
}

sub random_int {
	my $low = shift;
	my $high = shift;

	return Math::Random::random_uniform_integer(1, $low, $high);
}

(@ARGV==5) || die "usage: $0 <num_of_bs's> <num_of_targets> <num_of_nodes> <density> <output_file.svg>\n";

my $num_bs = $ARGV[0];
my $num_points = $ARGV[1];
my $num_nodes = $ARGV[2];
my $density = $ARGV[3]/100;
my $output_file = $ARGV[4];

(($num_bs < 1) || ($num_points < 1)) && die "num_nodes and num_points must be greater than one!\n";
(($density <= 0) || ($density > 100)) && die "area of interest must lie between 0 < x <= 100.0\n";

my $norm_x = int($terrain_x * $density);        # normalised terrain_x
my $norm_y = int($terrain_y * $density);        # normalised terrain_y

my $stats_state = 0;
my $stats_cnt = 0;
my $stats_total = 0;

my @named_nodes = ();
my @targets = ();
my @named_targets = ();
my %target_cid = ();
my @sinks = ();
my @mask1 = ();
my %areas = ();


### GENERATING TARGETS ###

my %points_temp = ();
my $tid = "A";
for(my $i=1; $i<=$num_points; $i++){
	my ($x, $y) = (random_int(1+$sensor_reading_radius, $norm_x-$sensor_reading_radius),
		random_int(1+$sensor_reading_radius, $norm_y-$sensor_reading_radius));

	while (exists $points_temp{$x}{$y}){
		($x, $y) = (random_int(1+$sensor_reading_radius, $norm_x-$sensor_reading_radius),
			random_int(1+$sensor_reading_radius, $norm_y-$sensor_reading_radius));
	}
	$points_temp{$x}{$y} = 1;
        push(@named_targets, [$tid, $x, $y]);
	$tid++;
}


### GENERATING SENSORS ###

my %nodes_temp = ();
for(my $i=1; $i<=$num_nodes; $i++){
	my ($x,$y) = (random_int(1, $norm_x), random_int(1, $norm_y));

	while (exists $nodes_temp{$x}{$y}){
		($x, $y) = (random_int(1, $norm_x), random_int(1, $norm_y));
	}
	$nodes_temp{$x}{$y} = 1;
	push(@named_nodes, [$i, $x, $y]);
}


### GATHERING SENSORS THAT ARE WITHIN TARGET RANGE ###

my @covered_targets = ();
foreach my $t (@named_targets){
	my ($tid, $tx, $ty) = @$t;
	$areas{$tid} = [];
	foreach my $n (@named_nodes){
		my ($nid, $nx, $ny) = @$n;
		if (distance($nx, $tx, $ny, $ty) < $sensor_reading_radius){
			push (@{$areas{$tid}}, $nid);
		}
	}
	if (scalar @{$areas{$tid}} != 0){
		push (@covered_targets, $t);
		push (@targets, [$tx, $ty]);
	}
}
@named_targets = @covered_targets;

### CLUSTERING PROCESS ###

for (my $i = 0; $i < scalar @targets; $i++){
	push(@mask1, [1, 1]);
}

my $weight1 = [1, 1];

my %parameters = (nclusters => $num_bs, data => \@targets, mask => \@mask1, weight => $weight1, transpose => 0, npass => 10, method => 'a', dist => 'e', initialid => []);
my ($clusters, $error, $found) = Algorithm::Cluster::kcluster(%parameters);

my @temp_named_targets = @named_targets;
foreach my $c (@$clusters){
	my $t = shift(@temp_named_targets);
	my ($name, $x, $y) = @$t;
	my $tc = $name;
	if ($c < 9){
		$tc = join('','S0',$c+1);
	}elsif ($c >= 9){
		$tc = join('','S',$c+1);
	}
	$target_cid{$name} = $tc;
#	printf "Target %s belongs in cluster %s\n", $name, $c;
}

if ($found == 0){
	printf "No optimal solution found!\n";
	exit;
}

my %c_parameters = (data => \@targets, mask => \@mask1, weight => $weight1, clusterid => $clusters, method => 'a', transpose => 0);
my ($cdata, $cmask) = Algorithm::Cluster::clustercentroids(%c_parameters);

my $i = "S01";
foreach my $c (@$cdata){
	my ($x, $y) = @$c;
	push (@sinks, [$i, $x, $y]);
	$i++;
}


### DISPLAY TERRAIN IN A SVG RESULT FILE ###

my ($display_x, $display_y) = (800, 800); # 800x800 pixel display pane
my $im = new GD::SVG::Image($display_x, $display_y);
my $white = $im->colorAllocate(255,255,255);
my $blue = $im->colorAllocate(0,0,255);
my $green = $im->colorAllocate(200,255,200);
my $black = $im->colorAllocate(0,0,0);
my $red = $im->colorAllocate(255,0,0);

foreach my $c (@sinks){
	my ($cid, $x, $y) = @$c;
	$im->filledRectangle( ($x * $display_x)/$norm_x-5, ($y * $display_y)/$norm_y-5,
		($x * $display_x)/$norm_x+5, ($y * $display_y)/$norm_y+5, $red);
}

foreach my $t (@named_targets){
	my ($s, $x, $y) = @$t;
	($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));

	$im->rectangle($x-5, $y-5, $x+5, $y+5, $red);
	$im->string(gdMediumBoldFont,$x-2,$y-20,$s,$blue);

	foreach my $c (@sinks){
		my ($cid, $cx, $cy) = @$c;
		($cx, $cy) = (int(($cx * $display_x)/$norm_x), int(($cy * $display_y)/$norm_y));
		if ($target_cid{$s} eq $cid){
			$im->line($x, $y, $cx, $cy, $green);
		}
	}
}

foreach my $sensor (@named_nodes){
	my ($s, $x, $y) = @$sensor;
	($x, $y) = (int(($x * $display_x)/ $norm_x), int(($y * $display_y)/ $norm_y));

	$im->string(gdSmallFont,$x-2,$y-12,$s,$black);
	$im->filledRectangle($x-1, $y-1, $x+1, $y+1, $black);
}

open(FILEOUT, ">$output_file") or die "could not open file $output_file for writing!";
binmode FILEOUT;
print FILEOUT $im->svg;
close FILEOUT;


### PRINT STATISTICS ###

my $min_cardinality = $num_nodes;
my $max_times_seen = 0;
my $mean_times_seen = 0;
my $min_times_seen = $num_points;
my %seen;

foreach my $t (sort @named_targets){
	my ($tid, $x, $y) = @$t;
	my $i = 0;

	printf "%s", $tid;

	foreach my $nid (@{$areas{$tid}}){
		if (exists $seen{$nid}){
			$seen{$nid}{times}++;
		} else {
			$seen{$nid}{times} = 1;
		}

		if ($seen{$nid}{times} > $max_times_seen){
			$max_times_seen = $seen{$nid}{times};
		}

		if ($seen{$nid}{times} < $min_times_seen){
			$min_times_seen = $seen{$nid}{times};
		}

		print " $nid";
		$i++;
	}

	if ($i < $min_cardinality){
		$min_cardinality = $i;
	}
	print "\n";
}

foreach my $tmp_node (keys %seen){
	$mean_times_seen += ( $seen{$tmp_node}{times} / (scalar keys %seen) );
}

printf "# terrain map [%i x %i]\n", $norm_x, $norm_y;

print "# target coords:";
foreach my $t (@named_targets){
	my ($id, $x, $y) = @$t;
	printf " %s [%i %i]", $id, $x, $y;
}
print "\n";

print "# sensor coords:";
foreach my $n (@named_nodes){
	my ($id, $x, $y) = @$n;
	printf " %s [%i %i]", $id, $x, $y;
}
print "\n";

printf "# base station coords:";
foreach my $c (@sinks){
	my ($id, $x, $y) = @$c;
	printf " %s [%i %i]", $id, $x, $y;
}
print "\n";


print  	"# generated with: $0 ",join(" ",@ARGV),"\n";

printf  "# stats: sensors=%i targets=%i base_stations=%i min_cardinality=%i ".
        "min_node_occur=%i max_node_occur=%i mean_node_occur=%.1f ".
        "terrain=%.1fm^2 sensor_sz=%.2fm^2 sensor_reading_radius=%.2fm ".
        "sensor_comm_radius=%.2fm\n",
        scalar keys %seen, scalar @named_targets, scalar @sinks, $min_cardinality,
        $min_times_seen, $max_times_seen, $mean_times_seen,
        ($norm_x * $norm_y) / 100, 0.1 * 0.1, $sensor_reading_radius / 10,
        $sensor_comm_radius / 10;

printf 	"# %s\n", '$Id: generate_terrain-kmeans.pl 1639 2011-04-15 17:40:49Z jim $';
