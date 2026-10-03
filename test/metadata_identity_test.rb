# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/inspection_fixture"

class MetadataIdentityTest < Minitest::Test
  include InspectionFixture

  def test_pkl_checks_observed_essence_even_without_a_composition
    with_inspection_fixture do
      write_package(assets: [[4, "picture.mxf", "application/x-smpte-mxf;asdcpKind=Sound"]])
      result = inspect_fixture
      assert result[:errors].any? { |error| error.include?("does not match inspected picture") }, result[:errors].inspect
      assert_empty result[:inspection_run].compositions
    end
  end

  def test_declared_types_are_compared_without_parameter_casing_or_spacing_noise
    with_inspection_fixture do
      write_package(assets: [[4, "picture.mxf", "APPLICATION/X-SMPTE-MXF; asdcpKind = PICTURE"]])
      refute inspect_fixture[:errors].any? { |error| error.include?("does not match inspected") }
    end
  end

  def test_wrong_generic_mxf_type_in_interop_is_reported
    with_inspection_fixture do
      write_package(assets: [[4, "picture.mxf", "application/mxf"]])
      assert inspect_fixture[:errors].any? { |error| error.include?("expected application/x-smpte-mxf;asdcpkind=picture") }
    end
  end

  def test_actual_png_signature_takes_precedence_over_filename
    with_inspection_fixture do
      File.binwrite(File.join(@directory, "resource.dat"), "\x89PNG\r\n\x1a\n".b)
      write_package(assets: [[6, "resource.dat", "application/ttf"]])
      assert inspect_fixture[:errors].any? { |error| error.include?("expected image/png") }
    end
  end

  def test_duplicate_am_and_pkl_ids_are_reported_before_dictionary_overwrite
    with_inspection_fixture do
      write_package(assets: [[4, "picture.mxf", "application/x-smpte-mxf;asdcpKind=Picture"]] * 2)
      path = File.join(@directory, "ASSETMAP")
      document = Nokogiri::XML(File.read(path))
      asset = document.at_xpath("//am:Asset[am:Id='urn:uuid:#{fixture_uuid(4)}']", "am" => V::Interop_am)
      asset.add_next_sibling(asset.dup)
      File.write(path, document.to_xml)
      errors = inspect_fixture[:errors]
      assert errors.any? { |error| error.start_with?("AM ") && error.include?("Duplicate Asset Id") }
      assert errors.any? { |error| error.start_with?("PKL ") && error.include?("Duplicate Asset Id") }
    end
  end

  def test_duplicate_reel_ids_are_local_to_a_composition_not_asset_reference_reuse
    with_inspection_fixture do
      reel = reference("MainPicture", 4) + reference("MainSound", 5)
      write_cpl(reels: [reel, reel])
      write_package
      assert_empty inspect_fixture[:errors]
      path = File.join(@directory, "CPL.xml")
      File.write(path, File.read(path).sub(fixture_uuid(11), fixture_uuid(10)))
      write_package
      assert inspect_fixture[:errors].any? { |error| error.include?("Duplicate Reel Id") }
    end
  end
end
