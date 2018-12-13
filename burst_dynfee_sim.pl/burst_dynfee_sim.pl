#!/usr/bin/env perl
# For Emacs: -*- mode:cperl; eval: (folding-mode 1); coding:utf-8; -*-

# {{{ use block

use warnings;
use strict;

use utf8;

use Data::Dumper;

# }}}
# {{{ var block

if (!@ARGV) {
    print "Dynamic Fee (Tx-Slots) Simulator\n\n";
    print "Usage:\n";
    print "       burst_dynfee_sim.pl <slots> [fee ]+\n\n";
    print "Meaning, your 1st argument is the number of slots and\n";
    print "all following arguments (space and/or comma separated list)\n";
    print "are the feet of the currently floating unconfirmed transactions.\n\n";
    print "Example:\n";
    print "       burst_dynfee_sim.pl 10 0.01,0.01,0.2,0.3 1 2 3 4\n";
exit;
}

my $blocksize = shift @ARGV;
my @fees      = map { split m{,} } @ARGV;

my $fee_quant = 0.00735;

# }}}

@fees = grep { $_ >= $fee_quant } sort { $b <=> $a } @fees;


print "\n";
print "    Fee Quantum: $fee_quant\n";
print " Block Capacity: $blocksize\n";
print "Fee slots:\n";

for my $slot (reverse (1 .. $blocksize)) {
    my $slot_fee = $slot * $fee_quant;
    print sprintf("%4d", $slot), ": $slot_fee\n";
}

print "Pending Tx fees (descending-sorted and filtered too low):\n";
print Dumper(\@fees);

print "Distributing as follows:\n";

INCLUDE_LOOP:
while ($blocksize && @fees) {
    my $fee = $fees[0];
    my $slot_value = $blocksize * $fee_quant;

    if ($fee >= $slot_value) {
        print "$fee has slot @ $blocksize -> added\n";
        shift @fees;
    }
    else {
        print "skipped slot @ $blocksize ($fee too low for $slot_value).\n";
    }
    $blocksize--;
}

if (@fees) {
    print "Block capacity exhausted, leaving these for the next block:\n";
    print Dumper(\@fees);
}

