# frozen_string_literal: true

require "minitest/autorun"
require "nokogiri"
require "digest"
require "dcp_inspect"

class SchemaStoreTest < Minitest::Test
  KDM_SCHEMAS = %w[
    SMPTE-430-1-2006-Amd-1-2009-KDM.xsd
    SMPTE-430-3-2008-ETM.xsd
    SMPTE-430-7-2008-FLM.xsd
    SMPTE-430-9-2008-KDMB.xsd
  ].freeze

  def test_catalog_is_relocatable
    catalog = File.read(File.join(DcpInspect.xsd_dir, "catalog.xml"))

    assert_includes catalog, 'xml:base="./"'
    refute_includes catalog, "will/be/patched"
  end

  def test_includes_future_kdm_schema_family
    KDM_SCHEMAS.each do |schema|
      assert File.file?(File.join(DcpInspect.xsd_dir, schema)), schema
    end
  end

  def test_schema_manifest_matches_authoritative_files
    expected_files = {}
    File.foreach(File.join(DcpInspect.xsd_dir, "MANIFEST.sha256")) do |line|
      expected, filename = line.split
      expected_files[filename] = expected
      actual = Digest::SHA256.file(File.join(DcpInspect.xsd_dir, filename)).hexdigest
      assert_equal expected, actual, filename
    end

    actual_files = Dir.children(DcpInspect.xsd_dir).reject { |filename| filename == "MANIFEST.sha256" }
    assert_equal expected_files.keys.sort, actual_files.sort
  end

  def test_primary_dcp_schemas_compile_from_read_only_store
    previous_catalog = ENV["XML_CATALOG_FILES"]
    store = DcpInspect::XML::SchemaStore.new

    %w[
      PROTO-ASDCP-AM-20040311.xsd
      PROTO-ASDCP-PKL-20040311.xsd
      PROTO-ASDCP-CPL-20040511.xsd
      SMPTE-429-9-2007-AM.xsd
      SMPTE-429-8-2006-PKL.xsd
      SMPTE-429-7-2006-CPL.xsd
    ].each do |schema|
      assert_instance_of Nokogiri::XML::Schema, store.schema(schema)
    end

    if previous_catalog
      assert_equal previous_catalog, ENV["XML_CATALOG_FILES"]
    else
      assert_nil ENV["XML_CATALOG_FILES"]
    end
  end
end
