# frozen_string_literal: true
require 'minitest/autorun'
require 'rbconfig'
require_relative '../lib/dcp_inspect/inspection/timed_text_extraction'

class TimedTextExtractionTest < Minitest::Test
  Extraction = DcpInspect::Inspection::TimedTextExtraction

  def test_explicit_output_paths_and_cleanup
    extracted = nil
    command = [RbConfig.ruby, '-e', 'File.write(ARGV.last, "<SubtitleReel/>")']
    Extraction.open('/tmp/input with spaces.mxf', command: command) do |xml, directory|
      extracted = directory
      assert_equal '<SubtitleReel/>', File.read(xml)
    end
    refute File.exist?(extracted)
  end

  def test_failure_keeps_diagnostic_and_cleans_partial_output
    Dir.mktmpdir do |dir|
      record = File.join(dir, 'record')
      command = [RbConfig.ruby, '-e', 'File.write(ARGV.shift, ARGV.last); File.write(ARGV.last, "partial"); STDERR.puts "bad MXF"; exit 7', record]
      error = assert_raises(Extraction::Error) { Extraction.open('/tmp/input.mxf', command: command) { flunk } }
      assert_includes error.message, 'bad MXF'
      refute File.exist?(File.dirname(File.read(record)))
    end
  end

  def test_missing_tool_is_distinct_from_broken_asset
    assert_raises(Extraction::Unavailable) { Extraction.open('/tmp/input.mxf', command: ['/no/such/asdcp-unwrap']) { flunk } }
  end

  def test_timeout_reaps_child_and_removes_temporary_files
    Dir.mktmpdir do |dir|
      record = File.join(dir, 'record')
      command = [RbConfig.ruby, '-e', 'File.write(ARGV.shift, "#{Process.pid}\n#{ARGV.last}"); trap("TERM") {}; sleep 30', record]
      assert_raises(Extraction::Error) { Extraction.open('/tmp/input.mxf', command: command, timeout: 0.2) { flunk } }
      pid, path = File.read(record).lines.map(&:strip)
      assert_raises(Errno::ESRCH) { Process.kill(0, pid.to_i) }
      refute File.exist?(File.dirname(path))
    end
  end

  def test_interruption_inside_inspection_removes_extracted_files
    extracted = nil
    command = [RbConfig.ruby, '-e', 'File.write(ARGV.last, "<SubtitleReel/>")']
    assert_raises(Interrupt) do
      Extraction.open('/tmp/input.mxf', command: command) do |_xml, directory|
        extracted = directory
        raise Interrupt
      end
    end
    refute File.exist?(extracted)
  end

  def test_interruption_during_extraction_reaps_child
    Dir.mktmpdir do |dir|
      record = File.join(dir, 'record')
      command = [RbConfig.ruby, '-e', 'File.write(ARGV.shift, "#{Process.pid}\n#{ARGV.last}"); sleep 30', record]
      worker = Thread.new do
        begin
          Extraction.open('/tmp/input.mxf', command: command, timeout: 5) { flunk }
        rescue Interrupt
          :interrupted
        end
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
      until File.exist?(record)
        raise 'fake unwrap did not start' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.01
      end
      worker.raise(Interrupt)
      assert_equal :interrupted, worker.value
      pid, path = File.read(record).lines.map(&:strip)
      assert_raises(Errno::ESRCH) { Process.kill(0, pid.to_i) }
      refute File.exist?(File.dirname(path))
    ensure
      worker&.raise(Interrupt) if worker&.alive?
      worker&.join
    end
  end
end
