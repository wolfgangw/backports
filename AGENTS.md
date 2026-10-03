# Scope and layout

Work on the Ruby DCP inspector: `dcp_inspect`, `lib/dcp_inspect/`, `xsd/`, related tests and documentation. Leave unrelated repository tools alone.

- `VERSION`: shared release version for CLI, library, fullscreen UI, and reports; currently `1.2026.10.03`.
- `dcp_inspect`: standalone entry point; `lib/dcp_inspect.rb`: library loader.
- `application.rb` and `cli/`: CLI lifecycle, options, dependency checks, logs, exports, exit status.
- `inspector.rb`, `configuration.rb`, `result.rb`, `engine/`: public Ruby API; Native runs in-process, Subprocess runs the CLI.
- `inspection/runtime.rb` and `inspection/orchestrator.rb`: inspection and composition analysis; `audio_analysis.rb`: subprocess supervision and cleanup.
- `model.rb`: packages, AssetMaps (AM), PackingLists (PKL), CompositionPlaylists (CPL), reels, assets, check events.
- `ui.rb`: console logging and fullscreen (`--tfs`) interface. `xml/`, `crypto.rb`, and `filesystem_walker.rb`: parsing/schema resolution, signature verification, discovery.

Paths above are relative to `lib/dcp_inspect/` unless stated otherwise.

# Installation and dependencies

Use Ruby with OpenSSL support; development is tested on Ruby 3.4.6. Install runtime gems and development tools:

```sh
gem install nokogiri ttfunk base64
gem install rake minitest
```

Install asdcplib CLI tools and FFmpeg through the host's package/build setup and put them on `PATH`. `asdcp-info` is required; audio analysis also requires `asdcp-unwrap` and `ffmpeg` with the `ebur128` and `astats` filters, plus POSIX `mkfifo`. Optional `fd`/`fdfind` accelerates discovery; Ruby traversal is the fallback.

Run from the checkout, or deploy `dcp_inspect`, `lib/`, `VERSION`, and `xsd/` together, preserving their relative layout. The distribution is a standalone executable plus library files.

```sh
./dcp_inspect --version
./dcp_inspect --nh --na /path/to/DCP  # skip hashing and audio analysis
./dcp_inspect --tfs /path/to/DCP
```

Use `ruby -Ilib` and `require 'dcp_inspect'` for the Ruby API. `--dump-result` exports the full result; `--dump-model` exports the inspection graph.

# Behavior to preserve

- Discover SMPTE/Interop DCPs recursively; validate AM/PKL/CPL XML, asset availability and hashes, composition consistency, signatures/certificates, and DCSubtitle resources. Record invalid XML and continue inspection where possible.
- Keep meaningful nonzero exit statuses. Interruptions must restore the terminal, clean up audio subprocesses/FIFOs, and preserve requested partial logs.
- Asset completeness and validation success are separate. Findings must describe actual failures.
- Fullscreen mode redraws on resize; small terminals expose every panel through Tab. Findings prioritizes the selected tree item's messages and retains all others. During inspection, `q` requires confirmation; after completion it exits directly.

# Schemas and verification

`xsd/` is the authoritative, relocatable schema store. Keep filenames, `catalog.xml` namespace mappings, and `MANIFEST.sha256` consistent. It includes SMPTE/Interop infrastructure, XML Signature, KDM-family schemas, and `DCDMSubtitle-2010.xsd`; the latter validates extracted SMPTE subtitle XML using the 2010 DCST namespace.

```sh
ruby -Ilib -S rake test
ruby -Ilib -S rake xsd:check
# Only after intentional schema/catalog changes:
ruby -Ilib -S rake xsd:manifest
```

Set `DCP_INSPECT_TEST_DCP` to a known-good package to enable the optional real-DCP integration test. Use temporary copies for destructive cases. Exercise terminal interactions in a PTY when changing the UI.

Check `git status` before changes. Make distinct local commits for distinct changes; do not push unless requested.
