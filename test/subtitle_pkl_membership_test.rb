# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class SubtitlePklMembershipTest < Minitest::Test
  include InspectionFixture

  def subtitle_package
    File.binwrite(File.join(@directory, 'line.png'), "\x89PNG\r\n\x1a\n".b + [13].pack('N') + 'IHDR' + [100, 30].pack('NN'))
    File.write(File.join(@directory, 'subtitle.xml'), "<DCSubtitle><SubtitleID>#{fixture_uuid(6)}</SubtitleID><ReelNumber>1</ReelNumber><Language>en</Language><Subtitle SpotNumber='1' TimeIn='00:00:01:000' TimeOut='00:00:02:000'><Image>line.png</Image></Subtitle></DCSubtitle>")
    write_cpl(reels: [reference('MainPicture', 4) + reference('MainSound', 5) + reference('MainSubtitle', 6)])
    write_package(assets: [[3, 'CPL.xml', 'text/xml;asdcpKind=CPL'], [4, 'picture.mxf', 'application/x-smpte-mxf;asdcpKind=Picture'],
      [5, 'sound.mxf', 'application/x-smpte-mxf;asdcpKind=Sound'], [6, 'subtitle.xml', 'text/xml;asdcpKind=Subtitle'], [7, 'line.png', 'image/png']])
  end

  def remove_png_from_pkl
    path = File.join(@directory, 'PKL.xml')
    doc = Nokogiri::XML(File.read(path))
    asset = doc.at_xpath("//p:Asset[p:Id='urn:uuid:#{fixture_uuid(7)}']", 'p' => V::Interop_pkl)
    asset.remove
    File.write(path, doc.to_xml)
    asset
  end

  def subtitle_check(result)
    result[:inspection_run].compositions.values.first.checks.find { |c| c.kind == :subtitles }
  end

  def test_assetmap_only_image_gets_membership_hint_but_is_still_inspected
    with_inspection_fixture do
      subtitle_package
      remove_png_from_pkl
      result = inspect_fixture
      assert_empty result[:errors]
      check = subtitle_check(result)
      assert_equal :hint, check.status
      finding = check.details[:findings].find { |f| f[:code] == 'timed-text.resource.not-in-pkl' }
      assert_includes finding[:message], fixture_uuid(2)
      assert_equal false, check.details[:resource_memberships].first[:listed]
      assert_equal 100, check.details[:summary][:resources].first[:width]
      assert_equal :complete, result[:inspection_run].compositions.values.first.completeness_status
      File.binwrite(File.join(@directory, 'line.png'), 'broken')
      assert inspect_fixture[:errors].any? { |m| m.include?('no valid PNG') }
      File.unlink(File.join(@directory, 'line.png'))
      assert inspect_fixture[:errors].any? { |m| m.include?('resource unavailable') }
    end
  end

  def test_listed_image_uses_normal_pkl_size_and_hash_checks
    with_inspection_fixture do
      subtitle_package
      result = inspect_fixture(hashes: true)
      assert_empty result[:errors]
      assert_equal true, subtitle_check(result).details[:resource_memberships].first[:listed]
      refute result[:hints].any? { |m| m.include?('absent from CPL context PKL') }
      File.open(File.join(@directory, 'line.png'), 'ab') { |f| f.write('changed') }
      result = inspect_fixture(hashes: true)
      assert result[:errors].any? { |m| m.include?('Size mismatch') }
      assert result[:errors].any? { |m| m.match?(/hash.*mismatch/i) }, result[:errors].inspect
    end
  end

  def test_another_pkl_listing_does_not_hide_the_current_context_hint
    with_inspection_fixture do
      subtitle_package
      asset = remove_png_from_pkl
      File.write(File.join(@directory, 'other.xml'), "<PackingList xmlns='#{V::Interop_pkl}'><Id>urn:uuid:#{fixture_uuid(8)}</Id><AssetList>#{asset.to_xml}</AssetList></PackingList>")
      path = File.join(@directory, 'ASSETMAP')
      File.write(path, File.read(path).sub('</AssetList>', "<Asset><Id>urn:uuid:#{fixture_uuid(8)}</Id><PackingList/><ChunkList><Chunk><Path>other.xml</Path></Chunk></ChunkList></Asset></AssetList>"))
      [[], ['--as-asset-store']].each do |flags|
        result = inspect_fixture(*flags)
        assert_empty result[:errors]
        assert result[:hints].any? { |m| m.include?('absent from CPL context PKL') && m.include?(fixture_uuid(2)) }
      end
    end
  end

  def test_font_membership_and_unmapped_paths_are_independent_of_resource_type
    with_inspection_fixture do
      # Bad font bytes intentionally prove that membership does not bypass the
      # resource's own validation.
      File.write(File.join(@directory, 'font.ttf'), 'broken')
      document = Nokogiri::XML("<DCSubtitle><SubtitleID>#{fixture_uuid(6)}</SubtitleID><ReelNumber>1</ReelNumber><Language>en</Language><LoadFont Id='main' URI='font.ttf'/></DCSubtitle>")
      runtime = Runtime.new(options: DcpInspect::CLI::Options.parse(['--nh', '--na', '--no-schema']), stdout: StringIO.new)
      runtime.instance_variable_set(:@package_dir, @directory)
      context = { pkl_id: fixture_uuid(2), pkl_asset_ids: [], resource_dict: { fixture_uuid(7) => 'font.ttf' } }
      result = runtime.inspect_subtitle_document(document, File.join(@directory, 'subtitle.xml'), {}, context)
      assert result[:findings].any? { |f| f[:code] == 'timed-text.resource.not-in-pkl' && f[:severity] == :hint }
      assert result[:findings].any? { |f| f[:code] == 'timed-text.font.invalid' }
      context[:resource_dict] = {}
      result = runtime.inspect_subtitle_document(document, File.join(@directory, 'subtitle.xml'), {}, context)
      assert result[:findings].any? { |f| f[:code] == 'timed-text.resource.missing' }
    end
  end
end
