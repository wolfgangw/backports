# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class PictureRatesTest < Minitest::Test
  include InspectionFixture
  Rates = DcpInspect::Inspection::PictureRates
  Timing = DcpInspect::Inspection::Timing

  def set_rate(rate, essence: V::Pictures, stereo: false, smpte: false, sample: rate)
    @metadata['picture.mxf'].merge!('EssenceType' => essence, 'EditRate' => rate, 'SampleRate' => sample)
    @metadata['sound.mxf']['EditRate'] = rate
    @metadata.each_value { |m| m['Label Set Type'] = smpte ? 'SMPTE' : 'MXF Interop' }
    write_cpl(namespace: smpte ? V::Smpte_cpl : V::Interop_cpl, reels: [
      reference(stereo ? 'MainStereoscopicPicture' : 'MainPicture', 4, "<FrameRate>#{sample.tr('/', ' ')}</FrameRate>", rate: rate.tr('/', ' ')) + reference('MainSound', 5, rate: rate.tr('/', ' '))])
    write_package
  end

  def test_fractional_jpeg2000_is_invalid_even_when_all_metadata_agree
    with_inspection_fixture do
      set_rate('24000/1001')
      result = inspect_fixture
      assert result[:errors].any? { |m| m.include?('JPEG2000') && m.include?('24000/1001 (≈23.976)') && m.include?(fixture_uuid(4)) }
      model = result[:inspection_run].compositions.values.first
      assert model.checks.any? { |c| c.kind == :picture_rate && c.status == :error }
      assert_includes model.summary, '24000/1001 (≈23.976) fps'
      assert_includes model.summary, '240 edit units'
      refute result[:errors].any? { |m| m.include?('MainSound') }
    end
  end

  def test_legacy_mpeg2_fractional_rate_is_supported
    with_inspection_fixture do
      set_rate('24000/1001', essence: V::Mpeg2)
      @metadata['picture.mxf'].delete('DecompositionLevels')
      result = inspect_fixture
      assert_empty result[:errors]
      refute result[:hints].any? { |m| m.include?('non-24') || m.include?('old legacy') }
    end
  end

  def test_normalized_integer_and_stereo_rates
    with_inspection_fixture do
      set_rate('48000/2000')
      assert_empty inspect_fixture[:errors]
      set_rate('24/1', essence: V::Stereoscopic_pictures, stereo: true, sample: '48/1')
      assert_empty inspect_fixture[:errors]
      set_rate('48/1', essence: V::Stereoscopic_pictures, stereo: true, smpte: true, sample: '96/1')
      result = inspect_fixture
      assert_empty result[:errors]
      assert result[:hints].any? { |m| m.include?('per eye') && m.include?('remain unchecked') }
    end
  end

  def test_baseline_and_extended_rates_do_not_claim_full_profile_validation
    with_inspection_fixture do
      [24,25,30,48,50,60].each do |rate|
        set_rate("#{rate}/1", smpte: true)
        assert_empty Rates.findings(@metadata['picture.mxf'], composition_type: 'SMPTE', stereoscopic: false)
      end
      @metadata['picture.mxf'].merge!('StoredWidth' => '3996', 'StoredHeight' => '2160')
      assert_equal :hint, Rates.findings(@metadata['picture.mxf'], composition_type: 'SMPTE', stereoscopic: false).first.first
      set_rate('25/1')
      assert_equal :hint, Rates.findings(@metadata['picture.mxf'], composition_type: 'Interop', stereoscopic: false).first.first
      set_rate('24/1', sample: '48/1')
      assert Rates.findings(@metadata['picture.mxf'], composition_type: 'Interop', stereoscopic: false).any? { |s,m| s == :error && m.include?('SampleRate') }
    end
    assert_equal '24 fps', Timing.format_rate(Rational(48000,2000))
    assert_equal '[invalid rate]', Timing.format_rate(nil)
  end
end
