#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/soul_core/continuity_lab/verified_selection"
require "timeout"

if $PROGRAM_NAME == __FILE__
  lab = SoulCore::ContinuityLab
  helper = lab::VerifiedSelection
  reason = nil
  begin
    raise ArgumentError, "unexpected_arguments" unless ARGV.empty?
    # Bounded even when a caller leaves a pipe open without sending EOF.
    raw = Timeout.timeout(5) { STDIN.read(helper::MAX_INPUT_BYTES + 1) }
    raise ArgumentError, "input_too_large" if raw.bytesize > helper::MAX_INPUT_BYTES
    raw.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "invalid_utf8" unless raw.valid_encoding?
    payload = lab.parse(raw)
    unless payload.is_a?(Hash) && (%w[source request] - payload.keys).empty? &&
           (payload.keys - %w[source request proposal explanation]).empty?
      raise ArgumentError, "invalid_input_schema"
    end
    result = helper.present(source: payload["source"], request: payload["request"],
      proposal: payload["proposal"], explanation: payload["explanation"])
  rescue Timeout::Error
    reason = "input_timeout"
  rescue JSON::ParserError, JSON::NestingError, lab::ValidationError
    reason = "invalid_json"
  rescue ArgumentError => error
    reason = error.message
  end
  result = { "verified_result" => helper.refused(reason), "generated_explanation" => nil } if reason
  puts lab.encode(result)
  exit(result.fetch("verified_result").fetch("state") == "complete" ? 0 : 2)
end
