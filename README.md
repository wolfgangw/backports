## dcp_inspect inspects and checks DCP media and directories #

Usage:

        dcp_inspect /path/to/dir
        dcp_inspect --help

dcp_inspect

- checks all packages under a given location

- runs schema validation on all infrastructure files and DCSubtitle

    Validation errors will be reported but dcp_inspect will still try to inspect the contents of non-valid files.

- checks and verifies signatures

    Signature verification requires a recent Nokogiri version with C14N support (See Requirements). If the installed version of Nokogiri does not support C14N dcp_inspect will skip signature verification and let you know.

- deep-inspects compositions

- reports in detail all errors encountered

Requirements:

- [asdcplib and its cli tools](http://www.cinecert.com/asdcplib/)

- [Nokogiri, a ruby wrapper for libxml2](http://nokogiri.org/tutorials/installing_nokogiri.html)

    For verification of signatures dcp_inspect requires a recent Nokogiri version with C14N support. See [MISC on Digital Cinema Tools](https://github.com/wolfgangw/digital_cinema_tools/wiki/MISC) for notes on how to install Nokogiri with C14N support from [current git](https://github.com/tenderlove/nokogiri)

- dcp_inspect requires xsd/ next to it.

    Clone the whole repository to put everything in place:

        $ git clone git://github.com/wolfgangw/backports.git

- Set the environment variable XML_CATALOG_FILES to include the location of xsd/catalog.xml:

        $ export XML_CATALOG_FILES=[/path/to/]backports/xsd/catalog.xml

    Or add the equivalent export/setenv statements to .bashrc/.tcshrc

Run

    $ git pull

in backports to keep up-to-date.

Couple of todos:

- Package format consistency checks (Interop/SMPTE)
- Some Assetmap options (Offsets, volume indices) are not handled
- Marker lists are not handled
- Its output is quite chatty and for now there is no way to tame that other than `--verbosity info` which is chatty too
- A re-write to, again, tame the threads

Thanks to Julik for his Timecode library (https://github.com/guerilla-di/timecode).

Tested on linux boxes. Let me know if dcp_inspect actually runs on Mac OS or Windows.

Copyright 2011-2012 Wolfgang Woehl

