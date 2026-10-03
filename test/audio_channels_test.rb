# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class AudioChannelsTest < Minitest::Test
  include InspectionFixture
  Channels = DcpInspect::Inspection::AudioChannels
  Layout = DcpInspect::Inspection::PcmLayout

  def test_four_channel_interop_is_valid_and_center_stays_channel_three
    with_inspection_fixture do
      meta = @metadata['sound.mxf']
      meta.merge!('ChannelCount' => '4', 'BlockAlign' => '12')
      result = inspect_fixture
      assert_empty result[:errors]
      refute result[:hints].any? { |m| m.include?('channels') }
      layout = Layout.resolve(meta)
      assert_equal [['FL', 0], ['FR', 1], ['FC', 2], ['LFE', 3]], layout[:map]
      assert_includes Layout.pan(layout), 'FC=c2'
    end
  end

  def test_even_counts_and_odd_count_policy_are_format_specific
    [2, 4, 6, 8, 10, 12, 14, 16].each do |count|
      assert_empty Channels.findings('ChannelCount' => count.to_s, 'Label Set Type' => 'MXF Interop')
    end
    [1, 3, 5, 7, 9, 11, 13, 15].each do |count|
      assert_equal :hint, Channels.findings('ChannelCount' => count.to_s, 'Label Set Type' => 'MXF Interop').first.first
      assert_equal :error, Channels.findings('ChannelCount' => count.to_s, 'Label Set Type' => 'SMPTE').first.first
    end
    [nil, '0', '-2', 'four', '4oops', '18'].each do |count|
      assert_equal :error, Channels.findings('ChannelCount' => count).first.first
    end
    assert Channels.findings('ChannelCount' => '10', 'ChannelFormat' => '1', 'Label Set Type' => 'SMPTE').any? { |_, message| message.include?('defines only 8') }
  end
end
