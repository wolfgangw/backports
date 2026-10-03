# dcp_inspect

[dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect) is a tool for deep inspection and technical validation of digital cinema packages (DCP, SMPTE and Interop). This includes integrity checks, asset inspection, schema validation, signature verification and certificate checks, and composition summarization. Basically anyone who needs to establish the validity of a digital cinema package can put [dcp_inspect](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools#wiki-dcp-inspect) to good use.

See [Examples](https://github.com/wolfgangw/backports/wiki/Example-output-from-dcp_inspect) for some of the things it does. Also see [How to use Digital Cinema Tools](https://github.com/wolfgangw/digital_cinema_tools_distribution/wiki/How-to-use-Digital-Cinema-Tools).

# Usage examples

        dcp_inspect --help
        dcp_inspect <path to directory>
        dcp_inspect <path to directory> --no-hash --no-audio-analysis
        dcp_inspect <path to directory> --nh --na
        dcp_inspect <path to directory> --as-asset-store --hash-limit <limit> --logfile <path>

## Metadata validation

Quick inspection (`--nh --na`) still compares any CPL asset hash with its PKL
declaration and checks PKL types against observed XML, MXF, font, or PNG content.
Hash comparisons use the containing PKL by default; `--as-asset-store` also
compares declarations from the combined store. These checks do not replace
file-content hashing.

The inspector checks duplicate asset IDs within an AssetMap or PackingList and
duplicate reel IDs within a CPL. Reuse of an asset across reels or compositions
is permitted. Edit rates are compared as rational numbers, picture FrameRate is
checked separately against the MXF sample rate, and an omitted Duration defaults
to IntrinsicDuration minus EntryPoint. Large durations remain reportable without
overflowing timecode formatting. MPEG2 does not require JPEG2000 decomposition
metadata.

MainMarkers are inspected as timeline metadata. Reports include their reel,
native offset, and composition position where the timeline is known. Validation
covers standard labels, duplicate active standard markers, offsets, ordering,
and composition/credits boundaries. Custom label scopes are retained without
imposing the standard vocabulary. Both last-frame and end-boundary duration
conventions are accepted; markers trimmed by EntryPoint/Duration are retained
but excluded from composition ordering checks. Structured marker records appear
in the composition's `markers` check details in result/model exports.

For signed CPLs and PKLs, the Signer's issuer name, serial number, and optional
subject name are compared with the signing certificate. Identity mismatches are
validation errors even when the cryptographic signature itself verifies.

## Naming and subtitles

ContentTitleText is parsed as a set of naming claims, preserving spelling and
case. Modern and legacy forms use a pinned ISDCF registry snapshot (2026-10-01).
Missing or ambiguous fields remain unknown. Explicit format, dimension, frame
rate, resolution, and OV/VF claims are compared with available evidence;
disagreements are hints, not substitutes for technical validation. OV/VF is
compared with membership in the declaring PKL, independently of whether an
external asset is available elsewhere in an asset store. Parsed claims and
external asset IDs appear in composition `naming` check details.

Interop DCSubtitle XML and extracted SMPTE timed text share timing, font,
resource, and content checks. These cover subtitle ordering, positive intervals,
fade durations, native timeline bounds, font IDs and glyph availability,
unexpected text outside Text/Image elements, and closed-display/stereoscopic
constraints. Spot-number discontinuities and off-center horizontal alignment
are review hints. CPL EntryPoint/Duration may trim the native subtitle timeline.
Detailed findings and resource summaries appear in composition `subtitles`
check details; subtitle errors make composition validation fail independently
of asset completeness.

Interop resources resolve by their exact relative URI and must be listed in the
inspection dictionary. SMPTE XML and ancillary resources are extracted with
`asdcp-unwrap` into a private temporary directory, removed after inspection or
interruption. This runs with `--nh --na` as well. Missing `asdcp-unwrap` or
encrypted timed text produces an explicit unchecked hint. Extraction failures
are errors. Embedded XML is compared with the MXF document ID, namespace, edit
rate, and resource declarations. The installed 2010-namespace subtitle schema
is used unless `--no-schema` is selected; other namespaces get an explicit
schema-unchecked hint alongside semantic/resource checks.

PNG inspection checks the signature, header dimensions, and size relative to
the picture where known; it does not decode pixels or validate every PNG chunk.
Font resources are parsed with TTFunk and checked for required glyphs. These
checks do not simulate subtitle rendering or establish complete application
profile conformance.

## Ruby API

The inspection code is also available as a Ruby library for other tools.
The standalone executable and library share one inspection engine, schema
store, structured result, and TUI implementation. Add this checkout's `lib/`
directory to Ruby's load path (for example, with `ruby -Ilib`) to use it.

```ruby
require "dcp_inspect"

configuration = DcpInspect::Configuration.quick(verbosity: ["quiet"])
result = DcpInspect::Inspector.new(configuration: configuration).call("/dcp")

abort result.errors.join("\n") unless result.ok?
puts result.inspection_run.fetch("compositions").length
```

`Configuration.quick` retains schema, signature, relationship, MXF, and
subtitle inspection while disabling potentially lengthy hashing and audio
analysis. `Configuration.new` preserves the standalone CLI's full defaults.

The complete result can also be exported by the CLI with
`--dump-result result.json`; `--dump-model` remains available for the
`InspectionRun` graph alone.

### Architecture

Requiring `dcp_inspect` loads only namespaced library components; it does not
evaluate the compatibility runtime or start the CLI. The root executable is
a thin `DcpInspect::CLI` wrapper. Extracted components currently include CLI options, the inspection model, filesystem discovery, logging/TUI,
signature verification, timecode, progress reporting, result handling, and the
public engine boundary.

`DcpInspect::Inspector` accepts any engine implementing `call`. The default
`DcpInspect::Engine::Native` now runs the complete inspection in-process;
`DcpInspect::Engine::Subprocess` remains available as an explicit compatibility
and parity-testing backend. XML parsing and schema resolution are isolated under
`DcpInspect::XML`, while `DcpInspect::Application` owns process-level CLI duties
such as arguments, log destinations, the dashboard, and exit statuses.

## Schema store

The `xsd/` directory is the authoritative schema store for `dcp-inspect` and
Dietrich. Its relocatable catalog includes the DCP and future KDM schema
families. After intentionally changing schemas, run `ruby -Ilib -S rake
xsd:manifest`; CI and consumers can verify the complete store with `ruby -Ilib
-S rake xsd:check`.

## Filesystem discovery

`dcp-inspect` prefers `fd` (or Debian's `fdfind`) for fast parallel traversal
and falls back to a behavior-matched Ruby walker when neither executable is
available. Both backends include hidden and ignored regular files, traverse a
symlink supplied as the discovery root, and do not follow symlinks encountered
inside that tree. Output is NUL-delimited when using `fd`, so unusual but valid
filenames remain intact.

Only files named exactly `ASSETMAP` or `ASSETMAP.xml`, with that capitalization,
are AssetMap candidates. Other case variants, suffixes, backups, and partial
matches are never considered.

Compare both traversal backends on a large local tree with:

```sh
ruby benchmark/filesystem_walker.rb /path/to/discovery-root
```

# Installation

Run the standalone CLI from this checkout, keeping `lib/`, `VERSION`, and
`xsd/` alongside the root executable:

```sh
./dcp_inspect /path/to/DCP
./dcp_inspect --tfs /path/to/DCP
```

Fullscreen mode redraws automatically when the terminal is resized. On small terminals, Tab cycles through Package Tree, Compositions, and Findings one panel at a time. Arrow keys scroll or select entries. Findings puts messages related to the selected package, composition, reel, or asset first; Tab into Findings to browse them, with all other findings retained below. During inspection, `q` opens a confirmation: `y` interrupts and saves any requested partial log; `n`, Enter, or Escape continues. After inspection, `q` closes the dashboard immediately.


For development checks, run `ruby -Ilib -S rake test` and
`ruby -Ilib -S rake xsd:check`.

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

- Inspects Interop DCSubtitle and unencrypted SMPTE timed-text XML/resources

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
- Full naming-claim comparison with Composition Metadata Asset (CMA) fields
- Deep inspection of j2c markers/codestreams
- Decryption-key support for encrypted timed text; additional subtitle schema editions
- Better audio analysis wrt loudness
- Assetmap options chunks, offsets, volume indices
- Markers
- Check Signer.X509IssuerSerial issuer name

# Thank you

Thanks to Julik for his Timecode library (https://github.com/guerilla-di/timecode).
Thanks to all the awesome people who test, provide test materials, discuss and contribute. `dcp_inspect` wouldn't be a thing without you.

Runs on linux, macOS and windows (WSL) boxes.

Wolfgang Woehl 2011-2026
