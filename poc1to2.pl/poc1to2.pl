#!/usr/bin/env perl
# For Emacs: -*- mode:cperl; eval: (folding-mode 1) -*-

# {{{ use block

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Basename;
use Getopt::Long;                                                # command line options processing

# }}}
# {{{ var block

my $plotpath = $ARGV[0];
my ($pname,$ppath,$psuffix) = fileparse($plotpath,());


# define quantities

my $SCOOPS_IN_NONCE = 4096;

# define sizes within a plot file - in bytes

my $SHABAL256_HASH_SIZE = 32;
my $SCOOP_SIZE          = $SHABAL256_HASH_SIZE * 2;
my $NONCE_SIZE          = $SCOOP_SIZE * $SCOOPS_IN_NONCE;

# }}}
# {{{ CLI processing

GetOptions(
    'help'  => \&print_help,             # keep generated test files
) or croak "Formal error processing command line options!";

# }}}

print "Name: $pname\n";
print "Path: $ppath\n";

my $plotparams    = parse_plotname($pname);
my $plotsize      = check_plot($plotparams);
my $block_size    = $plotparams->{nonces} * $SCOOP_SIZE; # how big is a 'scoop block' - we have 4096 of these
my $tmp_plotpath  = "$plotpath.converting";
my $plotpath_poc2 = "$ppath/" . get_poc2_name($plotparams);

my $pos;  # fseek position (used for front/back)
my $buffer1;
my $buffer2;
my $numread;
my $numwrite;
my $numnonces = $plotparams->{nonces};

rename $plotpath, $tmp_plotpath;

open my $handle, '+<:raw', $tmp_plotpath or fail("Failed to open '$plotpath'");
binmode $handle;

print "processing scoops...\n";

for (my $scoop = 0; $scoop < $SCOOPS_IN_NONCE / 2; $scoop++) {
    $pos = $scoop * $block_size;
    seek $handle, $pos, 0; # seek from beginning
    $numread = sysread $handle, $buffer1, $block_size;
    fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
    seek $handle, -($pos + $block_size), 2; # seek from EOF
    $numread = sysread $handle, $buffer2, $block_size;
    fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
    print "$scoop/" . ($SCOOPS_IN_NONCE - $scoop) . ' ';

    my $off = 32;
    # here perform the shuffle-conversion
    for (my $nonceidx = 0; $nonceidx < $numnonces; $nonceidx++) {
        my $hash1 = substr $buffer1, $off, $SHABAL256_HASH_SIZE;
        my $hash2 = substr($buffer2, $off, $SHABAL256_HASH_SIZE);
        substr($buffer1, $off, $SHABAL256_HASH_SIZE) = $hash2;
        substr($buffer2, $off, $SHABAL256_HASH_SIZE) = $hash1;
        $off += $SCOOP_SIZE;
    }

    seek $handle, -($pos + $block_size), 2; # seek from EOF
    $numwrite = syswrite $handle, $buffer2;
    fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
    seek $handle, $pos, 0;          # seek from beginning
    $numwrite = syswrite $handle, $buffer1;
    fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
}

close $handle;

rename $tmp_plotpath, $plotpath_poc2;




# {{{ parse_plotname               examine given plotname if in optimized PoC1 format

sub parse_plotname {
    my $plotname = shift;

    # check if plotfile name is ok
    if ($plotname =~ m{\A(?<id>\d+)_(?<offset>\d+)_(?<nonces>\d+)_(?<stagger>\d+)\z}xms) { # PoC1 plot
        if ($+{nonces} == $+{stagger}) {
            return {
                id     => $+{id},
                offset => $+{offset},
                nonces => $+{nonces},
            }
        }
        else {
            fail("$0 works only on optimized plot files. Please optimize first.",
                 "The Burst plotfile named '$plotname' seems not to be an optimized PoC1 plot.");
        }
    }
    else {
        fail("The Burst plotfile named '$plotname' has not expected format.");
    }
}

# }}}
# {{{ check_plot                   check the plot consistency

sub check_plot {
    my $plotstruct = shift;

    my $real_plotsize     = -s $plotpath;
    my $expected_plotsize = $plotstruct->{nonces} * $NONCE_SIZE;

    if ($real_plotsize != $expected_plotsize) {
        fail("The real size ($real_plotsize) is not what we expected ($expected_plotsize)");
    }

    return $real_plotsize;
}

# }}}
# {{{ get_poc2_name                create PoC2 plot filename

sub get_poc2_name {
    my $plotstruct = shift;

    return $plotstruct->{id} . '_' . $plotstruct->{offset} . '_' . $plotstruct->{nonces};
}

# }}}
# {{{ print_help                   print usage help

sub print_help {
    print << "EOH";

    $0 - PoC1 to PoC2 converter

 Usage:
    LBC [options]

 Options:
    --help
      This help
EOH

    exit 0;
}

# }}}
# {{{ fail                         print lines wit failure information and exit

sub fail {
    my @lines = @_;

    for my $line (@lines) {
        print "$line\n";
    }

    exit 1;
}

# }}}
