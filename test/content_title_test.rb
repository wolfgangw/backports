# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../lib/dcp_inspect/inspection/content_title'
require_relative 'support/inspection_fixture'

class ContentTitleTest < Minitest::Test
  include InspectionFixture
  Parser = DcpInspect::Inspection::ContentTitle
  NAME = 'Film_FTR-1-2D_S_EN-XX_INT_51_4K_DI_20250917_DLX_SMPTE_OV'

  def test_modern_and_legacy_names
    p = Parser.parse(NAME)
    assert p[:recognized]
    assert_equal '1', p[:version]
    assert_equal '4K', p[:resolution]
    assert_equal 'SMPTE', p[:standard]
    legacy = Parser.parse('NAME-OF-MOVIE_TLR1-3D_F_EN-XX_US-GB_51-EN_48_ST_20070115_FAC_i3D-ngb_OV')
    assert_equal 48, legacy[:frame_rate]
    assert_equal '2K', legacy[:resolution]
    assert_equal 'Interop', legacy[:standard]
    assert_equal '3D', legacy[:dimension]
  end

  def test_missing_fields_do_not_shift_claims
    p = Parser.parse('LolaMontez_FTR-25_S-255_DE-XX_51_2K_FMM_20190226_FMM_SMPTE_OV')
    assert_nil p[:fields][:territory]
    assert_equal '51', p[:fields][:audio]
    assert_equal 'FMM', p[:fields][:studio]
    assert_equal '20190226', p[:fields][:date]
  end

  def test_language_case_is_meaningful
    p = Parser.parse(NAME.sub('EN-XX', 'QFC-fr-FR-Fr'))
    assert_equal 'fr-CA', p[:audio_language][:tag]
    assert_equal %w[burnt-in rendered unknown], p[:subtitles].map { |s| s[:mode] }
    refute Parser.parse('A free form title')[:recognized]
    refute Parser.parse('a_' * 65)[:recognized]
    unknown = Parser.parse(NAME.sub('2D', '2d').sub('_51_', '_iab-51_'))[:unknown]
    assert_equal %w[2d iab], unknown.map { |field| field[:token] }
  end

  def test_vf_suffix_is_not_a_version_or_frame_rate
    p = Parser.parse(NAME.sub('FTR-1-2D', 'FTR-25-3D-6fl-48').sub('_OV', '_VF-1'))
    assert_equal '25', p[:version]
    assert_equal 48, p[:frame_rate]
    assert_equal 'VF-1', p[:package_type]
    assert_empty Parser.compare(p, { external_ids: ['missing'] })
    assert Parser.compare(p, { external_ids: [] }).any? { |m| m.include?('claims VF') }
  end

  def test_title_mismatch_is_a_hint_not_technical_evidence
    with_inspection_fixture do
      # Fixture filenames are intentionally unrelated to content declarations.
      path = Dir[File.join(@directory, '*.xml')].find { |f| File.read(f).include?('<CompositionPlaylist') }
      File.write(path, File.read(path).sub('Metadata test', NAME.sub('_OV', '_VF')))
      write_package
      result = inspect_fixture
      assert_empty result[:errors]
      assert result[:hints].any? { |m| m.include?('claims VF') }
      assert result[:hints].any? { |m| m.include?('standard claims SMPTE') }
    end
  end
end
