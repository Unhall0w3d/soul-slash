#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative "compare-continuity-placement-a23"

runner = ContinuityPlacementComparisonA23.new
ContinuityPlacementComparisonA23::MODELS.each do |id|
  original = ContinuityModelComparisonA23.new.candidate_args(id, "/synthetic.gguf")
  expected = original.reject { |arg| arg == "--cpu-moe" }
  expected[expected.index("--flash-attn") + 1] = "auto"
  raise "Placement configuration differs beyond declared changes" unless runner.candidate_args(id, "/synthetic.gguf") == expected
end
begin
  runner.candidate_args("qwen8", "/synthetic.gguf")
  raise "Baseline accepted as placement candidate"
rescue RuntimeError => error
  raise unless error.message == "Unapproved placement candidate"
end
%i[generate evaluate_model with_restoration restore start_candidate stop_candidate check_idle validate_resources].each do |method|
  raise "Safety or scoring contract overridden: #{method}" unless runner.method(method).owner == ContinuityModelComparisonA23
end
raise "Request count changed" unless ContinuityModelComparisonA23::Cases.groups.sum { |group| group.fetch("cases").length } == 15
puts "PASS 12 placement-contract checks; inherited lifecycle exercised by verify-continuity-model-runner-a23.rb"
