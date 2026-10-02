# frozen_string_literal: true

require "minitest/autorun"
require "dcp_inspect"

class TFSFindingsTest < Minitest::Test
  def setup
    @renderer = DcpInspect::UI::TFSRenderer.new(DcpInspect::CLI::Options.parse([]))
    @renderer.instance_variable_set(:@color_enabled, false)
    @renderer.define_singleton_method(:console_size) { [30, 100] }
    @run = DcpInspect::Model::InspectionRun.new("/dcp")
    @renderer.attach_run(@run)
  end

  def test_certificate_messages_do_not_evict_errors_or_hints
    336.times { |i| @renderer.diagnostic(:error, "Error #{i}") }
    359.times { |i| @renderer.diagnostic(:hint, "Hint #{i}") }
    542.times { |i| @renderer.diagnostic(:siginfo, "Certificate #{i}") }

    assert_equal "336 errors  359 hints  542 siginfo", @renderer.send(:findings_status_line)
    assert_equal 1237, @renderer.send(:diagnostic_entries).size
  end

  def test_live_counts_come_from_findings_not_repeated_log_messages
    errors = []
    hints = []
    siginfo = []
    @renderer.track_findings(errors: errors, hints: hints, siginfo: siginfo)
    errors << "Audio analysis failed"
    2.times { @renderer.diagnostic(:error, "Error: Audio analysis failed") }
    hints << "External asset required"
    542.times { |i| siginfo << "Certificate #{i}" }

    assert_equal "1 error  1 hint  542 siginfo", @renderer.send(:findings_status_line)
    assert_equal 1, @renderer.send(:diagnostic_entries).count { |entry| entry[:level] == :error }
  end

  def test_unlogged_findings_are_visible_even_with_quiet_output
    renderer = DcpInspect::UI::TFSRenderer.new(DcpInspect::CLI::Options.parse(%w[--verbosity quiet]))
    renderer.instance_variable_set(:@color_enabled, false)
    renderer.attach_run(@run)
    renderer.track_findings(errors: ["Unreported failure"], hints: [], siginfo: [])

    assert_equal 1, renderer.send(:diagnostic_count, :error)
    assert renderer.send(:findings_lines).any? { |line| line.include?("Unreported failure") }
  end
  def test_composition_badges_distinguish_pending_external_and_broken
    cpl = DcpInspect::Model::CompositionPlaylist.new(@run, "cpl")
    @run.add_check(cpl, :schema, :ok)
    { nil => '···', 'Composition complete ✅' => 'OK ',
      'Composition incomplete ❌: Broken assets' => 'ERR',
      'Composition incomplete: Supplemental/VF/External' => 'EXT',
      'Composition warning: Missing sound' => 'WRN' }.each do |description, badge|
      cpl.complete = description
      assert_equal badge, @renderer.send(:status_token, cpl)
    end
    cpl.complete = 'Composition complete ✅'
    @run.add_check(cpl, :composition, :error, 'Invalid edit rate')
    assert_equal 'ERR', @renderer.send(:status_token, cpl)
  end

  def test_all_findings_and_full_long_messages_are_scrollable
    errors = 20.times.map { |i| "Unique failure #{i}: " + ('long/path/' * 30) + "END#{i}" }
    @renderer.track_findings(errors: errors, hints: [], siginfo: ['Certificate details'])
    lines = @renderer.send(:findings_lines, 38)
    joined = lines.join
    errors.each { |message| assert_includes joined, message }
    assert_includes joined, 'Certificate details'
    assert lines.all? { |line| @renderer.send(:display_width, line) <= 38 }
    # The bottom row must remain readable even when earlier rows are hidden.
    fitted = @renderer.send(:fit_lines, lines, 38, 5, lines.size - 5, false)
    assert_equal lines.last, fitted.last.rstrip
  end

  def test_small_terminal_can_reach_every_panel
    [3, 6, 12, 18].each do |height|
      @renderer.define_singleton_method(:console_size) { [height, 45] }
      [:package_tree, :compositions, :findings].each_with_index do |key, index|
        @renderer.instance_variable_set(:@focused_panel_index, index)
        frame = @renderer.build_frame
        assert_equal height, frame.size
        assert_includes frame.first, "(#{index + 1}/3)"
        assert frame.all? { |line| @renderer.send(:display_width, line) <= 44 }
      end
    end
  end

  def test_quit_confirmation_defaults_to_continue_and_is_not_needed_after_finish
    @renderer.send(:handle_keypress, 'q')
    assert @renderer.instance_variable_get(:@confirm_quit)
    popup = @renderer.send(:quit_confirmation_frame, @renderer.build_frame)
    assert popup.any? { |line| line.include?('Quit ongoing inspection?') }
    @renderer.send(:handle_keypress, "\r")
    refute @renderer.instance_variable_get(:@confirm_quit)
    refute @renderer.instance_variable_get(:@quit_requested)
    @renderer.send(:handle_keypress, 'q')
    @renderer.finish(0)
    refute @renderer.instance_variable_get(:@confirm_quit)
    @renderer.send(:handle_keypress, 'q')
    assert @renderer.instance_variable_get(:@quit_requested)
  end

end
