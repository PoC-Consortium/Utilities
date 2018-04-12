#!/usr/bin/env perl
# For Emacs: -*- mode:cperl; eval: (folding-mode 1) -*-

# {{{ use block

use strict;
use warnings;

use Carp;
use Crypt::Mode::CBC;
use Crypt::Curve25519;
use Data::Dumper;
use Digest::SHA qw(sha256 sha256_hex);
use File::Basename;
use Getopt::Long;                                                # command line options processing
use JSON;
use Time::HiRes;


# }}}
# {{{ var block

# CLI param defaults

my $SCOOPS = 4096;                 # number of scoops (we adhere to PoC1/2 standards
my $SSIZE  = 64;                   # size of a scoop in bytes
my $NONCE  = $SCOOPS * $SSIZE;     # resulting size of a nonce

# default values
my $scoop  = 1;                    # scoop number
my $gensig = 2**32 - 1;            # previous block gensig

my $splot_size = 0;                # size of the synthetic plot in NONCES
my $id         = 0;                # numeric Id of the miner
my $action;                        # no action

my $json = JSON->new;

# }}}
# {{{ CLI processing

GetOptions(
    'action=s' => \$action,             # 
    'gensig=i' => \$gensig,             # 64bit GenSig
    'help'     => \&print_help,         # keep generated test files
    'id=i'     => \$id,
    'plot=i'   => \$splot_size,
    'scoop=i'  => \$scoop,
) or croak "Formal error processing command line options!";


my $plotpath = $ARGV[0] // fail('No plotfile given.');

if (defined $action) {
    if ($action eq 'o2i') {
        orig2individual($plotpath, $id);
    }
    else {
        fail('Not implemented yet.');
    }
    exit 0;
}

if ($splot_size) {
    synthetic_plot($plotpath, $splot_size);
    exit 0;
}
elsif (! -r $plotpath) {
    fail("Plotfile not readable");
}

mine_poc3($plotpath, $scoop, $gensig);

# }}}

### ACTIONS

# {{{ mine_poc3                    simulate mining process

sub mine_poc3 {
    my $plot   = shift;       # get plot file
    my $scoop  = shift;       # get current scoop
    my $gensig = shift;       # get last block gensig

    my $chunksize = $SSIZE + 4;         # scoop size + offset long
    my $plotsize  = -s $plot;           # get size of plotfile

    if ($plotsize % $chunksize) {                 # make sure it is padded correctly
        fail("PoC3 file has wrong length");       # bail out else
    }

    my $seekok     = 1;
    my $pos        = $scoop * $chunksize;    # initial position
    my $iterations = 64;                     # maximum number of RB decisions (64bit gensig)
    my $buffer_off;                          # buffer for reading offset chunk
    my $buffer_data;                         # buffer for reading data chunk
    my $numread;                             # kep track of read bytes
    my @scoops;

    print "Mining $plot ($plotsize bytes) - simulating scoop $scoop\n";

    open my $handle, '<:raw', $plot or fail("Failed to open '$plot'");
  PLOTREAD_LOOP:
    while ($iterations--) {
        # print "DEBUG: Reading 64bytes at POS: $pos\n";

        seek($handle, $pos, 0) || last PLOTREAD_LOOP;

        sysread $handle, $buffer_off, 4;
        $numread = sysread $handle, $buffer_data, $SSIZE;
        fail("read $numread bytes instead of 64") if ($numread != 64);

        push @scoops, {
            off  => (unpack "L", $buffer_off),
            data => (unpack 'H*', $buffer_data),
        };

        $pos = $NONCE * 2**(63-$iterations) + $scoop * $chunksize * 2**(64-$iterations);
        $pos++ if ($gensig & 1);

        last PLOTREAD_LOOP if ($pos > $plotsize - $chunksize);
        $gensig = $gensig >> 1;
    }
    close $handle;

    # send this via JSON to the verifier
    print "Mined this shit:\n";
    print $json->encode(\@scoops);
    print "\n";

    return;
}

# }}}
# {{{ orig2individual              individualize a PoC3 plot to Miner numericID

