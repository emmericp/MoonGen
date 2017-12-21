#!/usr/bin/env perl

use strict;

if (@ARGV != 1) {
    print "usage: $0 <input_file>\n";
    exit(0);
}

my $FH;
open($FH, "<$ARGV[0]") || die "ERROR: unable to open $ARGV[0]\n";
my @lines = <$FH>;
close($FH);

chomp(@lines);

# some scripts record latency in msec and some in usec.
# just guess which it is based on the first latency value.
my $t_factor = 1.0e-3;
my ($latency, $count) = split(/[\,\s]+/,$lines[0]);
#if ($latency > 100000000) {
#    $t_factor = 1.0e-6;
#}

my $total = 0;
foreach my $l (@lines) {
    ($latency, $count) = split(/[\,\s]+/,$l);
    $total += $count;
}

foreach my $l (@lines) {
    ($latency, $count) = split(/[\,\s]+/,$l);
    print "".($latency*$t_factor)."\t$count\t".((1.0*$count)/(1.0*$total))."\n";
}



