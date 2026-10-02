# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class LibraryLoadingTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_require_is_lazy_and_does_not_pollute_object
    code = <<~'RUBY'
      require "dcp_inspect"
      forbidden = %i[DLogger DC_Signature_Verification InspectionRun Options].select do |name|
        Object.const_defined?(name, false)
      end
      abort "legacy constants loaded: #{forbidden.inspect}" unless forbidden.empty?
      abort "runtime loaded eagerly" if defined?(DcpInspect::Inspection::Runtime)
      puts DcpInspect::Model::InspectionRun.name
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-e", code, chdir: ROOT)

    assert status.success?, stderr
    assert_equal "DcpInspect::Model::InspectionRun\n", stdout
  end
end