sub orig2individual {
    my $file = shift;         # name of the PoC3 plot file
    my $id   = shift;         # numericId of the miner

    my $size = -s $file;                               # get length of the original file
    if ($size % $SSIZE) {                              # make sure it is padded correctly
        fail("PoC3 source file not padded");           # bail out else
    }
    # currently, we only want a padding to $SSIZE, but in future we
    # might want a padding to 1,3,7,15,...
    # (see https://oeis.org/A000225) * $NONCE, this stronger
    # requirement would restrict the valid PoC3 plot sizes to some
    # coarse grained steps the bigger these plots were, but it would
    # ensure a balanced RB tree and avoid any gameability of
    # unbalanced poC3 files.

    my $numread;              # keep track of bytes read
    my $numwrite;             # keep track of bytes written
    my $buffer;
    my $cbc = Crypt::Mode::CBC->new('AES', $SSIZE);  # prepare AES encryption of chunk

    open my $handle, '<:raw', $file         or fail("Failed to open input '$file'");
    open my $poc3_fh, '>:raw', "$file.poc3" or fail("Failed to open output '$file.poc3'");

    for (my $idx = 0; $idx < ($size / $SSIZE); $idx++) {    # we may need Math::BigInt for sizes > 2^64 (16777216 TB)
        $numread = sysread $handle, $buffer, $SSIZE;        # read chunk and check if read ok, bail else
        fail("read $numread bytes instead of $SSIZE") if ($numread != $SSIZE);
        # print "IDX: $idx\n";
        my ($key, $off) = determine_key($id, $idx);              # determine key
        my $iv          = pack "QQ", $off, $idx;                 # build IV
        my $ciphertext  = $cbc->encrypt($buffer, $key, $iv);     # encrypt chunk with 256bit AES

        $off      = pack "L", $off;
        $numwrite = syswrite $poc3_fh, $off . $ciphertext;
        fail("wrote $numwrite bytes instead of $SSIZE") if ($numwrite != $SSIZE + 4);
        print $idx, '/', ($size / $SSIZE), "\n";
        # print "LEN: ", length($ciphertext), " key: $key_hex OFF: $off\n";
        #print "ORIG:  ", unpack("H*", $buffer), "\n";
        #print "INDIV: ", unpack("H*", $ciphertext), "\n";
        #my $plaintext = $cbc->decrypt($ciphertext, $key, $iv);
        #print "BACK:  ", unpack("H*", $plaintext), "\n";
    }
    close $poc3_fh;
    close $handle;
}

# }}}
# {{{ synthetic_plot               write a synthetic plot for test purposes

sub synthetic_plot {
    my $plot = shift;         # PoC3 plot file name
    my $num  = shift;         # Number of NONCES for that synthetic plot

    my $index = 0;            # index of the current written data chunk

    open my $handle, '>:raw', $plot
        or fail("Failed to open '$plot'");

    for (my $i = 0; $i < $num; $i++) {                      # iterate all nonces to be written
        my $buffer = '';                                    # we write one nonce at a time, so buffer them

        for (my $scoop = 0; $scoop < $SCOOPS; $scoop++) {   # iterate all scoops
            $buffer .= pack 'QQQQQQQQ', (0) x 7, $index++;  # add 64 byte chunk with only its index as data to buffer
        }
        print $handle $buffer;                              # write the whole NONCE to disk
    }

    close $handle;

    return;
}

# }}}

### HELPERS

# {{{ determine_key                determine the 256bit AES encryption key

sub determine_key {
    my $id  = shift;  # numeric Id of miner
    my $idx = shift;  # index of data chunk

    my $off = 1;      # we start with offset 1 (never compute just the EC result)
    my $key;

    # compute a 25519 EC out of interleaved chunk idx and miner id
    # this is pretty ASIC proof
    $idx = unpack "Q", curve25519_public_key(pack("QQQQ", $idx,$id,$idx,$id));

    while (1) {
        my $data = pack "Q", ($idx + $off++);     # get 64bit input data for hash function
           $key  = sha256($data);                 # key used for AES encryption
        my @val  = unpack "QQQLSS", $key;         # dissect key (64,64,64,32,16,16 bit)

        # check if last unsigned word is 0 (on average one in 65536)
        # and bail out returning key and offset if so. This is defining
        # our "PoW difficulty". We can change both the hashing function
        # as well as the required difficulty for the production PoC3
        return ($key, $off) if (!$val[5]);
    }

    fail("Could not find any offset. Should never happen. I shouldn't even be here!");
    return;
}

# }}}

### LOW-LEVEL

# {{{ print_help                   print usage help

sub print_help {
    print << "EOH";

    $0 - PoC3 Prototype

 Usage:
    $0 [options] <file>

 Options:
    --action <o2i|i2o>
      individualize or de-individualize plot

    --gensig <num>
      simulate gensig <num> from previous block

    --help
      This help

    --id <numId>
      numeric Id of the miner

    --plot <n>
      Generate a synthetic plot with n nonces

    --scoop <n>
      simulate scoop number <n> (0-4095)
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
