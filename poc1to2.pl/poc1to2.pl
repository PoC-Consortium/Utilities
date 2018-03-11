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

# CLI param defaults;

my $quiet = 0;      # quiet = 0 => we are verbose
my $outdir;         # undefined => plot file in-place modification
my $inplace = 1;    # default mode of operation: convert in-place

# some plot constants

my $SCOOPS_IN_NONCE     = 4096;
my $SHABAL256_HASH_SIZE = 32;
my $SCOOP_SIZE          = $SHABAL256_HASH_SIZE * 2;
my $NONCE_SIZE          = $SCOOP_SIZE * $SCOOPS_IN_NONCE;

# }}}
# {{{ CLI processing

GetOptions(
    'help'  => \&print_help,             # keep generated test files
    'out=s' => \$outdir,
    'quiet' => \$quiet,
) or croak "Formal error processing command line options!";

my $plotpath = $ARGV[0];
my ($pname,$ppath,$psuffix) = fileparse($plotpath,());

if (defined $outdir) {
    info("Outdir defined. Copy conversion mode.");
    if (!-d $outdir) {
        fail("Given outdir ($outdir) is not a directory.");
    }
    if ($outdir eq $ppath) {
        fail("Given outdir is the same location as plotfile -> use in-place modification.");
    }
    $inplace = 0;    # mode of operation: convert copy
}


# }}}


$|++;  # make print output unbuffered

info("Name: $pname",
     "Path: $ppath");

my $plotparams    = parse_plotname($pname);                 # get plot structure from filename
my $plotsize      = check_plot($plotparams);                # see if plot file is consistent with plot filename
my $block_size    = $plotparams->{nonces} * $SCOOP_SIZE;    # how big is a 'scoop block' - we have 4096 of these
my $tmp_plotpath  = "$plotpath.converting";                 # temporary filename for in-place conversion
my $plotpath_poc2 = $inplace ? $ppath : $outdir;

$plotpath_poc2 .= '/' . get_poc2_name($plotparams);

my $pos;          # fseek position (read start position within the plot file)
my $buffer1;
my $buffer2;
my $numread;
my $numwrite;
my $numnonces = $plotparams->{nonces};

# We assume an optimized PoC1 file (scoop 0 of all nonces, then scoop 1 of all nonces etc...)
# we read in scoop 0 and scoop 4095 for all nonces, then we swap their MSB 32 bytes
# then we write these scoops back to disk
# we continue with scoop 1 and scoop 4094
# Therefore, each iteration handles 2 scoops, we need to make 2048 iterations for any plot file.
# our memory requirements for the two buffers are <number of nonces> * 128 bytes
# => roughly 1/2000th of the plot size (e.g. 5GB for a 10TB plot)

info("processing scoops...");

if ($inplace) {
    rename $plotpath, $tmp_plotpath;

    open my $handle, '+<:raw', $tmp_plotpath or fail("Failed to open '$plotpath'");

    binmode $handle;

    for (my $scoop = 0; $scoop < $SCOOPS_IN_NONCE / 2; $scoop++) {
        $pos = $scoop * $block_size;
        seek $handle, $pos, 0;                   # seek from beginning
        $numread = sysread $handle, $buffer1, $block_size;
        fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
        seek $handle, -($pos + $block_size), 2;  # seek from EOF
        $numread = sysread $handle, $buffer2, $block_size;
        fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
        info("$scoop/" . ($SCOOPS_IN_NONCE - $scoop) . ' ', undef);

        seek $handle, -$block_size, 1;           # seek relative to position

        my $off = 32;
        # here perform the shuffle-conversion (swap the MSB 32bytes in all nonces)
        for (my $nonceidx = 0; $nonceidx < $numnonces; $nonceidx++) {
            my $hash1 = substr $buffer1, $off, $SHABAL256_HASH_SIZE;
            substr($buffer1, $off, $SHABAL256_HASH_SIZE) = substr($buffer2, $off, $SHABAL256_HASH_SIZE);
            substr($buffer2, $off, $SHABAL256_HASH_SIZE) = $hash1;
            $off += $SCOOP_SIZE;
        }

        $numwrite = syswrite $handle, $buffer2;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
        seek $handle, $pos, 0;                   # seek from beginning
        $numwrite = syswrite $handle, $buffer1;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
    }

    close $handle;

    rename $tmp_plotpath, $plotpath_poc2;
}
else {                   # copy conversion: we need to pre-allocate target
    open my $target, ">:raw", $plotpath_poc2 or die $!;
    truncate $target, -s $plotpath  or die $!;
    binmode $target;

    open my $source, "<:raw", $plotpath or die $!;
    binmode $source;

    for (my $scoop = 0; $scoop < $SCOOPS_IN_NONCE / 2; $scoop++) {
        $pos = $scoop * $block_size;
        seek $source, $pos, 0;                   # seek from beginning
        $numread = sysread $source, $buffer1, $block_size;
        fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
        seek $source, -($pos + $block_size), 2;  # seek from EOF
        $numread = sysread $source, $buffer2, $block_size;
        fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
        info("$scoop/" . ($SCOOPS_IN_NONCE - $scoop) . ' ', undef);

        my $off = 32;
        # here perform the shuffle-conversion (swap the MSB 32bytes in all nonces)
        for (my $nonceidx = 0; $nonceidx < $numnonces; $nonceidx++) {
            my $hash1 = substr $buffer1, $off, $SHABAL256_HASH_SIZE;
            substr($buffer1, $off, $SHABAL256_HASH_SIZE) = substr($buffer2, $off, $SHABAL256_HASH_SIZE);
            substr($buffer2, $off, $SHABAL256_HASH_SIZE) = $hash1;
            $off += $SCOOP_SIZE;
        }

        seek $target, -($pos + $block_size), 2; # seek from EOF
        $numwrite = syswrite $target, $buffer2;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
        seek $target, $pos, 0;                   # seek from beginning
        $numwrite = syswrite $target, $buffer1;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
    }

    close $source;
    close $target;
}


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
    $0 [options]

 Options:
    --help
      This help

    --out <directory>
      Define a directory to write the converted plot file to. This switches
      to copy on write mode. (Else in-place is default) and allows you to
      fasten up the conversion at the expense of temporary additional HDD
      space.

    --quiet
      Quiet operation. Really quiet - no output at all (except failures).
      You can send the process into background and forget about it.

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
# {{{ info                         inform the user - if desired

sub info {
    return if ($quiet);

    my @lines   = @_;
    my $newline = 1;

    if (!defined $lines[-1]) {
        $newline = 0;
        pop @lines;
    }

    for my $line (@lines) {
        print $line;
        print "\n" if ($newline);
    }

    return;
}

# }}}
