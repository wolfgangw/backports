# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "dcp_inspect"

class ConfigurationTest < Minitest::Test
  def test_quick_profile_disables_expensive_checks
    configuration = DcpInspect::Configuration.quick(verbosity: ["quiet"])

    refute configuration.check_hashes
    refute configuration.audio_analysis
    assert_includes configuration.cli_arguments, "--no-hash"
    assert_includes configuration.cli_arguments, "--no-audio-analysis"
  end

  def test_rejects_unknown_verbosity
    assert_raises(ArgumentError) do
      DcpInspect::Configuration.new(verbosity: ["made-up"])
    end
  end

  def test_inspector_accepts_an_in_process_engine_boundary
    received = nil
    engine = Object.new
    engine.define_singleton_method(:call) do |path, configuration:, stdout:, stderr:|
      received = [path, configuration, stdout, stderr]
      DcpInspect::Result.new(status: 0, payload: { "inspection_run" => {} })
    end
    configuration = DcpInspect::Configuration.quick
    inspector = DcpInspect::Inspector.new(configuration: configuration, engine: engine)

    result = inspector.call("/dcp", stdout: :stdout, stderr: :stderr)

    assert result.ok?
    assert_equal ["/dcp", configuration, :stdout, :stderr], received
  end

  def test_inspector_uses_native_engine_by_default
    assert_instance_of DcpInspect::Engine::Native, DcpInspect::Inspector.new.engine
  end

  def test_native_engine_writes_requested_model_dump
    runtime = Object.new
    runtime.define_singleton_method(:call) do |_path|
      { errors: [], hints: [], siginfo: [], info: [], inspection_run: DcpInspect::Model::InspectionRun.new('/dcp') }
    end
    runtime_class = Class.new do
      define_singleton_method(:new) { |**_arguments| runtime }
    end

    Tempfile.create('dcp-inspect-model') do |file|
      configuration = DcpInspect::Configuration.quick(verbosity: ["quiet"], dump_model: file.path)
      result = DcpInspect::Inspector.new(
        configuration: configuration,
        engine: DcpInspect::Engine::Native.new(runtime_class: runtime_class)
      ).call('/dcp')

      assert result.ok?
      assert_equal '/dcp', JSON.parse(File.read(file.path)).fetch('root_path')
    end
  end
end
