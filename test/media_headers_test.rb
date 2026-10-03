# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require_relative 'support/media_fixture'
require_relative '../lib/dcp_inspect/inspection/iab'
require_relative '../lib/dcp_inspect/inspection/jpeg2000_headers'

class MediaHeadersTest < Minitest::Test
  include MediaFixture
  Iab = DcpInspect::Inspection::Iab
  J2k = DcpInspect::Inspection::Jpeg2000Headers
  Mxf = DcpInspect::Inspection::MxfEssence

  def with_track(key, values)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'track.mxf')
      File.binwrite(path, mxf(*values.map { |value| klv(key + "\x01".b, value) }))
      yield path
    end
  end

  def test_iab_beds_objects_and_nested_definitions_are_distinct
    bytes = iab_frame([iab_bed, iab_object(1, children: [iab_object(2)])])
    frame = Iab::Frame.new(StringIO.new(bytes), 0, bytes.size)
    assert_empty frame.errors
    assert_equal 1, frame.beds.size
    assert_equal 2, frame.objects.size
    assert_equal 1, frame.objects.count { |object| object[:top_level] }
  end

  def test_iab_missing_audio_duplicate_ids_and_malformed_boundaries
    bytes = iab_frame([iab_object(2, audio_id: 7), iab_object(2)])
    frame = Iab::Frame.new(StringIO.new(bytes), 0, bytes.size)
    assert frame.errors.any? { |m| m.include?('AudioDataID 7') }
    assert frame.errors.any? { |m| m.include?('Duplicate MetaID') }
    bytes = bytes.byteslice(0...-1)
    assert_raises(Iab::Error) { Iab::Frame.new(StringIO.new(bytes), 0, bytes.size) }
  end

  def test_iab_track_reports_ranges_and_continues_after_bad_frame
    with_track(Mxf::ATMOS, [iab_frame, 'broken', iab_frame([iab_bed])]) do |path|
      result = Iab.inspect_track(path, { 'ContainerDuration' => '3', 'EditRate' => '24/1' })
      assert_equal 3, result[:frames]
      assert_equal 2, result[:parsed_frames]
      assert_equal({ min: 0, max: 1 }, result[:objects])
      assert_equal 1, result[:errors].size
    end
  end

  def test_jpeg2000_valid_cinema_headers_and_descriptor_comparison
    bytes = jpeg2000
    header = J2k.inspect_frame(StringIO.new(bytes), 0, bytes.size, { 'StoredWidth' => '1998', 'StoredHeight' => '1080' })
    assert_empty header[:errors]
    assert_equal 3, header[:tile_parts]
    bad = J2k.inspect_frame(StringIO.new(bytes), 0, bytes.size, { 'StoredWidth' => '2048', 'StoredHeight' => '1080' })
    assert_includes bad[:errors], 'SIZ dimensions differ from MXF picture descriptor'
  end

  def test_jpeg2000_reports_style_and_profile_with_frame_evidence
    with_track(Mxf::J2K, [jpeg2000, jpeg2000(block_style: 1, profile: 2)]) do |path|
      result = J2k.inspect_track(path, { 'ContainerDuration' => '2' })
      assert_equal 2, result[:checked]
      assert_equal 2, result[:errors].size
      assert result[:errors].all? { |error| error[:first_codestream] == 2 }
    end
  end

  def test_klv_damage_stops_at_declared_boundary_without_resynchronizing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'broken.mxf')
      File.binwrite(path, mxf(Mxf::J2K + "\x01\x84".b + [1000].pack('N') + jpeg2000))
      result = J2k.inspect_track(path)
      assert_equal 0, result[:checked]
      assert_match(/beyond the file/, result[:errors].first[:message])
    end
  end
end
