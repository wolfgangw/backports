## dcp_inspect inspects and checks DCP media and directories

### Usage

        dcp_inspect /path/to/dir
        dcp_inspect --help

### Features

- Checks all packages under a given location

- Runs schema validation on all infrastructure files and DCSubtitle

    Validation errors will be reported but dcp_inspect will still try to inspect the contents of non-valid files.

- Checks and verifies signatures

    Signature verification requires a recent Nokogiri version with C14N support (See Requirements). If the installed version of Nokogiri does not support C14N dcp_inspect will skip signature verification and let you know.

- Deep-inspects compositions

- Reports in detail all errors encountered

### Requirements

- [asdcplib and its cli tools](http://www.cinecert.com/asdcplib/)

- [Nokogiri, a ruby wrapper for libxml2](http://nokogiri.org/tutorials/installing_nokogiri.html)

    For verification of signatures dcp_inspect requires a recent Nokogiri version with C14N support. See [MISC on Digital Cinema Tools](https://github.com/wolfgangw/digital_cinema_tools/wiki/MISC) for notes on how to install Nokogiri with C14N support from [current git](https://github.com/tenderlove/nokogiri)

- dcp_inspect requires xsd/ next to it.

    Clone the whole repository to put everything in place:

        $ git clone git://github.com/wolfgangw/backports.git

Run

    $ git pull

in backports to keep up-to-date.

### Couple of todos

- Package format consistency checks (Interop/SMPTE)
- Some Assetmap options (Offsets, volume indices) are not handled
- Marker lists are not handled
- Check Signer.X509IssuerSerial info
- Sound present in SMPTE DCP reels?
- Verbosity levels

Thanks to Julik for his Timecode library (https://github.com/guerilla-di/timecode).

Tested on linux and Mac OS boxes. Let me know if dcp_inspect actually runs on Windows.

Copyright 2011-2012 Wolfgang Woehl

