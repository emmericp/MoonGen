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

my $total = 0;
foreach my $l (@lines) {
    my ($latency, $count) = split(/[\,\s]+/,$l);
    $total += $count;
}

foreach my $l (@lines) {
    my ($latency, $count) = split(/[\,\s]+/,$l);
    print "$latency\t$count\t".((1.0*$count)/(1.0*$total))."\n";
}



