# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/inspection_fixture"

class MetadataTimingTest < Minitest::Test
  include InspectionFixture

  def test_picture_edit_rate_and_frame_rate_are_independently_checked
    with_inspection_fixture do
      write_cpl(reels: [reference("MainPicture", 4, "<FrameRate>25 1</FrameRate>") + reference("MainSound", 5)])
      write_package
      assert inspect_fixture[:errors].any? { |message| message.include?("FrameRate") && message.include?("SampleRate") }
      @metadata["picture.mxf"]["EditRate"] = "25/1"
      assert inspect_fixture[:errors].any? { |message| message.include?("MainPicture EditRate") }
    end
  end

  def test_stereoscopic_sample_rate_may_be_double_the_edit_rate
    with_inspection_fixture do
      @metadata["picture.mxf"].merge!("EssenceType" => V::Stereoscopic_pictures, "SampleRate" => "48/1")
      write_cpl(reels: [reference("MainStereoscopicPicture", 4, "<FrameRate>48 1</FrameRate>") + reference("MainSound", 5)])
      write_package
      assert_empty inspect_fixture[:errors]
    end
  end

  def test_equivalent_rational_rates_do_not_mismatch
    with_inspection_fixture do
      write_cpl(reels: [reference("MainPicture", 4, "<FrameRate>48 2</FrameRate>", rate: "24000 1000") + reference("MainSound", 5)])
      write_package
      assert_empty inspect_fixture[:errors]
    end
  end

  def test_huge_container_duration_is_a_finding_not_an_exception
    with_inspection_fixture do
      @metadata["picture.mxf"]["ContainerDuration"] = "2147483647"
      result = inspect_fixture
      assert result[:errors].any? { |message| message.include?("does not match ContainerDuration 2147483647") }
      assert_equal 1, result[:inspection_run].compositions.length
    end
  end

  def test_absent_duration_defaults_to_intrinsic_minus_entry
    with_inspection_fixture do
      write_cpl(reels: [reference("MainPicture", 4, duration: nil, entry: "24") + reference("MainSound", 5, duration: nil, entry: "24")])
      write_package
      result = inspect_fixture
      assert_empty result[:errors]
      assert_includes result[:inspection_run].compositions.values.first.summary, "00:00:09:00"
    end
  end

  def test_invalid_rates_do_not_abort_remaining_assets_or_reels
    ["0 1", "24 0", "abc 1", "24"].each do |rate|
      with_inspection_fixture do
        valid = reference("MainPicture", 4) + reference("MainSound", 5)
        write_cpl(reels: [reference("MainPicture", 4, rate: rate) + reference("MainSound", 5), valid])
        write_package
        result = inspect_fixture
        assert result[:errors].any? { |message| message.include?("invalid EditRate") }, rate
        assert_equal 2, result[:inspection_run].compositions.values.first.reels.size
        assert_includes result[:inspection_run].compositions.values.first.summary, "Duration does not compute"
      end
    end
  end

  def test_rate_changes_report_reel_evidence_and_sum_seconds_correctly
    with_inspection_fixture do
      valid = reference("MainPicture", 4) + reference("MainSound", 5)
      other = reference("MainPicture", 4, rate: "25 1") + reference("MainSound", 5, rate: "25 1")
      write_cpl(reels: [valid, other])
      write_package
      result = inspect_fixture
      assert result[:errors].any? { |message| message.include?("EditRate mismatch across reels") }
      refute result[:errors].any? { |message| message.include?("FPS cannot be zero") }
      assert_includes result[:inspection_run].compositions.values.first.summary, "19.600 s"
    end
  end

  def test_mpeg2_does_not_require_jpeg2000_decomposition_metadata
    with_inspection_fixture do
      @metadata["picture.mxf"]["EssenceType"] = V::Mpeg2
      @metadata["picture.mxf"].delete("DecompositionLevels")
      assert_empty inspect_fixture[:errors]
    end
  end
end
