#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require_relative "../lib/dcp_inspect"

root = ARGV.fetch(0) do
  abort "Usage: ruby benchmark/filesystem_walker.rb DISCOVERY_ROOT"
end
root = File.expand_path(root)
abort "fd/fdfind is required for the comparison" unless DcpInspect::FilesystemWalker.find_fd

results = {}
%i[fd ruby].each do |backend|
  walker = DcpInspect::FilesystemWalker.new(backend: backend)
  elapsed = Benchmark.realtime { results[backend] = walker.files(root) }
  warn "#{backend}: #{format('%.3f', elapsed)}s, #{results[backend].length} files"
end

unless results[:fd] == results[:ruby]
  fd_only = results[:fd] - results[:ruby]
  ruby_only = results[:ruby] - results[:fd]
  warn "Traversal mismatch: fd-only=#{fd_only.first(10).inspect} ruby-only=#{ruby_only.first(10).inspect}"
  exit 1
end

puts "Parity confirmed for #{results[:fd].length} files beneath #{root}"
