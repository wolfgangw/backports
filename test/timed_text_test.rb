# frozen_string_literal: true
require 'minitest/autorun'
require 'nokogiri'
require_relative 'support/inspection_fixture'
require_relative '../lib/dcp_inspect/inspection/timed_text'

class TimedTextTest < Minitest::Test
  include InspectionFixture
  Checker = DcpInspect::Inspection::TimedText

  def document(contents, smpte: false, extra: '')
    if smpte
      Nokogiri::XML("<SubtitleReel xmlns='http://www.smpte-ra.org/schemas/428-7/2010/DCST'><Id>urn:uuid:#{fixture_uuid(6)}</Id><EditRate>24 1</EditRate><TimeCodeRate>24</TimeCodeRate>#{extra}<SubtitleList>#{contents}</SubtitleList></SubtitleReel>")
    else
      Nokogiri::XML("<DCSubtitle><SubtitleID>#{fixture_uuid(6)}</SubtitleID><ReelNumber>1</ReelNumber><Language>English</Language>#{extra}#{contents}</DCSubtitle>")
    end
  end

  def spot(number = 1, start = '00:00:01:000', finish = '00:00:02:000', body = '<Text>Hello</Text>')
    "<Subtitle SpotNumber='#{number}' TimeIn='#{start}' TimeOut='#{finish}'>#{body}</Subtitle>"
  end

  def test_interop_ticks_and_fractional_seconds_are_not_picture_frames
    assert_equal Rational(1, 2), Checker.time('00:00:00:125')
    assert_equal Rational(1, 2), Checker.time('00:00:00.5')
    assert_nil Checker.time('00:00:00:250')
    assert_nil Checker.time('00:60:00:000')
    assert_equal Rational(1, 24), Checker.time('00:00:00:01', smpte: true, rate: 24)
  end

  def test_order_intervals_fades_spot_continuity_and_stray_text
    xml = document(spot(1, '00:00:03:000', '00:00:02:000') + spot(3, '00:00:01:000', '00:00:02:000', 'lost<Font><Text>nested</Text></Font>'))
    codes = Checker.new(xml).findings.map { |f| f[:code] }
    %w[interval.not-positive order.not-ascending spot.discontinuity text.outside-text].each { |code| assert_includes codes, "timed-text.#{code}" }
  end

  def test_font_ids_and_nested_text_are_resolved_semantically
    xml = document(spot(1, '00:00:01:000', '00:00:02:000', '<Font Id="undeclared"><Text>Hello <Font Id="also-missing">world</Font></Text></Font>'))
    findings = Checker.new(xml).findings
    assert_equal 2, findings.count { |f| f[:code] == 'timed-text.font.reference-missing' }
    assert findings.any? { |f| f[:code] == 'timed-text.font.multiple-ids' }
  end

  def test_smpte_start_time_and_trimmed_playback_window
    xml = document(spot(1, '01:00:01:00', '01:00:02:00'), smpte: true, extra: '<StartTime>01:00:00:00</StartTime>')
    result = Checker.new(xml, intrinsic: 240, edit_rate: Rational(24), entry_point: 120, duration: 120)
    refute result.findings.any? { |f| f[:code].include?('duration') || f[:code].include?('time-in') }
    assert result.findings.any? { |f| f[:code] == 'timed-text.font.load-font.missing' && f[:severity] == :error }
  end

  def test_png_resource_header_and_missing_resources
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'image.png')
      File.binwrite(path, "\x89PNG\r\n\x1a\n".b + [13].pack('N') + 'IHDR' + [720, 80].pack('NN'))
      xml = document(spot(1, '00:00:01:000', '00:00:02:000', '<Image>image.png</Image>'))
      good = Checker.new(xml) { path }
      assert_empty good.findings
      assert_equal 720, good.summary[:resources].first[:width]
      File.write(path, 'not a PNG')
      assert Checker.new(xml) { path }.findings.any? { |f| f[:code] == 'timed-text.image.invalid' }
      assert Checker.new(xml) { nil }.findings.any? { |f| f[:code] == 'timed-text.resource.missing' }
    end
  end

  def test_closed_captions_overlap_and_image_restrictions
    xml = document(spot(1, '00:00:01:00', '00:00:03:00') + spot(2, '00:00:02:00', '00:00:04:00', '<Image>urn:uuid:00000000-0000-4000-8000-000000000099</Image>'), smpte: true)
    codes = Checker.new(xml, kind: 'ClosedCaption').findings.map { |f| f[:code] }
    assert_includes codes, 'timed-text.closed.overlap'
    assert_includes codes, 'timed-text.closed.image'
  end

  def test_stereoscopic_variable_z_requires_valid_values_and_local_reference
    body = '<LoadVariableZ ID="depth">0:12 101:3</LoadVariableZ><Text VariableZ="other">Hello</Text>'
    xml = document(spot(1, '00:00:01:00', '00:00:03:00', body), smpte: true)
    codes = Checker.new(xml).findings.map { |f| f[:code] }
    %w[variable-z.vector variable-z.fallback variable-z.reference].each do |code|
      assert_includes codes, "timed-text.#{code}"
    end
  end

  def test_inspection_errors_propagate_to_composition_without_changing_completeness
    with_inspection_fixture do
      File.write(File.join(@directory, 'subtitle.xml'), document(spot(1, '00:00:03:000', '00:00:02:000')).to_xml)
      write_cpl(reels: [reference('MainPicture', 4) + reference('MainSound', 5) + reference('MainSubtitle', 6)])
      write_package(assets: [[3, 'CPL.xml', 'text/xml;asdcpKind=CPL'], [4, 'picture.mxf', 'application/x-smpte-mxf;asdcpKind=Picture'], [5, 'sound.mxf', 'application/x-smpte-mxf;asdcpKind=Sound'], [6, 'subtitle.xml', 'text/xml;asdcpKind=Subtitle']])
      result = inspect_fixture
      assert result[:errors].any? { |m| m.include?('TimeOut must be later') }
      composition = result[:inspection_run].compositions.values.first
      assert_equal 'Composition complete ✅', composition.complete
      assert composition.checks.any? { |c| c.kind == :composition && c.status == :error }
      assert composition.checks.any? { |c| c.kind == :subtitles && c.status == :error }
    end
  end
end
