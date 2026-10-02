# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "dcp_inspect"

class FilesystemWalkerTest < Minitest::Test
  EXACT_ASSETMAP_NAMES = ["ASSETMAP", "ASSETMAP.xml"].freeze
  NON_CANDIDATE_NAMES = [
    "assetmap",
    "assetmap.xml",
    "ASSETMAP.XML",
    "ASSETMAP.xml.bak",
    "ASSETMAPXxml",
    "ASSETMAP~"
  ].freeze

  def test_assetmap_candidates_are_precisely_the_two_allowed_filenames
    with_discovery_tree do |root|
      walkers.each do |walker|
        assert_equal [".hidden/ASSETMAP.xml", "nested/ASSETMAP", "nested/ASSETMAP.xml"],
                     walker.assetmap_candidates(root),
                     walker.backend.to_s
      end
    end
  end

  def test_fd_and_ruby_backends_have_file_parity_for_a_symlink_root
    skip "fd/fdfind is not installed" unless DcpInspect::FilesystemWalker.find_fd

    with_discovery_tree do |root|
      fd_files = DcpInspect::FilesystemWalker.new(backend: :fd).files(root)
      ruby_files = DcpInspect::FilesystemWalker.new(backend: :ruby).files(root)

      assert_equal fd_files, ruby_files
      assert_includes fd_files, File.join(root, "line\nbreak.mxf")
      refute_includes fd_files, File.join(root, "symlink-file.mxf")
      refute fd_files.any? { |path| path.include?("symlink-directory") }
    end
  end

  def test_auto_backend_prefers_fd
    skip "fd/fdfind is not installed" unless DcpInspect::FilesystemWalker.find_fd

    assert_equal :fd, DcpInspect::FilesystemWalker.new.backend
  end

  def test_ruby_backend_rejects_a_missing_root
    walker = DcpInspect::FilesystemWalker.new(backend: :ruby)

    assert_raises(DcpInspect::FilesystemWalker::TraversalError) do
      walker.files(File.join(Dir.tmpdir, "dcp-inspect-missing-#{Process.pid}"))
    end
  end

  def test_ruby_backend_reports_and_skips_an_unreadable_directory
    skip "permission behavior cannot be tested as root" if Process.uid.zero?

    Dir.mktmpdir("dcp-inspect-permissions-") do |root|
      unreadable = File.join(root, "unreadable")
      FileUtils.mkdir_p(unreadable)
      File.write(File.join(unreadable, "hidden.mxf"), "")
      FileUtils.chmod(0o000, unreadable)

      walker = DcpInspect::FilesystemWalker.new(backend: :ruby)
      refute_includes walker.files(root), File.join(unreadable, "hidden.mxf")
      refute_empty walker.warnings
    ensure
      FileUtils.chmod(0o700, unreadable) if unreadable && File.exist?(unreadable)
    end
  end

  private

  def walkers
    result = [DcpInspect::FilesystemWalker.new(backend: :ruby)]
    result << DcpInspect::FilesystemWalker.new(backend: :fd) if DcpInspect::FilesystemWalker.find_fd
    result
  end

  def with_discovery_tree
    Dir.mktmpdir("dcp-inspect-walker-") do |parent|
      physical_root = File.join(parent, "physical")
      logical_root = File.join(parent, "logical root;not-shell")
      FileUtils.mkdir_p(File.join(physical_root, "nested"))
      FileUtils.mkdir_p(File.join(physical_root, ".hidden"))
      FileUtils.mkdir_p(File.join(physical_root, "directory-target"))

      EXACT_ASSETMAP_NAMES.each { |name| File.write(File.join(physical_root, "nested", name), "") }
      NON_CANDIDATE_NAMES.each { |name| File.write(File.join(physical_root, "nested", name), "") }
      File.write(File.join(physical_root, ".hidden", "ASSETMAP.xml"), "")
      File.write(File.join(physical_root, ".ignore"), "ignored.mxf\n")
      File.write(File.join(physical_root, "ignored.mxf"), "")
      File.write(File.join(physical_root, "line\nbreak.mxf"), "")
      File.write(File.join(physical_root, "regular.mxf"), "")
      File.write(File.join(physical_root, "directory-target", "inside.mxf"), "")
      File.symlink(File.join(physical_root, "regular.mxf"), File.join(physical_root, "symlink-file.mxf"))
      File.symlink(File.join(physical_root, "directory-target"), File.join(physical_root, "symlink-directory"))
      File.symlink(physical_root, logical_root)

      yield logical_root
    end
  end
end
