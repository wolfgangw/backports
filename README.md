## dcp_inspect

dcp_inspect is a tool for deep inspection and validation of digital cinema packages (DCP). This includes integrity checks, asset inspection, schema validation, signature and certificate verification and composition summarization. Basically anyone who needs to establish the validity of a digital cinema package can put dcp_inspect to good use.

See the [Examples](https://github.com/wolfgangw/backports/wiki/Example-output-from-dcp_inspect) page for some of the things it can do.

### Usage

        dcp_inspect --help
        dcp_inspect /path/to/dir
        dcp_inspect /path/to/dir --no-hash --no-schema
### Installation

See [Digital Cinema Tools Distribution](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki) for an easy-to-use [Setup](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/Setup) script. This will install everything required (batteries included).

### Features

- Will find and check all DCPs in a filesystem tree

- Runs schema validation on all infrastructure files and DCSubtitle

    Validation errors will be reported but dcp_inspect will still try to inspect the contents of non-valid files.

- Checks and verifies signatures

    Signature verification requires a recent Nokogiri version with C14N support (See Requirements). If the installed version of Nokogiri does not support C14N dcp_inspect will skip signature verification and let you know.

- Deep-inspects compositions

    This includes composition type consistency and completeness checks. dcp_inspect goes through some lengths to determine a composition's type (SMPTE/Interop). It does so by collecting all types referenced and trying to make sense of that list.

- Reports in detail all errors encountered

### Requirements

See [Digital Cinema Tools Distribution](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki) for an easy-to-use [Setup](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/Setup) script. This will install everything required (batteries included). Run the setup occasionally to keep up-to-date.

If you prefer manual installation you will need the following:

- [asdcplib and its cli tools](http://www.cinecert.com/asdcplib/)

- [Nokogiri, a ruby wrapper for libxml2](http://nokogiri.org/tutorials/installing_nokogiri.html)

    For signature verification dcp_inspect requires a recent Nokogiri version with C14N support. See [MISC on Digital Cinema Tools](https://github.com/wolfgangw/digital_cinema_tools/wiki/MISC) for notes on how to install Nokogiri with C14N support from [current git](https://github.com/tenderlove/nokogiri)

- dcp_inspect requires xsd/ next to it.

    Clone the whole repository to put everything in place:

        $ git clone git://github.com/wolfgangw/backports.git

Run

    $ git pull

in backports to keep up-to-date.

### Couple of todos

- Assetmap options chunks, offsets, volume indices are not handled
- Marker lists are not handled
- Check Signer.X509IssuerSerial issuer name
- ~~Sound present in SMPTE DCP reels?~~ Done (9723e0febb)
- ~~Verbosity levels~~ Done (eb5da2ecaf)

Thanks to Julik for his Timecode library (https://github.com/guerilla-di/timecode).

Tested on linux and Mac OS boxes. Thanks to Terrence for trying on a Windows system (it executed but the libxml infrastructure required for schema checking did not work, so there. Wip)

Copyright 2011-2012 Wolfgang Woehl

