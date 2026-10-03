# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/inspection_fixture"

class MetadataHashTest < Minitest::Test
  include InspectionFixture

  def test_matching_hashes_ignore_xml_whitespace_without_reading_asset_digest
    with_inspection_fixture do
      digest = Digest::SHA1.file(File.join(@directory, "picture.mxf")).base64digest
      write_cpl(reels: [reference("MainPicture", 4, "<Hash>\n#{digest}\n</Hash>") + reference("MainSound", 5)])
      write_package
      result = inspect_fixture
      assert_empty result[:errors]
    end
  end

  def test_cpl_pkl_mismatch_is_reported_when_hashing_is_disabled
    with_inspection_fixture do
      write_cpl(reels: [reference("MainPicture", 4, "<Hash>#{Digest::SHA1.base64digest('wrong')}</Hash>") + reference("MainSound", 5)])
      write_package
      result = inspect_fixture
      assert result[:errors].any? { |message| message.include?("CPL/PKL Hash mismatch") }, result[:errors].inspect
      assert_equal 1, result[:inspection_run].compositions.length
      assert_includes result[:inspection_run].compositions.values.first.complete, "Composition complete"
    end
  end

  def test_absent_optional_cpl_hash_is_not_an_error
    with_inspection_fixture { assert_empty inspect_fixture[:errors] }
  end

  def test_hash_declarations_remain_scoped_to_the_pkl_unless_using_asset_store
    with_inspection_fixture do
      digest = Digest::SHA1.file(File.join(@directory, "picture.mxf")).base64digest
      write_cpl(reels: [reference("MainPicture", 4, "<Hash>#{digest}</Hash>") + reference("MainSound", 5)])
      write_package
      other = File.read(File.join(@directory, "PKL.xml"))
        .sub(fixture_uuid(2), fixture_uuid(6)).sub(digest, Digest::SHA1.base64digest("other"))
      doc = Nokogiri::XML(other)
      doc.xpath("//p:Asset", "p" => V::Interop_pkl).each do |asset|
        asset.remove unless asset.at_xpath("p:Id", "p" => V::Interop_pkl).text.end_with?(fixture_uuid(4))
      end
      File.write(File.join(@directory, "other.xml"), doc.to_xml)
      am_path = File.join(@directory, "ASSETMAP")
      File.write(am_path, File.read(am_path).sub("</AssetList>",
        "<Asset><Id>urn:uuid:#{fixture_uuid(6)}</Id><PackingList/><ChunkList><Chunk><Path>other.xml</Path></Chunk></ChunkList></Asset></AssetList>"))
      refute inspect_fixture[:errors].any? { |message| message.include?("CPL/PKL Hash mismatch") }
      assert inspect_fixture("--as-asset-store")[:errors].any? { |message| message.include?("CPL/PKL Hash mismatch") }
    end
  end
end
