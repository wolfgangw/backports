# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class MetadataMarkersTest < Minitest::Test
  include InspectionFixture

  def markers(entries, intrinsic: '240', entry: '0', duration: nil, rate: '24 1')
    list = entries.map do |label, offset, scope|
      "<Marker><Label#{scope ? " scope=\"#{scope}\"" : ''}>#{label}</Label><Offset>#{offset}</Offset></Marker>"
    end.join
    reference('MainMarkers', 20, "<MarkerList>#{list}</MarkerList>", intrinsic: intrinsic, entry: entry, duration: duration, rate: rate)
  end

  def run_markers(*groups)
    with_inspection_fixture do
      write_cpl(reels: groups.map { |group| reference('MainPicture', 4) + reference('MainSound', 5) + group })
      write_package
      yield inspect_fixture
    end
  end

  def test_valid_markers_do_not_require_a_track_file
    run_markers(markers([['FFOC', 0], ['LFOC', 239]])) do |result|
      assert_empty result[:errors]
      check = result[:inspection_run].compositions.values.first.checks.find { |c| c.kind == :markers }
      assert_equal :ok, check.status
      assert_equal '239/24', check.details[:markers].last[:seconds]
    end
  end

  def test_entrypoint_and_reel_origin_are_applied
    run_markers('', markers([['FFOC', 24], ['LFOC', 264]], intrinsic: '264', entry: '24', duration: '240')) do |result|
      assert_empty result[:errors]
      check = result[:inspection_run].compositions.values.first.checks.find { |c| c.kind == :markers }
      assert_equal '10/1', check.details[:markers].first[:seconds]
      assert_equal '20/1', check.details[:markers].last[:seconds]
    end
  end

  def test_custom_scope_allows_unknown_and_repeated_labels
    run_markers(markers([['Cue', 0, 'urn:example:markers'], ['Cue', 240, 'urn:example:markers']])) do |result|
      assert_empty result[:errors]
    end
  end

  def test_trimmed_markers_do_not_inherit_another_markers_position
    run_markers(markers([['FFOC', 24], ['FFTC', 0], ['LFOC', 264]], intrinsic: '264', entry: '24', duration: '240')) do |result|
      assert_empty result[:errors]
      check = result[:inspection_run].compositions.values.first.checks.find { |c| c.kind == :markers }
      trimmed = check.details[:markers][1]
      refute trimmed[:active]
      assert_nil trimmed[:seconds]
    end
  end

  def test_bad_offsets_and_rates_are_findings
    run_markers(markers([['FFOC', '-1'], ['LFOC', 241]])) do |result|
      assert result[:errors].any? { |m| m.include?('invalid Offset') }
      assert result[:errors].any? { |m| m.include?('exceeds IntrinsicDuration') }
    end
    run_markers(markers([['FFOC', 0]], rate: '24 0')) do |result|
      assert result[:errors].any? { |m| m.include?('MainMarkers: invalid EditRate') }
    end
  end

  def test_duplicate_and_reversed_standard_markers
    run_markers(markers([['FFOC', 239], ['LFOC', 0], ['FFEC', 100], ['FFEC', 120]])) do |result|
      assert result[:errors].any? { |m| m.include?('Duplicate standard marker FFEC') }
      assert result[:errors].any? { |m| m.include?('FFOC occurs after LFOC') }
    end
  end

  def test_unknown_standard_label_and_last_offset_are_reported
    run_markers(markers([['UNKN', 20]])) do |result|
      assert result[:errors].any? { |m| m.include?('unknown standard marker') }
      assert result[:errors].any? { |m| m.include?('does not correspond to IntrinsicDuration') }
    end
  end
end
