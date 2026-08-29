#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "rbconfig"

require_relative "../lib/soul_core/bounded_command_runner"

errors = []
check = lambda do |description, condition|
  puts "#{condition ? 'PASS' : 'FAIL'}: #{description}"
  errors << description unless condition
end

runner = SoulCore::BoundedCommandRunner.new

prefix = runner.run(RbConfig.ruby, "-e", 'print "abcdefghijk"', max_output_bytes: 8)
check.call("default prefix capture remains unchanged", prefix.success? && prefix.stdout == "abcdefgh" && prefix.truncated)

# The child emits more than 2 MiB in fixed-size JSON records, then a final
# record without a newline. The tail must remain parseable at every boundary.
fixture = <<~'RUBY'
  require "json"
  2_500.times { |id| puts(JSON.generate("id" => id, "payload" => "x" * 900)) }
  print JSON.generate("id" => "eof", "payload" => "λ" * 100)
RUBY
tail_limit = 8 * 1024
tail = runner.run(RbConfig.ruby, "-e", fixture, max_output_bytes: tail_limit, capture_mode: :complete_line_tail)
tail_records = tail.stdout.lines
parsed_records = tail_records.filter_map do |line|
  JSON.parse(line)
rescue JSON::ParserError
  nil
end
tail_ids = parsed_records.map { |record| record.fetch("id") }
check.call("large NDJSON tail stays within the byte bound", tail.success? && tail.stdout.bytesize <= tail_limit)
check.call("large NDJSON tail reports discarded earlier records", tail.truncated && tail_ids.length < 2_501)
check.call("large NDJSON tail contains only complete valid JSON records", parsed_records.length == tail_records.length && tail.stdout.valid_encoding?)
check.call("large NDJSON tail retains the final non-newline record", tail_ids.last == "eof" && !tail.stdout.end_with?("\n"))

oversized = runner.run(
  RbConfig.ruby,
  "-rjson",
  "-e",
  'print("λ" * 200); print "\n"; print({"id" => "kept"}.to_json)',
  max_output_bytes: 64,
  capture_mode: :complete_line_tail
)
oversized_records = oversized.stdout.lines.map { |line| JSON.parse(line) }
check.call("oversized lines are dropped as whole records", oversized.truncated && oversized_records == [{ "id" => "kept" }])
check.call("oversized-line handling never emits partial UTF-8", oversized.stdout.valid_encoding? && oversized.stdout.bytesize <= 64)

invalid_mode = runner.run(RbConfig.ruby, "-e", "print 'must not run'", capture_mode: :untrusted)
check.call("capture mode is closed and rejects unknown values", invalid_mode.status == "failed" && invalid_mode.stderr.include?("ArgumentError"))

if errors.empty?
  puts "PASS: 8 checks"
  exit 0
end

warn "FAIL: #{errors.length} checks failed: #{errors.join(', ')}"
exit 1
