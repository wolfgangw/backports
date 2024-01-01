# dcp_inspect

[dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect) is a tool for deep inspection and validation of digital cinema packages (DCP, SMPTE and Interop). This includes integrity checks, asset inspection, schema validation, signature and certificate verification and composition summarization. Basically anyone who needs to establish the validity of a digital cinema package can put [dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect) to good use.

See the [Examples](https://github.com/wolfgangw/backports/wiki/Example-output-from-dcp_inspect) page for some of the things it can do. Also see [How to use Digital Cinema Tools](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools)' section for [dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect).

# Usage examples

        dcp_inspect --help
        dcp_inspect <path to directory>
        dcp_inspect <path to directory> --no-hash --no-audio-analysis
        dcp_inspect <path to directory> --nh --na
        dcp_inspect <path to directory> --as-asset-store --hash-limit <limit> --logfile <path>

# Installation

See [Digital Cinema Tools Distribution](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki) for an easy-to-use [Setup](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/Setup) script. This will install everything required.

# Features

- Will find and check all DCPs in a filesystem tree

- Handles both Interop and SMPTE DCPs (and says useful things about free poetry DCPs, too)

- Checks asset integrity

- Checks timeline integrity of compositions

- Checks applicable assets against XSD (XML Schema Definitions)

- Checks and verifies signatures

- Deep-inspects compositions

    This includes composition type consistency and completeness checks.

- Deep-inspects DCSubtitle

- Reports in detail all errors encountered

See [Examples](https://github.com/wolfgangw/backports/wiki/Example-output-from-dcp_inspect). See [What's missing](#whats-missing).

# Requirements

See [Digital Cinema Tools Distribution](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki) for an easy-to-use [Setup](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/Setup) script. This will install everything required (batteries included). Run the setup occasionally to keep up-to-date.

If you prefer manual installation you will need the following:

- [Ruby](https://www.ruby-lang.org/en/)

- [asdcplib and its cli tools](http://www.cinecert.com/asdcplib/)

- [Nokogiri, a ruby wrapper for libxml2](http://nokogiri.org/tutorials/installing_nokogiri.html)

- [dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect) requires xsd/ next to it.

    Clone the whole repository to put everything in place:

        $ git clone git://github.com/wolfgangw/backports.git

Run

    $ git pull

in backports to keep up-to-date.

# What's missing

- Composition metadata (CMA)
- Cross-check of updated naming convention with CMA / claimed asset properties / actual asset properties
- Deep inspection of j2c markers/codestreams
- Deep inspection of SMPTE timed text trackfiles
- Better audio analysis wrt loudness
- Assetmap options chunks, offsets, volume indices
- Markers
- Check Signer.X509IssuerSerial issuer name

# Thank you

Thanks to Julik for his Timecode library (https://github.com/guerilla-di/timecode).
Thanks to all the awesome people who tested, provided test materials, discussed and contributed. `dcp_inspect` wouldn't be a thing without you.

Runs on linux, macOS and windows (WSL) boxes.

Wolfgang Woehl 2011-2023

