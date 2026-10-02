# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "open3"
require "dcp_inspect"
require_relative "support/cli_environment"

class DocumentReaderTest < Minitest::Test
  include CLIEnvironment

  def test_missing_and_empty_identifiers_return_nil
    ["", "<Id/>", "<Id> </Id>", "<Id>urn:uuid:</Id>",
     "<AssetList><Asset><Id>urn:uuid:child-id</Id></Asset></AssetList>"].each do |body|
      assert_nil read_uuid("<AssetMap>#{body}</AssetMap>"), body
    end
  end

  def test_reads_infrastructure_and_legacy_subtitle_identifiers
    assert_equal "asset-id", read_uuid('<AssetMap xmlns="urn:test"><Id>urn:uuid:asset-id</Id></AssetMap>')
    assert_equal "subtitle-id", read_uuid('<DCSubtitle><SubtitleID> subtitle-id </SubtitleID></DCSubtitle>')
    assert_equal "metadata-id", read_uuid('<DCMetadata><MetadataID>metadata-id</MetadataID></DCMetadata>')
  end

  def test_missing_assetmap_id_reports_validation_errors_and_continues
    with_cli_environment do |directory, environment|
      %w[a-missing-id b-empty-id c-another-map].each { |name| Dir.mkdir(File.join(directory, name)) }
      namespace = 'http://www.smpte-ra.org/schemas/429-9/2007/AM'
      File.write(File.join(directory, "a-missing-id/ASSETMAP.xml"), "<AssetMap xmlns=\"#{namespace}\"><AssetList/></AssetMap>")
      File.write(File.join(directory, "b-empty-id/ASSETMAP.xml"), "<AssetMap xmlns=\"#{namespace}\"><Id/><AssetList/></AssetMap>")
      id = "01234567-89ab-4cde-8fab-0123456789ab"
      File.write(File.join(directory, "c-another-map/ASSETMAP.xml"), "<AssetMap xmlns=\"#{namespace}\"><Id>urn:uuid:#{id}</Id><AssetList/></AssetMap>")
      result_file = File.join(directory, "result.json")

      _stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, DcpInspect.executable,
        "--nh", "--na", "--dump-result", result_file, directory)
      assert_equal 1, status.exitstatus, stderr
      result = JSON.parse(File.read(result_file))
      assert result.fetch("errors").any? { |error| error.include?("Schema check") }
      assert_equal 2, result.fetch("errors").count { |error| error.include?("has no Id") }
      assert_includes result.fetch("inspection_run").fetch("assetmaps").map { |am| am.fetch("id") }, id
    end
  end

  private

  def read_uuid(xml)
    logger = Object.new
    logger.define_singleton_method(:info) { |_message| }
    reader = DcpInspect::XML::DocumentReader.new(logger: logger, mxf_inspector: ->(_) { flunk "XML treated as MXF" })
    Tempfile.create("dcp-id") do |file|
      file.write(xml)
      file.flush
      reader.asset_uuid(file.path)
    end
  end
end
