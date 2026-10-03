# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class ScreenAspectRatioTest < Minitest::Test
  include InspectionFixture
  Aspect = DcpInspect::Inspection::ScreenAspectRatio

  def finding(value, width: '1998', height: '1080', scope: nil, format: 'Interop', essence: V::Pictures, display: nil)
    node = Nokogiri::XML('<ScreenAspectRatio/>').root
    node.content = value
    node['scope'] = scope if scope
    Aspect.finding(node, { 'StoredWidth' => width, 'StoredHeight' => height, 'EssenceType' => essence, 'AspectRatio' => display }, composition_type: format)
  end

  def test_flat_scope_full_and_equivalent_rational_declarations
    assert_nil finding('1.85')
    assert_nil finding('1.850', scope: Aspect::INTEROP_SCOPE)
    assert_nil finding('2.39', width: '2048', height: '858')
    assert_nil finding('1.90', width: '2048')
    assert_nil finding('3996 2160', format: 'SMPTE')
    assert_nil finding('185 100', format: 'SMPTE')
    assert_nil Aspect.finding(nil, {}, composition_type: 'Interop')
  end

  def test_custom_scope_and_invalid_values_are_explicitly_unchecked
    assert_match(/custom scope.*unchecked/, finding('2.00', scope: 'urn:custom')[:message])
    ['bad', '0', '-1', 'NaN', 'Infinity'].each do |value|
      assert_match(/cannot be compared/, finding(value)[:message])
    end
    assert_match(/unchecked/, finding('2.00', height: '0')[:message])
    assert_nil finding('1.85', essence: V::Stereoscopic_pictures)
    assert_nil finding('1.78', essence: V::Mpeg2, width: '720', height: '480', display: '16/9')
    assert_match(/unchecked/, finding('1.78', essence: V::Mpeg2)[:message])
  end

  def test_issue_45_is_a_hint_not_a_composition_error
    with_inspection_fixture do
      write_cpl(reels: [reference('MainPicture', 4, "<ScreenAspectRatio scope='#{Aspect::INTEROP_SCOPE}'>2.00</ScreenAspectRatio>") + reference('MainSound', 5)])
      write_package
      result = inspect_fixture
      assert_empty result[:errors]
      assert result[:hints].any? { |m| m.include?('ScreenAspectRatio "2.00"') && m.include?('1998x1080') }
      model = result[:inspection_run].compositions.values.first
      check = model.checks.find { |c| c.kind == :screen_aspect_ratio }
      assert_equal :hint, check.status
      assert_equal fixture_uuid(4), check.details[:asset_id]
      assert_equal :complete, model.completeness_status
    end
  end
end
