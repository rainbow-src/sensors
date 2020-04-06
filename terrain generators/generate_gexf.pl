#!/usr/bin/perl -w

use strict;

my $base_x = 0;
my $base_y = 0;
my @all_sensors = ();
my $temp_graph;

while(<>){
	if (/^# base station coords: \[([0-9]+) ([0-9]+)\]/){
		($base_x, $base_y) = ($1/10, $2/10);
	} elsif (/^# sensor coords: (.*)/){
		my $sens_coord = $1;
		my @coords = split(/\] /, $sens_coord);
		@all_sensors = map {/([0-9]+) \[([0-9]+) ([0-9]+)/; [$1, $2/10, $3/10];} @coords;
# 	} elsif (/^# target coords: (.*)/){
# 		my $target_coord = $1;
# 		my @coords = split(/\] /, $target_coord);
# 		@targets = map { /([A-Z]+) \[([0-9]+) ([0-9]+)/; [$1, $2, $3]; } @coords;
	} elsif (/^# Graph: (.*)/){
		$temp_graph = $1;
	}

	next if (/^\#/); # skip comments
}

print '<?xml version="1.0" encoding="UTF-8"?>';
print "\n";
print '<gexf xmlns="http://www.gexf.net/1.2draft" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.gexf.net/1.1draft http://www.gexf.net/1.2draft/gexf.xsd" version="1.2" xmlns:viz="http://www.gexf.net/1.1draft/viz">';
print "\n";
printf "<meta lastmodifieddate=\"%s\">\n</meta>\n", '$Id: generate_gexf.pl 1665 2011-05-30 12:42:36Z jim $';
print "<graph type=\"static\">\n";
print "<nodes>\n";

print "<node id=\"bs\" label=\"bs\">\n";
print "<viz:color r=\"255\" g=\"10\" b=\"10\"/>\n";
print "<viz:position x=\"$base_x\" y=\"$base_y\" z=\"0.0\"/>\n";
print "<viz:size value=\"8.0\"/>\n";
#print "<viz:shape value=\"disc\"/>\n";
print "</node>\n";

foreach my $sensor (@all_sensors){
	my ($s, $x, $y) = @$sensor;
	print "<node id=\"$s\" label=\"$s\">\n";
	print "<viz:color r=\"128\" g=\"128\" b=\"128\" a=\"0.6\"/>\n";
	print "<viz:position x=\"$x\" y=\"$y\" z=\"0.0\"/>\n";
	print "<viz:size value=\"4.0\"/>\n";
#	print "<viz:shape value=\"disc\"/>\n";
	print "</node>\n";
}

print "</nodes>\n";
print "<edges>\n";

my $i = 1;
my @edges = split(/,/, $temp_graph);
foreach my $edge (@edges){
	chomp ($edge);
	my ($v1, $v2) = split(/=/,$edge);
	print "<edge id=\"$i\" source=\"$v1\" target=\"$v2\" />\n";
	$i++;
}

print "</edges>\n";
print "</graph>\n";
print "</gexf>\n";