# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/dcp_inspect/inspection/log_writer'

class LogWriterTest < Minitest::Test
  Writer = DcpInspect::Inspection::LogWriter

  def test_long_unicode_name_recovers_in_same_directory_without_clobbering
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'é' * 200 + '.txt')
      fallback = Writer.compact_path(path)
      File.write(fallback, 'existing')
      result = Writer.write(path, 'new', overwrite: true)
      assert result[:recovered]
      assert_equal dir, File.dirname(result[:path])
      assert File.basename(result[:path]).valid_encoding?
      assert_equal 'existing', File.read(fallback)
      assert_equal 'new', File.read(result[:path])
      refute_equal fallback, result[:path]
    end
  end

  def test_short_names_respect_overwrite_and_append_and_long_append_is_stable
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'report.txt')
      Writer.write(path, 'one')
      assert_raises(Errno::EEXIST) { Writer.write(path, 'two') }
      Writer.write(path, 'two', overwrite: true)
      assert_equal 'two', File.read(path)
      long = File.join(dir, 'a' * 300)
      first = Writer.write(long, 'one', append: true)
      second = Writer.write(long, 'two', append: true)
      assert_equal first[:path], second[:path]
      assert_equal 'onetwo', File.read(first[:path])
    end
  end

  def test_bad_directories_and_non_length_errors_are_not_redirected
    Dir.mktmpdir do |dir|
      assert_raises(Errno::ENOENT) { Writer.write(File.join(dir, 'absent', 'report'), 'test') }
      assert_raises(SystemCallError) { Writer.write(dir, 'test', overwrite: true) }
      assert_empty Dir.children(dir)
    end
  end
end
