# frozen_string_literal: true

require "rake/testtask"
require "digest"

Rake::TestTask.new do |task|
  task.libs << "lib"
  task.pattern = "test/**/*_test.rb"
end

task default: :test

namespace :xsd do
  manifest = File.expand_path("xsd/MANIFEST.sha256", __dir__)
  files = lambda do
    Dir[File.expand_path("xsd/*", __dir__)].select do |path|
      File.file?(path) && File.basename(path) != "MANIFEST.sha256"
    end.sort
  end

  desc "Regenerate the authoritative XSD manifest"
  task :manifest do
    contents = files.call.map do |path|
      "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}"
    end.join("\n") + "\n"
    File.write(manifest, contents)
    puts "Updated #{manifest}"
  end

  desc "Verify the authoritative XSD store and manifest"
  task :check do
    expected = File.foreach(manifest).to_h do |line|
      digest, filename = line.split
      [filename, digest]
    end
    actual = files.call.to_h { |path| [File.basename(path), path] }
    abort "XSD manifest file list does not match the store" unless expected.keys.sort == actual.keys.sort

    expected.each do |filename, digest|
      abort "XSD mismatch for #{filename}" unless Digest::SHA256.file(actual.fetch(filename)).hexdigest == digest
    end
    puts "Authoritative XSD store matches #{manifest}"
  end
end
