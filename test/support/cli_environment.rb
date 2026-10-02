# frozen_string_literal: true

require "tmpdir"
require "rbconfig"

module CLIEnvironment
  private

  def with_cli_environment
    Dir.mktmpdir("dcp-application-test-") do |directory|
      bindir = File.join(directory, "bin")
      Dir.mkdir(bindir)
      tool = File.join(bindir, "asdcp-info")
      File.write(tool, "#!#{RbConfig.ruby}\nputs 'asdcplib 2.13.2'\n")
      File.chmod(0o755, tool)
      yield directory, {
        "PATH" => "#{bindir}#{File::PATH_SEPARATOR}#{ENV['PATH']}",
        "DCP_INSPECT_AUTOLOG" => nil,
        "DCP_INSPECT_AUTOLOG_NAME_IS_BASENAME" => nil,
        "DCP_INSPECT_DIR" => nil
      }
    end
  end
end
