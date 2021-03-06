# fastq-shuffle

[![Build Status](https://www.travis-ci.org/chloroExtractorTeam/fastq-shuffle.svg)](https://www.travis-ci.org/chloroExtractorTeam/fastq-shuffle)
[![Coverage Status](https://coveralls.io/repos/github/chloroExtractorTeam/fastq-shuffle/badge.svg)](https://coveralls.io/github/chloroExtractorTeam/fastq-shuffle)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.1011356.svg)](https://doi.org/10.5281/zenodo.1011356)

```shell
    A small program to shuffle huge fastq files using external memory
    according to Sanders (1998) "Random Permutations on Distributed,
    External and Hierarchical Memory".

SYNOPSIS
        fastq-shuffle.pl -1 reads.fq -2 mates.fq

        # multiple input files
        fastq-shuffle.pl -1 reads1.fq,reads2.fq -2 mates1.fq,mates2.fq

        # alternative form of multiple input files
        fastq-shuffle.pl -1 reads1.fq -2 mates1.fq -1 reads2.fq -2 mates2.fq

OUTPUT
    The shuffled output files are returned with the same name as the input
    files with the additional suffix ".shuffled". Therefore, the file
    "read.fq" would be returned as "read.fq.shuffled". All output files are
    stored in the same folder as the input files unless a specific output
    directory is specified using "--outdir" option.

OPTIONS
    -1/--reads and -2/--mates
        Input file(s) for first and seconde read. Might be used several
        times or multiple files seperated by comma are provided. WARNING:
        The order of files for first and second read has to match, but will
        be displayed for a check.

    -t/--num-temp-files [0/auto]
        Number of temporary files, the input is split in. The split files
        are loaded into memory entirely for shuffling. A value of 0 or auto
        calulates the number of temporary files based on the shuffle block
        size

    -s/--shuffle-block-size [1G]
        The size of a single shuffle block. The entire input will be split
        into blocks of that size in bytes. Unit signs might be used for
        mega-(m/M), kilo-(k/K), or giga-(g/G) byte. The default value is 1
        gigabyte.

    -d/--temp-directory
        The temporary files are created inside the given folder. One might
        use that option to put the temporary files onto fast disks, eg. SSDs
        or into a RAM disk.

    -r/--seed/--randomseed [ current unixtime stamp ]
        The seed for the random generator. Strings can be used as seed due
        to the basis is a cryptographic hash algorithm (SHA-256). Used to
        provide reproducebility. In case the same input files (in same
        order) and the same random seed is provided, the shuffle results are
        identical.

    -o/--outdir
        Specifies the output directory for the shuffled files. The shuffled
        file names will be extended by the suffix ".shuffled" and stored
        into the specified directory. If no output directory is provided,
        the files will be stored into the folder of the input files.

CHANGELOG
    v0.9.0
        First version is able to shuffle fastq files

    v0.9.1
        Fixed an issue with the temporary file parameter.

    v0.9.2
        First release candidate.

        Adds a changelog and licence information to the README.md and to the
        program documentaton.

LICENCE
    MIT License

    Copyright (c) 2017 chloroExtractorTeam

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

```
