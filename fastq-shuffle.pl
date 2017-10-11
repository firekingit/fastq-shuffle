#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use POSIX;
use File::Temp;
use File::Basename;
use File::Spec;

my $random_state;

my @temp_files = ();

my %buffer = (
    input    => "",       # unshuffled input
    index    => []        # index for input
    );

=head1 fastq-shuffle.pl

A small program to shuffle huge fastq files using external memory
according to Sanders (1998) "Random Permutations on Distributed,
External and Hierarchical Memory".

=head1 SYNOPSIS

    fastq-shuffle.pl -1 reads.fq -2 mates.fq

    # multiple input files
    fastq-shuffle.pl -1 reads1.fq,reads2.fq -2 mates1.fq,mates2.fq

    # alternative form of multiple input files
    fastq-shuffle.pl -1 reads1.fq -2 mates1.fq -1 reads2.fq -2 mates2.fq

=head1 OPTIONS

=over 4

=item -1/--reads and -2/--mates

Input file(s) for first and seconde read. Might be used several times
or multiple files seperated by comma are provided. WARNING: The order
of files for first and second read has to match, but will be displayed
for a check.

=item -t/--num-temp-files [0/auto]

Number of temporary files, the input is split in. The split files are
loaded into memory entirely for shuffling. A value of 0 or auto
calulates the number of temporary files based on the shuffle block
size

=item -s/--shuffle-block-size [1G]

The size of a single shuffle block. The entire input will be split
into blocks of that size in bytes. Unit signs might be used for
mega-(m/M), kilo-(k/K), or giga-(g/G) byte. The default value is 1
gigabyte.

=item -d/--temp-directory

The temporary files are created inside the given folder. One might use
that option to put the temporary files onto fast disks, eg. SSDs or
into a RAM disk.

=item -r/--seed/--randomseed [ current unixtime stamp ]

The seed for the random generator. Strings can be used as seed due to
the basis is a cryptographic hash algorithm (SHA-256). Used to provide
reproducebility. In case the same input files (in same order) and the
same random seed is provided, the shuffle results are identical.

=item -o/--outdir

Specifies the output directory for the shuffled files. The shuffled
file names will be extended by the suffix C<.shuffled> and stored into
the specified directory. If no output directory is provided, the files
will be stored into the folder of the input files.

=back

=cut

use version 0.77; our $VERSION = version->declare("v0.1.0");

my %option = (
    'num-temp-files'     => 'auto',
    'temp-directory'     => undef,
    'shuffle-block-size' => '1G',
    'reads'              => [],
    'mates'              => [],
    'seed'               => time(),
    'outdir'             => undef
    );

GetOptions(
    \%option, qw(
          reads|1=s@
          mates|2=s@
          num-temp-files|t=s
          shuffle-block-size|s=s
          temp-directory|d=s
          version|V
          verbose|v+
          debug|D
          help|h
          seed|randomseed|r=s
          outdir|o=s
     ) ) or pod2usage(1);


# help requested?
if (exists $option{help} && $option{help})
{
    pod2usage(1);
}

# version requested?
if (exists $option{version} && $option{version}) {
    print "$VERSION\n";
    exit 0;
}

use Log::Log4perl qw(:easy :no_extra_logdie_message);
Log::Log4perl->easy_init($WARN);
my $logger = get_logger();
if (exists $option{verbose})
{
    $logger->more_logging($option{verbose});
    $logger->error("Verbosity level increased by ".$option{verbose});
}

if (exists $option{debug})
{
    Log::Log4perl->easy_init($DEBUG);
}

# check input files
@{$option{reads}} = split(",", join(",", @{$option{reads}}));
@{$option{mates}} = split(",", join(",", @{$option{mates}}));

# is the file list empty?
if (@{$option{reads}}==0 && @{$option{mates}}==0)
{
    $logger->logdie("ERROR: required parameter are --reads and --mates, please provide at least on pair of input files");
}

# same number of files?
unless (@{$option{reads}} == @{$option{mates}})
{
    $logger->logdie(sprintf("ERROR Number of first and second read files are different (%d vs. %d), but need to be the same!", 0+@{$option{reads}}, 0+@{$option{mates}}));
}

# do all files exist?
my @missing_files = grep { ! -e $_ } (@{$option{reads}}, @{$option{mates}});
if (@missing_files)
{
    $logger->logdie("ERROR The following files can not be accessed: ", join(", ", map {"'$_'"} @missing_files));
}

# estimate file size
my $filesize = estimate_filesize($option{reads}, $option{mates});
ALWAYS "Maximum filesize was estimated to be ".formatfilesize($filesize);

