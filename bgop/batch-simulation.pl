#!/usr/bin/perl -w
#
# Batch Simulation Script
#
# by Dimitris Glynos (daglyn/at/unipi/gr)
# Distributed under the GPLv3 license (see LICENSE file)

use strict;
use Cwd qw ( abs_path getcwd );

my $progress_report = 0;

my %simulation = ();

$simulation{"4classes"}{"cmdline"} = "./sim_4classes.pl %f";
$simulation{"4classes"}{"working_dir"} = ".";
$simulation{"4classes"}{"time_pattern"} = '# Algorithm running time: ([0-9]+\.[0-9]+)';
$simulation{"4classes"}{"sets_pattern"} = '# Number of generated sets ([0-9]+)';

$simulation{"adaptive"}{"cmdline"} = "./sim_adaptive.pl %f";
$simulation{"adaptive"}{"working_dir"} = ".";
$simulation{"adaptive"}{"time_pattern"} = '# Algorithm running time: ([0-9]+\.[0-9]+)';
$simulation{"adaptive"}{"sets_pattern"} = '# Number of generated sets ([0-9]+)';

$simulation{"slijepcevic"}{"cmdline"} = "java Simulation f %f";
$simulation{"slijepcevic"}{"working_dir"} = "./slijepcevic";
$simulation{"slijepcevic"}{"time_pattern"} = '# time ([0-9]+\.[0-9]+)';
$simulation{"slijepcevic"}{"sets_pattern"} = '# generated sets ([0-9]+)';

die "usage: batch-simulation.pl <num_of_runs> <file1> <file2> .. <fileN>\n"
	unless (@ARGV > 1);

my $simul_runs = shift @ARGV;
my $pwd = getcwd();

foreach my $file (@ARGV){
	$file = abs_path($file);
	foreach my $simula (keys %simulation){
		my $min_time = 99999999.0;
		my $max_sets = 0;

		chdir($simulation{$simula}{"working_dir"});
		for (my $run = 0; $run < $simul_runs; $run++){
			my $time = -1.0;
			my $sets = -1;
			my $exec = $simulation{$simula}{"cmdline"};
			my $context = sprintf("simulation '%s' (file %s, run %i)",
				$simula, $file, $run);

			$exec =~ s/\%f/$file/;

			my $output = `$exec`;

			die "Error: $context exited with code ".($? >> 8).
				", output was:\n$output" if ($?);
			if ($output =~ /$simulation{$simula}{"time_pattern"}/){
				$time = $1;
				if ($time < $min_time){
					$min_time = $time;
				}
			}

			if ($output =~ /$simulation{$simula}{"sets_pattern"}/){
				$sets = $1;
				if ($sets > $max_sets){
					$max_sets = $sets;
				}
			}

			if (($time == -1.0) || ($sets == -1)){
				die "Error: $context did not provide time or set stats!\n";
			}
			printf STDERR ("processed %s %15s %4i sets %.6f sec run %i\n", 
				$file, $simula, $sets, $time, $run) if ($progress_report);
		}
		printf "%s %15s %4i sets %.3f sec %.3f sec/set\n", $file, $simula, $max_sets, $min_time , ($max_sets)?$min_time/$max_sets:0;
		chdir($pwd);
	}
}

# $Id: batch-simulation.pl 623 2009-02-23 19:31:53Z glynos $
