# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'
require_relative 'support/media_fixture'

class MediaInspectionTest < Minitest::Test
  include InspectionFixture
  include MediaFixture
  Mxf = DcpInspect::Inspection::MxfEssence

  def setup
    @inspect_media = true
  end

  def picture_track(bad: false)
    frames = [jpeg2000] * 240
    frames[-1] = jpeg2000(block_style: 1) if bad
    File.binwrite(File.join(@directory, 'picture.mxf'), mxf(*frames.map { |frame| klv(Mxf::J2K + "\x01".b, frame) }))
  end

  def test_header_failure_reaches_composition_result_even_without_hashing
    with_inspection_fixture do
      picture_track(bad: true)
      write_package
      result = inspect_fixture
      assert result[:errors].any? { |message| message.include?('codeblocks') && message.include?('240') }
      composition = result[:inspection_run].compositions.values.first
      check = composition.checks.find { |entry| entry.kind == :jpeg2000 }
      assert_equal :error, check.status
      assert_equal 240, check.details[:data][:codestreams]
      assert_equal 'Composition complete ✅', composition.complete
      assert composition.checks.any? { |entry| entry.kind == :composition && entry.status == :error }
    end
  end

  def test_quvis_style_descriptor_corruption_is_a_composition_error
    with_inspection_fixture do
      picture_track
      @metadata['picture.mxf'].merge!('Rsize' => '3', 'Xsize' => '409867776', 'Ysize' => '1',
        'XOsize' => '4102', 'YOsize' => '0', 'XTsize' => '560', 'YTsize' => '0', 'XTOsize' => '409867776', 'YTOsize' => '1')
      write_package
      result = inspect_fixture
      assert result[:errors].any? { |message| message.include?('Xsize="409867776"') && message.include?('Xsize=1998') }
      check = result[:inspection_run].compositions.values.first.checks.find { |entry| entry.kind == :jpeg2000 }
      assert_equal :error, check.status
      assert_empty check.details[:data][:unchecked_descriptor_fields]
      assert_equal :complete, result[:inspection_run].compositions.values.first.completeness_status
    end
  end

  def test_iab_counts_are_exported_as_actual_definitions_not_descriptor_capacity
    with_inspection_fixture do
      picture_track
      File.binwrite(File.join(@directory, 'iab.mxf'), mxf(*Array.new(240) { klv(Mxf::ATMOS + "\x01".b, iab_frame) }))
      @metadata['iab.mxf'] = { 'EssenceType' => V::Atmos, 'Label Set Type' => 'SMPTE', 'EncryptedEssence' => 'No', 'AssetUUID' => fixture_uuid(6), 'EditRate' => '24/1', 'ContainerDuration' => '240', 'MaxObjectCount' => '118' }
      write_cpl(reels: [reference('MainPicture', 4) + reference('MainSound', 5) + reference('AuxData', 6)])
      write_package(assets: [[3, 'CPL.xml', 'text/xml;asdcpKind=CPL'], [4, 'picture.mxf', 'application/x-smpte-mxf;asdcpKind=Picture'], [5, 'sound.mxf', 'application/x-smpte-mxf;asdcpKind=Sound'], [6, 'iab.mxf', 'application/mxf']])
      result = inspect_fixture
      check = result[:inspection_run].compositions.values.first.checks.find { |entry| entry.kind == :iab }
      assert_equal :ok, check.status
      assert_equal({ min: 1, max: 1 }, check.details[:data][:objects])
      assert_equal({ min: 1, max: 1 }, check.details[:data][:beds])
      assert_includes check.message, 'audio payloads and profiles unchecked'
    end
  end

  def test_encrypted_media_is_explicitly_skipped
    with_inspection_fixture do
      @metadata['picture.mxf']['EncryptedEssence'] = 'Yes'
      result = inspect_fixture
      check = result[:inspection_run].compositions.values.first.checks.find { |entry| entry.kind == :jpeg2000 }
      assert_equal :skipped, check.status
      assert_includes check.message, 'without a key'
    end
  end
end
