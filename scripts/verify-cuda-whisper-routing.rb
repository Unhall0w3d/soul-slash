#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/soul_core/cuda_whisper_runtime_handoff"

class CudaRoutingControlFixture
  def initialize(observation)
    @observation = observation
  end

  def status
    { "ok" => true, "data" => @observation }
  end
end

class CudaRoutingSelectionFixture
  attr_accessor :core

  def initialize(core)
    @core = core
  end

  def persisted_selection(profiles:)
    { "active_core_id" => @core }
  end
end

def check(label, condition)
  abort "FAIL: #{label}" unless condition
  puts "PASS: #{label}"
end

Dir.mktmpdir("cuda-whisper-routing-") do |root|
  observation = {
    "profiles" => [{ "id" => "nvidia-fallback", "service_state" => "active" }],
    "active_work_count" => 0, "active_leases" => [],
    "active_profile_count" => 1, "profile_conflict" => false, "idle_certain" => true
  }
  control = CudaRoutingControlFixture.new(observation)
  selection = CudaRoutingSelectionFixture.new("amd-free")
  coordinator = SoulCore::CudaWhisperRuntimeHandoff.new(
    root: root, env: {}, control: control, selection: selection
  )
  check("selected chat Core admits idle NVIDIA handoff",
        coordinator.status_blocker.nil? && coordinator.send(:admissible?, observation))
  selection.core = "free"
  check("Free Core status refuses transcription", coordinator.status_blocker.include?("Free Core"))
  begin
    coordinator.send(:admissible?, observation)
    check("Free Core recheck under lock refuses transcription", false)
  rescue SoulCore::WhisperRuntimeHandoff::Error => error
    check("Free Core recheck under lock refuses transcription", error.message.include?("Free Core"))
  end
  selection.core = "unknown"
  check("unknown selected Core refuses transcription", coordinator.status_blocker.include?("known chat Core"))
  selection.core = "amd-free"
  observation["profile_conflict"] = true
  check("conflicting chat runtime refuses transcription", coordinator.status_blocker.include?("single active"))
  observation["profile_conflict"] = false
  observation["active_work_count"] = 1
  check("active model work refuses transcription", !coordinator.send(:admissible?, observation))
end
puts "CUDA Whisper routing verification passed."
