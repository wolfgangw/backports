# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "rbconfig"
require "timeout"
require "dcp_inspect/inspection/audio_analysis"

class AudioAnalysisTest < Minitest::Test
  Analysis = DcpInspect::Inspection::AudioAnalysis

  def test_drains_the_fifo_and_reports_progress
    with_helpers do |fifo, producer, consumer|
      progress = []
      output = run_helpers(
        producer + ['File.open(ARGV[0], "wb") { |io| io.write("audio" * 100_000) }'],
        consumer + ['File.binread(ARGV[0]); puts "out_time_us=1000000"; warn "analysis summary"'],
        fifo
      ) { |line| progress << line }

      assert_equal ["out_time_us=1000000\n"], progress
      assert_equal "analysis summary\n", output
    end
  end

  def test_unwrap_failure_does_not_leave_ffmpeg_waiting_for_the_fifo
    with_helpers do |fifo, producer, consumer|
      error = assert_raises(Analysis::Error) do
        run_helpers(producer + ['warn "invalid MXF"; exit 7'], consumer + ['File.binread(ARGV[0])'], fifo)
      end

      assert_match(/asdcp-unwrap failed \(exit 7\)/, error.message)
      assert_includes error.message, "invalid MXF"
    end
  end

  def test_ffmpeg_failure_after_consuming_input_is_not_success
    with_helpers do |fifo, producer, consumer|
      error = assert_raises(Analysis::Error) do
        run_helpers(
          producer + ['File.write(ARGV[0], "audio")'],
          consumer + ['File.binread(ARGV[0]); warn "unsupported filter"; exit 1'], fifo
        )
      end

      assert_includes error.message, "ffmpeg failed (exit 1)"
      assert_includes error.message, "unsupported filter"
    end
  end

  def test_early_ffmpeg_failure_kills_a_producer_that_ignores_term
    with_helpers do |fifo, producer, consumer|
      # The producer marks itself ready only after installing the signal handler.
      producer << 'Signal.trap("TERM", "IGNORE"); File.write(ARGV[1] + ".ready", ""); File.open(ARGV[0], "wb") { sleep 30 }'
      consumer << 'sleep 0.01 until File.exist?(ARGV[2] + ".ready"); warn "cannot start decoder"; exit 2'
      error = assert_raises(Analysis::Error) { run_helpers(producer, consumer, fifo) }

      assert_includes error.message, "ffmpeg failed (exit 2)"
    end
  end

  def test_interrupt_reaps_both_helpers
    with_helpers do |fifo, producer, consumer|
      producer << 'File.open(ARGV[0], "wb") { sleep 30 }'
      consumer << 'File.open(ARGV[0], "rb") { STDOUT.sync = true; puts "out_time_us=0"; sleep 30 }'
      assert_raises(Interrupt) do
        run_helpers(producer, consumer, fifo) { raise Interrupt, "cancelled" }
      end
    end
  end

  def test_ffmpeg_launch_failure_cleans_up_the_producer
    with_helpers do |fifo, producer, _consumer|
      producer << 'File.open(ARGV[0], "wb") { sleep 30 }'
      error = assert_raises(Analysis::Error) do
        Timeout.timeout(5) do
          Analysis.run(
            [RbConfig.ruby, "-e", producer.join, fifo, "#{fifo}.producer.pid"],
            [File.join(File.dirname(fifo), "missing-ffmpeg")]
          )
        end
      end

      assert_includes error.message, "Could not run audio analysis"
    end
  end

  private

  def with_helpers
    Dir.mktmpdir("dcp-audio-test-") do |directory|
      fifo = File.join(directory, "audio.wav")
      system("mkfifo", fifo, exception: true)
      preamble = 'File.write(ARGV[1], Process.pid.to_s); '
      yield fifo, [preamble], [preamble]
    ensure
      Dir[File.join(directory, "*.pid")].each do |file|
        pid = File.read(file).to_i
        assert_raises(Errno::ECHILD, "helper #{pid} was not reaped") { Process.waitpid(pid, Process::WNOHANG) }
        assert_raises(Errno::ESRCH, "helper #{pid} is still alive") { Process.kill(0, pid) }
      end
    end
  end

  def run_helpers(producer, consumer, fifo, &progress)
    producer_pid = "#{fifo}.producer.pid"
    consumer_pid = "#{fifo}.consumer.pid"
    Timeout.timeout(5) do
      Analysis.run(
        [RbConfig.ruby, "-e", producer.join, fifo, producer_pid],
        [RbConfig.ruby, "-e", consumer.join, fifo, consumer_pid, producer_pid],
        &progress
      )
    end
  end
end
