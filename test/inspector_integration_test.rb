# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "dcp_inspect"

class InspectorIntegrationTest < Minitest::Test
  def test_quick_inspection_returns_structured_result
    sample = ENV["DCP_INSPECT_TEST_DCP"]
    skip "set DCP_INSPECT_TEST_DCP to run integration coverage" unless sample && File.directory?(sample)

    Tempfile.create("dcp-inspect-report") do |report|
      configuration = DcpInspect::Configuration.quick(verbosity: ["quiet"])
      result = DcpInspect::Inspector.new(configuration: configuration).call(
        sample,
        stdout: report,
        stderr: report
      )

      assert result.ok?, result.errors.join("\n")
      assert result.inspection_run
      assert_operator result.inspection_run.fetch("assetmaps").length, :>=, 1
      assert_operator result.inspection_run.fetch("packing_lists").length, :>=, 1
      assert_operator result.inspection_run.fetch("compositions").length, :>=, 1
    end
  end
end
