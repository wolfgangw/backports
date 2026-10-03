# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class AssetmapPackingListTest < Minitest::Test
  include InspectionFixture

  def smpte_assetmap(pkl_value, asset_value)
    path = File.join(@directory, 'ASSETMAP')
    xml = Nokogiri::XML(File.read(path).sub(V::Interop_am, V::Smpte_am))
    xml.remove_namespaces!
    xml.xpath('//Asset').each do |asset|
      value = asset.at_xpath('PackingList') ? pkl_value : asset_value
      asset.xpath('PackingList').remove
      asset.at_xpath('Id').add_next_sibling("<PackingList>#{value}</PackingList>") unless value.nil?
    end
    xml.root['xmlns'] = V::Smpte_am
    File.write(path, xml.to_xml)
    File.rename(path, path + '.xml')
  end

  def test_smpte_boolean_values_only_register_actual_packing_lists
    [['true', 'false'], ['1', '0'], [" true \n", " false \n"], ['true', nil]].each do |pkl_value, asset_value|
      with_inspection_fixture do
        smpte_assetmap(pkl_value, asset_value)
        result = inspect_fixture
        assert_empty result[:errors], result[:errors].inspect
        assert_equal [fixture_uuid(2)], result[:inspection_run].packing_lists.keys
        assert_equal 1, result[:inspection_run].compositions.size
      end
    end
  end

  def test_invalid_boolean_is_reported_without_registering_asset_as_pkl
    ['', 'FALSE', 'yes'].each do |value|
      with_inspection_fixture do
        smpte_assetmap('true', value)
        result = inspect_fixture
        assert result[:errors].any? { |error| error.include?('Invalid SMPTE PackingList boolean') }
        refute result[:errors].any? { |error| error.include?('Not a PackingList') }
        assert_equal [fixture_uuid(2)], result[:inspection_run].packing_lists.keys
      end
    end
  end

  def test_interop_empty_marker_still_identifies_packing_list
    with_inspection_fixture do
      result = inspect_fixture
      assert_empty result[:errors]
      assert_equal [fixture_uuid(2)], result[:inspection_run].packing_lists.keys
    end
  end
end
