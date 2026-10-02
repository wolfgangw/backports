# frozen_string_literal: true
require 'minitest/autorun'
require 'dcp_inspect'

class TFSRelatedFindingsTest < Minitest::Test
  def setup
    @ui = DcpInspect::UI::TFSRenderer.new(DcpInspect::CLI::Options.parse([]))
    @ui.instance_variable_set(:@color_enabled, false)
    @ui.define_singleton_method(:console_size) { @test_size || [30, 120] }
    @run = DcpInspect::Model::InspectionRun.new('/dcp')
    @am = @run.assetmap('am-one', base: 'package-one', path: 'package-one/ASSETMAP')
    @pkl = @run.packing_list('pkl-one', assetmap_id: @am.id)
    @cpl = @run.composition('cpl-one', packing_list_id: @pkl.id)
    @picture = @run.reel_asset(@cpl.id, 2, 'picture-one', kind: 'MainPicture')
    @run.add_check(@picture.asset, :hash, :error, 'Digest mismatch without an ID')
    @ui.attach_run(@run)
    @ui.track_findings(errors: ['CPL cpl-other: unrelated failure', 'CPL cpl-one: Reel 2: image rate invalid'],
                       hints: ['Asset picture-one: related hint', 'CPL cpl-one: Reel 3: unrelated reel hint'],
                       siginfo: ['CPL cpl-one: signer details'])
  end

  def select(subject, panel = :compositions)
    @ui.instance_variable_set(:@focused_panel_index, panel == :compositions ? 1 : 0)
    @ui.instance_variable_get(:@panel_row_actions)[panel] = [{subject: subject}]
    @ui.instance_variable_get(:@panel_selected_rows)[panel] = 0
    @ui.send(:findings_lines)
  end

  def related(lines)
    lines.take_while { |line| line != 'Other findings' }.join("\n")
  end

  def test_composition_includes_asset_findings_and_certificate_information
    lines = select(@cpl)
    assert_includes related(lines), 'related hint'
    assert_includes related(lines), 'signer details'
    assert_includes related(lines), 'Digest mismatch without an ID'
    refute_includes related(lines), 'unrelated failure'
    assert_includes lines.join, 'unrelated failure'
  end

  def test_reel_and_asset_include_reel_number_diagnostics_but_not_other_reels
    [@picture.reel, @picture, @picture.asset].each do |subject|
      text = related(select(subject))
      assert_includes text, 'image rate invalid'
      assert_includes text, 'related hint'
      refute_includes text, 'unrelated reel hint'
      refute_includes text, 'signer details'
    end
  end

  def test_package_and_packing_list_include_descendant_findings
    [@run.packages.first, @am, @pkl].each do |subject|
      text = related(select(subject, :package_tree))
      assert_includes text, 'image rate invalid'
      assert_includes text, 'related hint'
      refute_includes text, 'unrelated failure'
    end
  end

  def test_selection_resets_scroll_only_when_subject_changes_and_survives_focus_change
    select(@cpl)
    offsets = @ui.instance_variable_get(:@panel_scroll_offsets)
    offsets[:findings] = 5
    select(@cpl)
    assert_equal 5, offsets[:findings]
    select(@picture)
    assert_equal 0, offsets[:findings]
    @ui.instance_variable_set(:@focused_panel_index, 2)
    offsets[:findings] = 3
    assert_includes related(@ui.send(:findings_lines)), 'MainPicture'
    assert_equal 3, offsets[:findings]
  end

  def test_compact_navigation_remembers_selection_when_switching_to_findings
    @ui.instance_variable_set(:@test_size, [10, 55])
    @ui.instance_variable_set(:@focused_panel_index, 1)
    @ui.build_frame
    @ui.send(:focus_next_panel)
    frame = @ui.build_frame
    assert_includes frame.join, 'Related to CompositionPlaylist cpl-one'
  end

  def test_empty_selection_is_explicit_and_retains_other_findings
    text = select(@run.composition('cpl-clean')).join("\n")
    assert_includes text, 'No findings recorded for this selection'
    assert_includes text, 'unrelated failure'
  end
end
