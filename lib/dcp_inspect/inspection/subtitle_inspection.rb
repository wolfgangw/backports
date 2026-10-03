# frozen_string_literal: true
require_relative 'timed_text'
require_relative 'timed_text_extraction'

module DcpInspect
  module Inspection
    class Runtime
      module SubtitleInspection
        def inspect_subtitle_document(document, path, dict, context, embedded: false)
          expected = embedded ? 'SubtitleReel' : 'DCSubtitle'
          return { findings: [{ severity: :error, code: 'timed-text.root.invalid', message: "Expected #{expected}, got #{document.root&.name}" }], summary: {} } unless document.root&.name == expected
          resources = (dict || {}).values.map { |relative| File.expand_path(package(relative)) }
          directory = File.dirname(path)
          inspection = TimedText.new(document, context) do |reference|
            if embedded
              # UUID-only filenames are the asdcplib extraction contract.
              File.join(directory, reference) if TimedText::UUID.match?(reference)
            else
              uri = URI.parse(reference)
              next nil if uri.scheme || uri.host || uri.query || uri.fragment || reference.start_with?('/')
              candidate = File.expand_path(URI::RFC2396_PARSER.unescape(uri.path), directory)
              next nil unless resources.include?(candidate)
              # A declared symlink must still resolve inside the selected package.
              root = File.realpath(@package_dir)
              real = File.realpath(candidate) if File.exist?(candidate)
              candidate if real && (real == root || real.start_with?(root + File::SEPARATOR))
            end
          end
          findings = inspection.findings
          if options.schema_validate
            schema = embedded ? (document.root.namespace&.href == 'http://www.smpte-ra.org/schemas/428-7/2010/DCST' ? 'DCDMSubtitle-2010.xsd' : nil) : 'DCSubtitle.v1.mattsson.xsd'
            if schema
              @schema_store.validate(document, schema).each do |error|
                findings << { severity: :error, code: 'timed-text.schema.invalid', message: error.message.strip, line: error.line }
              end
            else
              findings << { severity: :hint, code: 'timed-text.schema.unchecked', message: "No installed subtitle schema for #{document.root.namespace&.href}; semantic/resource checks only" }
            end
          end
          { findings: findings, summary: inspection.summary }
        end

        def inspect_embedded_subtitle(path, meta, dict, context)
          if meta['EncryptedEssence'] == 'Yes'
            return { findings: [{ severity: :hint, code: 'timed-text.encrypted.unchecked', message: 'Encrypted timed text: XML and resources were not inspected (no decryption key)' }], summary: {} }
          end
          TimedTextExtraction.open(path) do |xml_path, _directory|
            document = Nokogiri::XML(File.binread(xml_path)) { |config| config.strict.nonet }
            inspect_subtitle_document(document, xml_path, dict, context, embedded: true)
          end
        rescue TimedTextExtraction::Unavailable => error
          { findings: [{ severity: :hint, code: 'timed-text.extraction.unavailable', message: error.message }], summary: {} }
        rescue TimedTextExtraction::Error, Nokogiri::XML::SyntaxError, SystemCallError => error
          { findings: [{ severity: :error, code: 'timed-text.extraction.failed', message: "Timed-text extraction/parse failed: #{error.message}" }], summary: {} }
        end

        def record_subtitle_findings(result, prefix, errors, hints, inspection_run, cpl_model)
          result[:findings].each do |finding|
            (finding[:severity] == :error ? errors : hints) << "#{prefix}: #{finding[:message]}"
          end
          failed = result[:findings].any? { |finding| finding[:severity] == :error }
          if cpl_model
            status = failed ? :error : result[:findings].any? ? :hint : :ok
            message = result[:findings].empty? ? "#{prefix}: subtitle semantics/resources checked" : "#{prefix}: #{result[:findings].map { |f| f[:message] }.join('; ')}"
            inspection_run.add_check(cpl_model, :subtitles, status, message, result)
          end
          failed
        end
      end
    end
  end
end
