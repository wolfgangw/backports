# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class CompositionReportingTest < Minitest::Test
  include InspectionFixture
  Reporting = DcpInspect::Inspection::CompositionReporting

  def test_summary_reports_observed_sound_kind_and_pkl_sizes
    with_inspection_fixture do
      result = inspect_fixture
      assert_empty result[:errors]
      cpl = result[:inspection_run].compositions.values.first
      assert_includes cpl.summary, 'Kind: feature'
      assert_includes cpl.summary, 'PCM 6ch container / 48 kHz / 24-bit'
      assert_includes cpl.summary, 'PKL asset sizes:'
      refute_includes cpl.summary, 'NaN'
      bytes = %w[CPL.xml picture.mxf sound.mxf].sum { |name| File.size(File.join(@directory, name)) }
      assert_equal [{ pkl_id: fixture_uuid(2), listed_bytes: bytes, available_bytes: bytes }], cpl.summary_details[:packages]
      assert_equal cpl.summary_details, cpl.to_h[:summary_details]
    end
  end

  def test_unmapped_assets_still_contribute_to_declared_size
    with_inspection_fixture do
      path = File.join(@directory, 'ASSETMAP')
      xml = Nokogiri::XML(File.read(path))
      xml.xpath('//*[local-name()="Asset"]').find { |asset| asset.at_xpath('*[local-name()="Id"]').text.end_with?(fixture_uuid(5)) }.remove
      File.write(path, xml.to_xml)
      cpl = inspect_fixture[:inspection_run].compositions.values.first
      sizes = cpl.summary_details[:packages].first
      assert_equal File.size(File.join(@directory, 'sound.mxf')), sizes[:listed_bytes] - sizes[:available_bytes]
      assert_includes cpl.summary, '1/1 MainSound references unavailable or not PCM'
    end
  end

  def test_missing_sound_does_not_imply_a_format_change
    track = { essence: V::Audio, channels: '8', sample_rate: '48000/1', bits: '24' }
    refs = [{ kind: 'MainSound' }, { kind: 'MainSound' }]
    summary = Reporting.sound([track], refs, [])[:text]
    assert_includes summary, '8ch container'
    assert_includes summary, '1/2 MainSound references unavailable'
    refute_includes summary, '7.1'
    refute_includes summary, 'format changes'
    changed = Reporting.sound([track, track.merge(channels: '6')], refs, [])[:text]
    assert_includes changed, 'format changes across reels'
  end

  def test_no_main_sound_and_immersive_presence_are_independent
    summary = Reporting.sound([], [], ['iab', 'iab'])
    assert_includes summary[:text], 'no MainSound'
    assert_includes summary[:text], 'IAB/Atmos present'
    assert_equal ['iab'], summary[:immersive_asset_ids]
  end

  def test_overlapping_packing_lists_are_reported_separately
    pkl = Struct.new(:id, :package_size_listed, :package_size_actual)
    first = pkl.new('one', 100, 90)
    second = pkl.new('two', nil, 70)
    packages = Reporting.packages([first, first, second])
    assert_equal 2, packages.size
    assert_equal 100, packages.first[:listed_bytes]
    assert_nil packages.last[:listed_bytes]
    assert_includes Reporting.package_text(packages), 'unknown listed'
  end
end