# calculate the buffer size and number of temporary files
$option{'shuffle-block-size'} = parse_size_spec($option{'shuffle-block-size'}) || $logger->logdie("Unable to parse the shuffle-block-size");

# if the number of temporary files was specified, then it will overwrite the value of shuffle-block-size
$option{'num-temp-files'} =~ s/^\s+|\s+$//g;
if (uc($option{'num-temp-files'}) ne "AUTO")
{
    unless ($option{'num-temp-files'} =~ /^\d+$/ && $option{'num-temp-files'} > 0)
    {
	$option{'shuffle-block-size'} = ceil($filesize/$option{'num-temp-files'});
    } else {
	$logger->error("Seems that you specify 0 as number of temporary files, therefore the value 'auto' is assumed");
	$option{'num-temp-files'}="AUTO";
    }
}

if (uc($option{'num-temp-files'}) eq "AUTO")
{
    $option{'num-temp-files'} = ceil($filesize/$option{'shuffle-block-size'});
}

# if buffer size is larger than file size we can shuffle in memory
if ($option{'shuffle-block-size'} >= $filesize)
{
    $option{'num-temp-files'} = 0;
    ALWAYS "Buffer size is larger than size of input file, therefore in memory shuffle will be used and no temporary files will be generated";
} else {
    ALWAYS sprintf("Size of buffer for shuffle will be %d %s and %d temporary files will be used", formatfilesize($option{'shuffle-block-size'}), $option{'num-temp-files'});

    # check if a temp-directory was specified and create a temporary folder inside that directory
    my $tempdir;
    if (defined $option{'temp-directory'})
    {
	unless (-d $option{'temp-directory'})
	{
	    $logger->logdie("Specified temporary directory ('".$option{'temp-directory'}."') does not exist. Please specify an existing directory!");
	}

	$tempdir = File::Temp::tempdir( DIR => $option{'temp-directory'}, CLEANUP => 1) || $logger->logdie("Unable to create temporary directory: $!");
    } else {

	$tempdir = File::Temp::tempdir( TMPDIR => 1, CLEANUP => 1) || $logger->logdie("Unable to create temporary directory: $!");
    }

    # generate the list of temporary files
    if ($option{'num-temp-files'} > 1)
    {
	foreach (2..$option{'num-temp-files'})
	{
	    push(@temp_files, { filename => File::Temp::tempnam($tempdir, "shuffleXXXXXX") });
	}
    }
}

# initialize the random number generator
ALWAYS "Random generator was initialized with the value '".::srand($option{seed})."'";

# estimates the filesize of a paired end set
sub estimate_filesize
{
    my ($filelist_reads, $filelist_mates) = @_;

    my $filesize = 0;

    for (my $i=0; $i<@{$filelist_reads}; $i++)
    {
	my $new_filesize = -s $filelist_reads->[$i];
	$new_filesize += -s $filelist_mates->[$i];

	if ($new_filesize > $filesize)
	{
	    $filesize = $new_filesize;
	}
    }

    return $filesize;
}

# Random generator is based on the implementation at
# http://wellington.pm.org/archive/200704/randomness/#slide19
# (paragraph Cryptographic random number generators)
use Digest;

sub srand{
    my $seed = shift || (time());
    $random_state = {
        digest => new Digest ("SHA-256"),
        counter => 0,
        waiting => [],
        prev    => $seed
    };

    return $seed;
}

sub rand{
    my $range = shift || 1.0;
    ::srand() unless defined $random_state;

    if (! @{$random_state->{waiting}}){
        $random_state->{digest}->reset();
        $random_state->{digest}->add($random_state->{counter} ++ .
                                     $random_state->{prev});
        $random_state->{prev} = $random_state->{digest}->digest();
        my @ints = unpack("Q*", $random_state->{prev}); # 64 bit unsigned integers
        $random_state->{waiting} = \@ints;
    }
    my $int = shift @{$random_state->{waiting}};
    return $range * $int / 2**64;
}

sub formatfilesize {
    my ($size, $si, $base) = @_;

    my $units = [qw(B KB MB GB TB PB)];

    unless (defined $base)
    {
	$base = 1024;
    }

    if ($base == 1024 || $base == 2)
    {
	$base = 1024;
    } elsif ($base == 1000 || $base == 10)
    {
	$base = 1000;
    } else {
	die "Base has to be 2 or 10 or 1024/1000\n";
    }

    if($base == 1024 && $si)
    {
	$units = [qw(B KiB MiB GiB TiB PiB)];
    }

    my $exp = 0;

    for (@$units) {
        last if $size < $base;
        $size /= $base;
        $exp++;
    }
    return wantarray ? ($size, $units->[$exp]) : sprintf("%.2f %s", $size, $units->[$exp]);
}

