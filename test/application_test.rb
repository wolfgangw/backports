# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "open3"
require "rbconfig"
require "dcp_inspect"
require "dcp_inspect/application"
require_relative "support/cli_environment"

class ApplicationTest < Minitest::Test
  include CLIEnvironment

  def test_missing_path_returns_documented_status_without_exiting
    stdout = StringIO.new
    stderr = StringIO.new
    application = DcpInspect::Application.new([], stdout: stdout, stderr: stderr)

    assert_equal 2, application.run
    assert_includes stderr.string, "No volume or directory given"
  end

  def test_too_many_paths_returns_documented_status_without_exiting
    stderr = StringIO.new
    application = DcpInspect::Application.new(%w[first second], stdout: StringIO.new, stderr: stderr)

    assert_equal 3, application.run
    assert_includes stderr.string, "Too many arguments"
  end

  def test_interrupt_and_processing_failure_preserve_partial_logfiles
    { 'raise Interrupt, "cancelled"' => 18,
      'raise DcpInspect::Inspection::Error.new("unreadable asset", 9)' => 9,
      'raise "unexpected failure"' => 21 }.each do |failure, expected_status|
      with_cli_environment do |directory, environment|
        logfile = File.join(directory, "report.txt")
        _stdout, stderr, status = run_with_runtime_body(environment, directory, failure, "--logfile", logfile)

        assert_equal expected_status, status.exitstatus, stderr
        assert_includes File.read(logfile), "Reached asset checks"
      end
    end
  end

  def test_interrupt_preserves_append_and_autolog_reports
    with_cli_environment do |directory, environment|
      logfile = File.join(directory, "append.txt")
      File.write(logfile, "Existing report\n")
      environment["DCP_INSPECT_DIR"] = File.join(directory, "autolog")
      _stdout, stderr, status = run_with_runtime_body(environment, directory,
        'raise Interrupt, "cancelled"', "--logfile-append", logfile, "--autolog")

      assert_equal 18, status.exitstatus, stderr
      assert File.read(logfile).start_with?("Existing report\n")
      assert_equal 1, File.read(logfile).scan("Reached asset checks").length
      reports = Dir[File.join(environment["DCP_INSPECT_DIR"], "*")]
      assert_equal 1, reports.length
      assert_includes File.read(reports.first), "Reached asset checks"
    end
  end

  def test_success_does_not_append_the_report_twice
    with_cli_environment do |directory, environment|
      logfile = File.join(directory, "append.txt")
      _stdout, stderr, status = run_with_runtime_body(environment, directory,
        '{ errors: [] }', "--logfile-append", logfile)

      assert_equal 0, status.exitstatus, stderr
      assert_equal 1, File.read(logfile).scan("Reached asset checks").length
    end
  end

  def test_log_write_failure_does_not_hide_the_interrupt
    with_cli_environment do |directory, environment|
      logfile = File.join(directory, "report.txt")
      environment["TEST_LOGFILE"] = logfile
      _stdout, stderr, status = run_with_runtime_body(environment, directory,
        'Dir.mkdir(ENV.fetch("TEST_LOGFILE")); raise Interrupt, "cancelled"', "--logfile", logfile)

      assert_equal 18, status.exitstatus
      assert_includes stderr, "Could not save partial inspection log"
    end
  end

  private

  def run_with_runtime_body(environment, directory, body, *arguments)
    # Exercise real CLI setup and report writing; inject only the interruption
    # point so these regression tests do not require large media fixtures.
    code = <<~RUBY
      require "dcp_inspect"
      require "dcp_inspect/application"
      class DcpInspect::Inspection::Runtime
        def call(path)
          logger.info "Reached asset checks"
          #{body}
        end
      end
      exit DcpInspect::Application.new(ARGV).run
    RUBY
    Open3.capture3(environment, RbConfig.ruby, "-I#{File.join(DcpInspect::ROOT, 'lib')}",
      "-e", code, "--", "--nh", "--na", *arguments, directory)
  end
end
