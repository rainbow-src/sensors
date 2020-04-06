#!/usr/bin/perl -w

my $a = 0;
my $b = 0;
my $file = shift @ARGV;
printf "#a\t b\t c\t sets\n";
for ($a = 0.02; $a < 0.99; $a+=0.02){
        for ($b = 0.02; $b < 0.99; $b+=0.02){
                if ($a + $b < 0.99){
                        my $sets = -1;
                        my $exec = "../../dynamic-ccf.pl 1 $a $b $file";
                        my $output = `$exec`;

                        if ($output =~ /# Total network lifetime: ([0-9]+\.[0-9]+)/){
                                $sets = $1;
                        }
                        printf "%.2f\t %.2f\t %.2f\t %.2f\n", $a, $b, 1-$a-$b, $sets;
                }
        }
        printf "\n";
}
