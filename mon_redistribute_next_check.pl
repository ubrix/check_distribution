#!/usr/bin/env perl 
#===============================================================================
# REQUIREMENTS: # yum install perl-Statistics-Basic perl-Statistics-Descriptive
#       AUTHOR: Jonatan Sundeen 
#===============================================================================

use strict;
use warnings;
use utf8;
use Getopt::Std;
use Statistics::Descriptive;
use Statistics::Basic qw(:all);
use List::Util qw( min max );

sub testStats($);
sub optimalDistribution($$);
sub testDistMean($);
sub printCmd($@);

my $usage ='
Usage:
my-program <input-file-name>

Prints distribution of checks with option to force redistribution.
Gets data from using "mon query ls" command

-f force redistribute
';

our ($opt_d, $opt_h, $opt_f);
getopts('dhf');

if ( $opt_h ) {
    print $usage;
    exit 1;
}

my %file_1_hash;
my %line_hash;
my %next_check_hash;
my %check_interval_hash;
my %interval_value_count_hash;
my $line;
my $line_counter = 0;
my $show_match = 0;
my $perfdata;
my $return_string;
my $return_string_long;

my $start_time = time();

my $file1 = "/tmp/mon_query_ls_nodes_$start_time.tmp.txt";
` asmonitor mon query ls services -c host_name,description,next_check,check_interval > $file1 `;

#read the file into a hash 
open (FILE1, "<$file1") or die "can't open file $file1\n";
while ($line=<FILE1>){
    chomp ($line);
    $line_counter++;
    if (!($line =~ m/^\s*$/)){
        $file_1_hash{$line_counter}=$line;
    }
}
close (FILE1);
unlink $file1;

#hash rows
# TODO: make sub
foreach my $line (sort { $a <=> $b } keys %file_1_hash) {
    
    my @row = split(/;/,$file_1_hash{$line});
    my $host = $row[0];
    my $service = $row[1];
    my $next_check = $row[2];
    my $check_interval = $row[3] + 0;
    
    $check_interval_hash{"$host;$service"} = $check_interval;
    $next_check_hash{"$host;$service"} = $next_check;
    $interval_value_count_hash{$check_interval}++;
}
undef %file_1_hash;

# Process per interval
# TODO: make sub
foreach my $interval (sort { $a <=> $b } keys %interval_value_count_hash) {
    my $min = -1;
    my $max = -1;
    my $vector = vector();
    my $variance = 0;
    my $count = 0;
    foreach my $line (keys %check_interval_hash) {
        if($check_interval_hash{$line} == $interval && $interval > 0) {
            $vector->append($next_check_hash{$line});
            
            if ($min > $next_check_hash{$line} || $min < 0) {
                $min = $next_check_hash{$line} 
            }
            if ($max < $next_check_hash{$line} || $max < 0) {
                $max = $next_check_hash{$line} 
            }
            $count++;
        }
    }
    if ($vector->query_size() > 1) {
        my $diff = $max - $min;
        my ($variance, $stddev) = testStats($vector->query);
        my ($mean, $dist_max) = testDistMean($vector->query);
        $return_string .= "int: $interval mean: $mean; ";
        $return_string_long .= "interval: $interval count: $count min: $min max: $max diff: $diff variance: $variance stddev: $stddev mean: $mean dist_max: $dist_max";
        $perfdata .= "variance$interval=$variance stddev$interval=$stddev mean$interval=$mean ";

        my $optimal = optimalDistribution(($interval*60), $count);
        my ($opti_variance, $opti_stddev) = testStats($optimal->query);
        my ($opti_mean, $opti_dist_max) = testDistMean($optimal->query);
        $return_string_long .= " (OPTIMAL variance: $opti_variance stddev: $opti_stddev mean: $opti_mean dist_max: $opti_dist_max)\n";

        my @copy_of_contents = $optimal->query;
        printCmd($interval, @copy_of_contents);
    }
}

print "$return_string | $perfdata \n";
print "$return_string_long";


# optimalDistribution for specified count and interval 
sub optimalDistribution($$) {
    my($interval, $count) = @_;
    my $vector=vector();
    my $mod = $interval / $count;
    print "optimal \n" if $opt_d;
    if ($mod < 1) {
        $mod = 1;
    }
    for (my $n = 0; $n < $count; $n++) {
        my $step = int($mod + $mod*$n);
        if ($step >= $interval && $interval > 0) {
            $mod = $interval / ($count-$n);
            $count = $count - $n;
            $n = 0;
            $step = 0;
        }
        print "$n $step \n" if $opt_d;
        $vector->append($step);
    }
    my $size = $vector->query_size();
    print "size: $size \n" if $opt_d;
    return $vector;
}

sub testDistMean($) {
    my $vector=vector();
    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data(@_);
    my $f = $stat->frequency_distribution_ref(100);
    for (sort {$a <=> $b} keys %$f) {
       print "key = $_, count = $f->{$_}\n" if $opt_d;
       $vector->append(int($f->{$_}));
    }
    print "mean: " . mean($vector) . "\n" if $opt_d;
    return (mean($vector), max($vector->query));
}

sub testStats($) {
    my $vector = vector(@_);
    
    my $var  = variance($vector);
    my $stddev =  stddev($vector);
    return ($var, $stddev);
}

sub printCmd($@) {
    my ($interval, @optimalSteps) = @_;
    my $margin = 1;
    
    foreach my $line (keys %check_interval_hash) {
        if($check_interval_hash{$line} == $interval) {
            my $now = time();
            my $step = shift @optimalSteps;
            my $next_check = $margin + $now + $step;
            my $command = "mon qh query command run \"[\$(date +%s)] SCHEDULE_FORCED_SVC_CHECK;$line;$next_check\"";
            print $command . "\n" if $opt_d;
            my $result = ` $command ` if $opt_f;
        }
    }
    print "\n";
}
