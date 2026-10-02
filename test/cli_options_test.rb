# frozen_string_literal: true

require "minitest/autorun"
require "dcp_inspect"

class CliOptionsTest < Minitest::Test
  def test_parses_without_loading_the_inspection_runtime
    arguments = %w[--nh --na --verbosity quiet /dcp]
    options = DcpInspect::CLI::Options.parse(arguments, program_name: "dcp_inspect")

    refute options.check_hashes
    refute options.audio_analysis
    assert_equal ["quiet"], options.verbosity
    assert_equal ["/dcp"], arguments
  end

  def test_defaults_preserve_full_standalone_inspection
    options = DcpInspect::CLI::Options.parse([], program_name: "dcp_inspect")

    assert options.check_hashes
    assert options.audio_analysis
    assert options.schema_validate
  end
end
