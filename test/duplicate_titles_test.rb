# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class DuplicateTitlesTest < Minitest::Test
  include InspectionFixture
  Checks = DcpInspect::Inspection::MetadataChecks

  def add_second_cpl(title = 'Metadata test')
    path = File.join(@directory, 'CPL.xml')
    doc = Nokogiri::XML(File.read(path))
    doc.at_xpath('/p:CompositionPlaylist/p:Id', 'p' => V::Interop_cpl).content = "urn:uuid:#{fixture_uuid(8)}"
    doc.at_xpath('/p:CompositionPlaylist/p:ContentTitleText', 'p' => V::Interop_cpl).content = title
    File.write(File.join(@directory, 'CPL2.xml'), doc.to_xml)
    write_package(assets: [[3, 'CPL.xml', 'text/xml;asdcpKind=CPL'], [8, 'CPL2.xml', 'text/xml;asdcpKind=CPL'],
      [4, 'picture.mxf', 'application/x-smpte-mxf;asdcpKind=Picture'], [5, 'sound.mxf', 'application/x-smpte-mxf;asdcpKind=Sound']])
  end

  def test_duplicate_title_is_one_hint_attached_to_both_distinct_compositions
    with_inspection_fixture do
      add_second_cpl
      result = inspect_fixture
      assert_empty result[:errors]
      assert_equal 1, result[:hints].count { |m| m.include?('Identical ContentTitleText') }
      result[:inspection_run].compositions.each_value do |model|
        check = model.checks.find { |c| c.kind == :duplicate_title }
        assert_equal :hint, check.status
        assert_equal [fixture_uuid(3), fixture_uuid(8)], check.details[:cpl_ids]
        assert_equal 'Metadata test', check.details[:title]
        assert_equal :complete, model.completeness_status
      end
    end
  end

  def test_repeated_cpl_in_multiple_pkls_is_not_a_duplicate_title
    with_inspection_fixture do
      File.write(File.join(@directory, 'other.xml'), File.read(File.join(@directory, 'PKL.xml')).sub(fixture_uuid(2), fixture_uuid(9)))
      path = File.join(@directory, 'ASSETMAP')
      File.write(path, File.read(path).sub('</AssetList>', "<Asset><Id>urn:uuid:#{fixture_uuid(9)}</Id><PackingList/><ChunkList><Chunk><Path>other.xml</Path></Chunk></ChunkList></Asset></AssetList>"))
      result = inspect_fixture
      assert_empty result[:errors]
      refute result[:hints].any? { |m| m.include?('Identical ContentTitleText') }
      assert_equal 1, result[:inspection_run].compositions.size
    end
  end

  def test_case_whitespace_empty_titles_and_uuid_case_are_not_conflated
    assert_empty Checks.duplicate_titles('a' => 'Title', 'b' => 'title', 'c' => ' Title')
    assert_empty Checks.duplicate_titles('a' => '', 'b' => '', 'c' => ' ', 'd' => ' ')
    assert_empty Checks.duplicate_titles('a-b' => 'Title', 'A-B' => 'Title')
    assert_equal 1, Checks.duplicate_titles('a' => '[Empty]', 'b' => '[Empty]').size
    with_inspection_fixture do
      add_second_cpl('METADATA TEST')
      refute inspect_fixture[:hints].any? { |m| m.include?('Identical ContentTitleText') }
    end
  end
end
