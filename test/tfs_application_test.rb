# frozen_string_literal: true
require 'minitest/autorun'
require 'pty'
require 'io/console'
require 'timeout'
require_relative 'support/cli_environment'

class TFSApplicationTest < Minitest::Test
  include CLIEnvironment

  def test_fatal_error_survives_alternate_screen_restoration
    with_cli_environment do |directory, environment|
      output = +''
      status = nil
      PTY.spawn(environment, RbConfig.ruby, File.expand_path('../dcp_inspect', __dir__),
                '--nh', '--na', '--tfs', '--dump-result', '/dev/null/impossible.json', directory) do |reader, writer, pid|
        begin
          Timeout.timeout(10) do
            loop { output << reader.readpartial(65536) }
          end
        rescue EOFError, Errno::EIO
          _, status = Process.waitpid2(pid)
        ensure
          unless status
            Process.kill('KILL', pid) rescue nil
            Process.waitpid(pid) rescue nil
          end
        end
      end
      assert_equal 8, status.exitstatus
      assert_includes output, "\e[?1049l"
      remaining = output.split("\e[?1049l").last
      assert_includes remaining, 'impossible.json'
    end
  end
  def test_resize_and_confirmed_quit_during_inspection
    with_cli_environment do |directory, environment|
      script = <<~'CODE'
        require './lib/dcp_inspect'
        require './lib/dcp_inspect/application'
        class DcpInspect::Inspection::Runtime
          def call(path)
            @logger.info('Inspection running')
            sleep 30
            { errors: [] }
          end
        end
        exit DcpInspect::Application.new(ARGV).run
      CODE
      logfile = File.join(directory, 'partial.log')
      status = nil
      PTY.spawn(environment, RbConfig.ruby, '-e', script, '--', '--nh', '--na', '--tfs',
                '--logfile', logfile, directory) do |reader, writer, pid|
        begin
          reader.winsize = [24, 120]
          read_until(reader, 'Tab: panel')
          reader.winsize = [10, 55]
          assert_includes read_until(reader, 'Package Tree (1/3)'), 'Package Tree (1/3)'
          writer.write("\t")
          read_until(reader, 'Compositions (2/3)')
          writer.write("\t")
          read_until(reader, 'Findings (3/3)')
          writer.write('q')
          read_until(reader, 'Quit ongoing inspection?')
          writer.write("n\t")
          read_until(reader, 'Package Tree (1/3)')
          assert_nil Process.waitpid(pid, Process::WNOHANG)
          writer.write('q')
          read_until(reader, 'Quit ongoing inspection?')
          writer.write('y')
          output = +''
          begin
            Timeout.timeout(5) { loop { output << reader.readpartial(65536) } }
          rescue EOFError, Errno::EIO
          end
          _, status = Process.waitpid2(pid)
          assert_equal 18, status.exitstatus
          assert_includes output, "\e[?1049l"
          assert_includes output.split("\e[?1049l").last, 'Shutdown: Interrupt'
          assert_includes File.read(logfile), 'Inspection running'
        ensure
          unless status
            Process.kill('KILL', pid) rescue nil
            Process.waitpid(pid) rescue nil
          end
        end
      end
    end
  end

  private

  def read_until(reader, text)
    output = +''
    Timeout.timeout(5) do
      output << reader.readpartial(65536) until output.include?(text)
    end
    output
  end

end
