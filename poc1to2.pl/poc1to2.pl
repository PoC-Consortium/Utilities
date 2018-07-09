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

# CLI param defaults

my $memory;         # define memory constraints; default: unlimited
my $inplace = 1;    # default mode of operation: convert in-place
my $outdir;         # undefined => plot file in-place modification
my $quiet = 0;      # quiet = 0 => we are verbose

# some plot constants

my $SCOOPS_IN_NONCE     = 4096;
my $SHABAL256_HASH_SIZE = 32;
my $SCOOP_SIZE          = $SHABAL256_HASH_SIZE * 2;
my $NONCE_SIZE          = $SCOOP_SIZE * $SCOOPS_IN_NONCE;

# }}}
# {{{ CLI processing

GetOptions(
    'mem=i' => \$memory,                # divide processing blocks into N fragments
    'help'  => \&print_help,            # keep generated test files
    'out=s' => \$outdir,
    'quiet' => \$quiet,
) or &print_help;

my $plotpath = shift @ARGV || do {
	say STDERR "No plot file specified";
	&print_help;
	exit 1;
};

if (!-r $plotpath) {
    fail("Given plotfile '$plotpath' unreadable or nonexistant.");
}

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

my $plotparams     = parse_poc1_name($pname);          # get plot structure from filename
my $plotsize       = check_poc1_plot($plotparams);     # see if plot file is consistent with plot filename
my $numnonces      = $plotparams->{nonces};            # number of nonces in scoop
my $tmp_plotpath   = "$plotpath.converting";           # temporary filename for in-place conversion
my $plotpath_poc2  = $inplace ? $ppath : $outdir;      # location of PoC2 plot
my $block_size     = $numnonces * $SCOOP_SIZE;         # how big is a 'scoop block' - we have 4096 of these
my $used_memMB     = $block_size / 524288;             # memory in MB that is going to be used
my $process_nonces = $numnonces;                       # nonces to process per batch (default: all)
my $work_size      = $block_size;                      # worksize block (default: complete/all nonces)

if (defined $memory && $memory < $used_memMB) {        # if our memory constraints are smaller than needed
    $process_nonces = $memory * 8192;                  # 1 MB / 128 byte (2 SCOOPS) = 8192
    $work_size      = $process_nonces * $SCOOP_SIZE;   # our smaller block
    info("applying memory constraints: max buffer $memory MB",
         "resulting in processing $process_nonces nonces (instead of $numnonces) at a time.");
    exit 0;
#    print "TEST: process nonces: $process_nonces * 2 * $SCOOP_SIZE = " . $process_nonces * 2 * $SCOOP_SIZE . "\n";
}
else {
    info('memory to be used: ' . sprintf("%.3f MB", $used_memMB));
}

$plotpath_poc2 .= '/' . create_poc2_name($plotparams);

my $pos;          # fseek position (read start position within the plot file)
my $buffer1;
my $buffer2;
my $numread;
my $numwrite;

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

    shuffle_poc1to2($handle, $handle); # in-place shuffling: source and target file are the same

    close $handle;

    rename $tmp_plotpath, $plotpath_poc2;
}
else {                   # copy conversion: we need to pre-allocate target
    my $target = preallocate($plotpath_poc2, -s $plotpath);

    open my $source, '<:raw', $plotpath or die $!;
    binmode $source;

    shuffle_poc1to2($source, $target); # copy-on-write shuffling: source and target file are different

    close $source;
    close $target;
}


### PLOT OPERATIONS

# {{{ shuffle_poc1to2              shuffle operation PoC1 to PoC2 (theoretically also vice versa)

sub shuffle_poc1to2 {
    my $src_fh = shift;       # source filehandle
    my $tgt_fh = shift;       # target filehandle

    for (my $scoop = 0; $scoop < $SCOOPS_IN_NONCE / 2; $scoop++) {
        $pos = $scoop * $block_size;
        seek $src_fh, $pos, 0;                   # seek from beginning
        $numread = sysread $src_fh, $buffer1, $block_size;
        fail("read $numread bytes instead of $block_size") if ($numread != $block_size);
        seek $src_fh, -($pos + $block_size), 2;  # seek from EOF
        $numread = sysread $src_fh, $buffer2, $block_size;
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

        seek $tgt_fh, -($pos + $block_size), 2;   # seek from EOF
        $numwrite = syswrite $tgt_fh, $buffer2;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
        seek $tgt_fh, $pos, 0;                   # seek from beginning
        $numwrite = syswrite $tgt_fh, $buffer1;
        fail("wrote $numwrite bytes instead of $block_size") if ($numwrite != $block_size);
    }

    return;
}

# }}}
# {{{ parse_poc1_name              check and parse given PoC1 plotname (if in optimized PoC1 format)

sub parse_poc1_name {
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

    return fail("The file named '$plotname' does not look like a known PoC1 plotfile.");
}

# }}}
# {{{ check_poc1_plot              check the PoC1 plot file consistency (size is what filename says)

sub check_poc1_plot {
    my $plotstruct = shift;

    my $real_plotsize     = -s $plotpath;
    my $expected_plotsize = $plotstruct->{nonces} * $NONCE_SIZE;

    if ($real_plotsize != $expected_plotsize) {
        fail("The real size ($real_plotsize) is not what we expected ($expected_plotsize)");
    }

    return $real_plotsize;
}

# }}}
# {{{ create_poc2_name             create PoC2 plot filename

sub create_poc2_name {
    my $plotstruct = shift;

    return $plotstruct->{id} . '_' . $plotstruct->{offset} . '_' . $plotstruct->{nonces};
}

# }}}

### HELPERS

# {{{ preallocate                  pre-allocate file/path of a specific size

sub preallocate {
    my $path = shift;
    my $size = shift;

    open my $target, ">:raw", $path or die $!;
    truncate $target, $size  or die $!;
    binmode $target;

    return $target;
}

# }}}
# {{{ print_help                   print usage help

sub print_help {
    print << "EOH";

    $0 - PoC1 to PoC2 converter

 Usage:
    $0 [options] <plotfile>

 Options:
    --help
      This help

    --mem <megabyte>
      Memory constraint to use less memory than the script would have used
      without any constraints (1/2000th of plot size)
      Given in megabyte, so -m 1000 will use roughly 1GB of memory

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
# {{{ fail                         print lines with failure information and exit

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
