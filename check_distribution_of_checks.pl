#!/usr/bin/env perl 
#===============================================================================
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
sub testSuit1();
#sub test1($);

my $usage ='
Usage:
my-program <input-file-name>

-q get data from mon qh
';

our ($opt_d, $opt_w, $opt_c, $opt_h, $opt_q, $opt_f, $opt_t);
getopts('dw:c:hqf:t');

if ( $opt_h ) {
    print $usage;
    exit 1;
}

my ($file1) = $opt_f;
my %file_1_hash;
my %line_hash;
my %next_check_hash;
my %check_interval_hash;
my %interval_value_count_hash;
my $line;
my $line_counter = 0;
my $show_match = 0;

my $start_time = time();
my $perfdata;
my $return_string;
my $return_string_long;
my $exit_code = 0;
my $warning = 2;
my $critical = 20;

if ( $opt_w ) {
    $warning = $opt_w;
}
if ( $opt_c ) {
    $critical = $opt_c;
}
if ( $opt_t ) {
    testSuit1();
    exit 0;
}

my $tmp_file = "/tmp/mon_query_ls_nodes_$start_time.tmp.txt";
if ( $opt_q ) {
    ` asmonitor mon query ls services -c host_name,description,next_check,check_interval > $tmp_file `;
    $file1 = $tmp_file;
}

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
unlink $tmp_file;

#sort each row per interval
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
foreach my $interval (sort { $a <=> $b } keys %interval_value_count_hash) {
    my $min = -1;
    my $max = -1;
    my $vector = vector();
    my $variance = 0;
    my $count = 0;
    foreach my $line (keys %check_interval_hash) {
        if($check_interval_hash{$line} == $interval) {
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
        my $interval_string .= "mean/max: $mean/$dist_max; ";
        $return_string_long .= "interval: $interval count: $count min: $min max: $max diff: $diff variance: $variance stddev: $stddev dist_max: $dist_max";
        $perfdata .= "variance$interval=$variance stddev$interval=$stddev mean$interval=$mean dist_max$interval=$dist_max ";

        my $optimal = optimalDistribution(($interval*60), $count);
        my ($opti_variance, $opti_stddev) = testStats($optimal->query);
        my ($opti_mean, $opti_dist_max) = testDistMean($optimal->query);
        $return_string_long .= " (OPTIMAL variance: $opti_variance stddev: $opti_stddev dist_max: $opti_dist_max)\n";
	my $int_exit_text = "int$interval:OK";
	my $int_exit_code = 0;
        #if (($opti_variance + $warning*100 < $variance || $opti_mean + $warning < $mean) and $exit_code < 1) {
        if (($opti_mean + $warning < $mean || $opti_dist_max + $warning < $dist_max)) {
            $int_exit_code = 1;
            $int_exit_text = "int$interval:WARNING";
        }
        #if (($opti_variance + $critical*100 < $variance || $opti_mean + $critical < $mean) and $exit_code < 2) {
        if (($opti_mean + $critical < $mean || $opti_dist_max + $critical < $dist_max)) {
            $int_exit_code = 2;
            $int_exit_text = "int$interval:CRITICAL";
        }
	if ($exit_code < $int_exit_code) {
	    $exit_code = $int_exit_code;
	}
	
	$return_string .= "$int_exit_text" . " $interval_string";
    }
}

print "$return_string | $perfdata \n";
print "$return_string_long";

exit $exit_code;

# optimalDistribution for specified count and interval 
sub optimalDistribution($$) {
    my($interval, $count) = @_;
    my $vector=vector();
    my $mod = $interval / $count;
    #my @copy_of_contents;
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
        #@copy_of_contents = $vector->query;
    }
    my $size = $vector->query_size();
    print "size: $size \n" if $opt_d;
    return $vector;
}

sub testDistMean($) {
    # http://search.cpan.org/~shlomif/Statistics-Descriptive-3.0613/lib/Statistics/Descriptive.pm
    my $vector=vector();
    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data(@_);
    
    #my $min = min( @{ $_[0]} );
    #my $max = max( @{ $_[0]} );
    #my $interval = $max - $min + 1;

    my $f = $stat->frequency_distribution_ref(100);
    for (sort {$a <=> $b} keys %$f) {
       print "key = $_, count = $f->{$_}\n" if $opt_d;
       $vector->append(int($f->{$_}));
    }
    #print "    dist Stats: ";
    #my ($variance, $stddev) = testStats($vector);
    print "mean: " . mean($vector) . "\n" if $opt_d;
	return (mean($vector), max($vector->query));
}

sub testStats($) {
    # http://search.cpan.org/~jettero/Statistics-Basic-1.6611/lib/Statistics/Basic.pod
    
    my $vector = vector(@_);
    
    my $var  = variance($vector);
    my $stddev =  stddev($vector);
    #print "vector $vector \n";
    #print "Variance $var std dev $stddev \n";
    # print " . "\n";
    return ($var, $stddev);
}

sub testSuit1() {
    
    my @test = (1,1,1,1,1,1);
    test1(@test);
    @test = (1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2);
    test1(@test);
    @test = (1..5, 50, 100);
    test1(@test);
    @test = (50, 100);
    test1(@test);
    @test = (1..50, 1..50);
    test1(@test);
    @test = (1..10, 1..10, 1..100);
    test1(@test);
    @test = (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 100..1000);
    test1(@test);
    
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    print "*** Test \n";
#    @test = (1,1,1,2,2,2);
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    print "*** Test \n";
#    @test = (1..5);
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    print "*** Test \n";
#    @test = (1..50);
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    print "*** Test \n";
#    @test = (1..500);
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    print "*** Test \n";
#    @test = (1,500);
#    ($variance, $stddev) = testDist(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    ($variance, $stddev) = testStats(\@test);
#    print "var: $variance stddev: $stddev; \n";
#    
#    @test = (1,1);
#    my $covariance = covariance( \@test, \@test );
#    print "cov: $covariance \n";
#    
#    @test = (1..10);
#    $covariance = covariance( \@test, \@test );
#    print "cov: $covariance \n";
    
}

sub test1 {
    print "*** Test \n";
    #my @test = shift;
    my (@test) = @_;
    #print "passed: @test; \n";
    my ($variance, $stddev, $mean) = 0;
    my $min = min @test;
    my $max = max @test;
    my $interval = ($max - $min + 1);
    my $size = 0+@test;
    
    print "min: $min max: $max size: $size interval: $interval \n";
    
    
    print join(", ", @test) . "\n";
    $mean = testDistMean(\@test);
    ($variance, $stddev) = testStats(\@test);
    print "var: $variance stddev: $stddev mean: $mean; \n";

   
    my $optimal = optimalDistribution($interval, $size);
    $mean = testDistMean($optimal->query);
    ($variance, $stddev) = testStats($optimal->query);
    print "OPT var: $variance stddev: $stddev mean: $mean; \n";
    print join(", ", $optimal->query) . "\n" if $opt_d;
    print "\n";
}
