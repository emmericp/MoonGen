#!/usr/bin/env perl

use strict;

if (@ARGV == 0) {
    print "usage: $0 <input_files...>\n";
    exit(0);
}

foreach my $fname (@ARGV) {
    my $FH;
    open($FH, "<$fname") || die "ERROR: unable to open $fname for reading\n";
    my @lines = <$FH>;
    close($FH);

    chomp(@lines);

    my $total = 0;
    foreach my $l (@lines) {
	my ($latency, $count) = split(/[\,\s]+/,$l);
	$total += $count;
    }

    open($FH, ">$fname") || die "ERROR: unable to open $fname for writing\n";
    my $running_sum = 0.0;
    foreach my $l (@lines) {
	my ($latency, $count) = split(/[\,\s]+/,$l);
	$running_sum += $count;
	my $cdf = $running_sum/$total;
	my $ccdf = ($total - $running_sum)/$total;
	print $FH "$latency\t$count\t".((1.0*$count)/(1.0*$total))."\t$cdf\t$ccdf\n";
    }
    close($FH);
}