# returns a number of bytes based on a formated string like 1.6 GB
# containing a (float) number and a unit string allowed units are
# B(Byte), kB/kiB (kilobyte), MB/MiB (Megabyte), GB/GiB (Gigabyte),
# PB/PiB (Petabyte) unit is case insensitive
sub parse_size_spec
{
    my ($input, $base) = @_;

    if (! defined $base)
    {
	$base = 1024;
    }

    my $uc_input = uc($input);
    unless ($uc_input =~ /^\s*([0-9.]+)\s*([KMGP]*)I?B?\s*$/)
    {
	$logger->error("Unable to parse number '$input'");
	return undef;
    }

    my $number = $1;
    my $unit = $2;

    # check if number contains only on "."
    unless ($number =~ /^[0-9]*\.*[0-9]+$|^[0-9]+$/)
    {
	$logger->error("Unable to parse number '$number'");
	return undef;
    }
    $number = $number+0;

    my $factor = 1;
    if ($unit eq "")
    {
	$factor = 1;
    }
    elsif ($unit eq "K")
    {
	$factor = $base;
    }
    elsif ($unit eq "M")
    {
	$factor = $base * $base;
    }
    elsif ($unit eq "G")
    {
	$factor = $base * $base * $base;
    }
    elsif ($unit eq "P")
    {
	$factor = $base * $base * $base * $base;
    }

    return sprintf("%.0f", $number * $factor);
}

sub create_output_filenames
{
    my ($file1, $file2, $outdir) = @_;

    # generate new filenames
    my ($file1_fn, $file1_dir) = fileparse($file1);
    my ($file2_fn, $file2_dir) = fileparse($file2);

    # write output to shuffled files
    if (defined $outdir)
    {
	$file1_dir = $outdir;
	$file2_dir = $outdir;
    }

    my $outfile1 = File::Spec->catfile($file1_dir, $file1_fn.".shuffled");
    my $outfile2 = File::Spec->catfile($file2_dir, $file2_fn.".shuffled");

    # check if the files exist
    my @existing_files = grep {-e $_} ($outfile1, $outfile2);

    if(@existing_files)
    {
	$logger->logdie(sprintf("Outputfile(s) (%s) exist! Please delete and restart or specify another output directory", join(", ", map { "'$_'" } (@existing_files))));
    }

    return ($outfile1, $outfile2);
}

sub shuffle_memory_and_write_files
{
    my ($ref_buffer, $file1, $file2) = @_;

    # shuffle in memory
    for(my $i = @{$ref_buffer->{index}}-1; $i >= 1; $i--)
    {
	my $j = rand($i);

	($ref_buffer->{index}[$i], $ref_buffer->{index}[$j]) = ($ref_buffer->{index}[$j], $ref_buffer->{index}[$i]);
    }

    open(my $f1, ">>", $file1) || $logger->logdie($!);
    open(my $f2, ">>", $file2) || $logger->logdie($!);

    foreach my $next_item (@{$ref_buffer->{index}})
    {
	print $f1 substr($ref_buffer->{input}, $next_item->{offset}, $next_item->{lenA});
	print $f2 substr($ref_buffer->{input}, $next_item->{offset}+$next_item->{lenA}, $next_item->{lenB});
    }

    close($f1) || $logger->logdie($!);
    close($f2) || $logger->logdie($!);
}


sub read_from_temp_file
{
    my ($file, $index, $buffer) = @_;

    $buffer->{input} = "";
    $buffer->{index} = [];

    open(FH, "<", $file) || $logger->logdie($!);
    {
	local $/;
	$buffer->{input} = <FH>;
    }
    close(FH) || $logger->logdie($!);

    open(FH, "<", $index) || $logger->logdie($!);
    {
	local $/;
	my @dat = unpack("(QLL)*", scalar <FH>);

	for(my $i=0; $i<@dat; $i+=3)
	{
	    push(@{$buffer->{index}}, { offset => $dat[$i], lenA => $dat[$i+1], lenB => $dat[$i+2] });
	}
    }
    close(FH) || $logger->logdie($!);
}

sub write_to_temp_file
{
    my ($blockA, $blockB, $temp_file) = @_;

    my $fh = $temp_file->{file};
    my $idx = $temp_file->{idx};

    my $offset = tell($fh);
    my $index_entry = pack("QLL", $offset, length($$blockA), length($$blockB));
    print $idx $index_entry;
    print $fh $$blockA, $$blockB;
}
