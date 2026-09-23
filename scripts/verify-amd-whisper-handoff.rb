#!/usr/bin/env ruby
# frozen_string_literal: true
require "tmpdir"
require_relative "../lib/soul_core/amd_whisper_runtime_handoff"

class AmdHandoffFixture
  GIB = SoulCore::AmdWhisperDevice::GIB
  attr_accessor :mode, :core, :worked
  attr_reader :commands, :states, :payloads
  def initialize(mode)
    @mode, @core, @commands, @worked = mode, "daily", [], false
    @payloads = []
    @core = "free" if mode == :free
    @states = {"soul-model-gemma.service"=>"active", "soul-model-dev.service"=>"inactive", "llama-server.service"=>"inactive"}
    if %i[nvidia dev memory].include?(mode)
      @core = mode == :dev ? "dev" : "amd-free"
      @states["soul-model-gemma.service"] = "inactive"
      @states["llama-server.service"] = "active"
      @states["soul-model-dev.service"] = "active" if mode == :dev
    end
    @loaded = @states.transform_values { |s| s == "active" }
    if mode == :multi_restore
      @states["soul-model-dev.service"] = "active"
      @loaded["soul-model-dev.service"] = true
    end
  end
  def persisted_selection(profiles:)
    raise "corrupt selection" if mode == :corrupt
    {"active_core_id"=>core}
  end
  def with_controlled_observation
    return {"reason"=>"model runtime control is busy"} if mode == :lock
    return {"reason"=>"model runtime control is disabled"} if mode == :disabled
    profiles = @states.reject { |u, _| u == "soul-model-dev.service" }.map do |u,s|
      {"id"=>u == "llama-server.service" ? "nvidia-fallback" : "amd-gemma", "service"=>u,
       "runtime"=>"ollama_openai", "accelerator"=>u == "llama-server.service" ? "NVIDIA" : "AMD Vulkan",
       "endpoint"=>"http://127.0.0.1:8082/v1", "service_state"=>s}
    end
    yield({"profiles"=>profiles,"active_profile_count"=>1,"profile_conflict"=>false,
           "idle_certain"=>mode != :unknown,"active_work_count"=>mode == :busy ? 1 : 0,"active_leases"=>[]})
  end
  def observe_service_state(unit) = @states.fetch(unit)
  def unit(uri) = uri.to_s.include?("18083") ? "soul-model-dev.service" : "soul-model-gemma.service"
  def model(u)
    {"name"=>u.include?("dev") ? "gpt-oss:20b" : "soul-local-chat:latest", "digest"=>"a"*64,
     "size_vram"=>6*GIB,"context_length"=>16384,"expires_at"=>"2036-09-06T00:00:00Z"}
  end
  def bounded_http_get(uri)
    u = unit(uri)
    row = model(u)
    row["digest"] = "b"*64 if mode == :identity && worked
    {status:200, body:JSON.generate({"models"=>@loaded[u] ? [row] : []})}
  end
  def service_command(action, target)
    @commands << [action, target.fetch("service")]
    unless mode == :stop_unchanged
      @states[target.fetch("service")] = "inactive"
      @loaded[target.fetch("service")] = false
    end
    result(%i[stop stop_unchanged].include?(mode) ? "failed" : "ok")
  end
  def restore_temporary_profile(target)
    @commands << ["start", target.fetch("service")]
    return "restore failed" if mode == :restore || (mode == :multi_restore && target["service"] == "soul-model-gemma.service")
    @states[target.fetch("service")] = "active"
    nil
  end
  def run(*args, **)
    @payloads << JSON.parse(args.fetch(args.index("--data-binary") + 1))
    @commands << ["warm", unit(args.last)]
    @loaded[unit(args.last)] = true unless mode == :reload
    result(mode == :reload ? "failed" : "ok")
  end
  def result(status) = SoulCore::BoundedCommandRunner::Result.new(status:status, stdout:"", stderr:"", truncated:false)
  def snapshot(services:)
    if worked && (mode == :unsettled || (mode == :settle && !@settled))
      @settled = true
      raise SoulCore::AmdWhisperDevice::AllocationUnsettled, "driver teardown not settled"
    end
    raise "foreign allocation" if mode == :foreign || (mode == :cleanup && worked)
    a = services.to_h { |s| [s, @loaded[s] ? 6*GIB : 0] }
    a = {} if mode == :placement
    used = GIB + a.values.sum
    {"allocations"=>a,"used"=>used,"free"=>mode == :memory && !commands.any? ? GIB : 16*GIB-used}
  end
  def verify_vulkan! = true
end

checks = 0
check = ->(label, ok) { raise "FAIL: #{label}" unless ok; checks += 1; puts "PASS: #{label}" }
%i[normal nvidia dev free corrupt busy unknown lock disabled foreign placement memory stop stop_unchanged work cancel cleanup restore reload identity stale multi_restore settle unsettled].each do |mode|
  Dir.mktmpdir("amd-handoff-") do |root|
    directory = File.join(root, "Soul/runtime/model_runtime")
    FileUtils.mkdir_p(directory)
    pending = File.join(directory, "whisper-pending.json")
    File.write(pending, "{}") if mode == :stale
    fixture = AmdHandoffFixture.new(mode)
    tick = 0
    coordinator = SoulCore::AmdWhisperRuntimeHandoff.new(root:root,env:{},control:fixture,runner:fixture,device:fixture,selection:fixture,clock:-> { tick += mode == :settle ? 0.1 : 5 },sleeper:->(_) {})
    error = value = nil
    begin
      value = coordinator.run do
        fixture.worked = true
        check.call("#{mode} private pending journal precedes work", File.stat(pending).mode & 0o777 == 0o600)
        raise "recognition failed" if mode == :work
        raise Interrupt if mode == :cancel
        :transcript
      end
    rescue StandardError, Interrupt => caught
      error = caught
    end
    if %i[normal nvidia dev settle].include?(mode)
      check.call("#{mode} returned after recovery", !error && value.first == :transcript && value.last["restored"])
      expected = mode == :nvidia ? [] : %w[stop start warm]
      check.call("#{mode} exact bounded service sequence", fixture.commands.map(&:first) == expected)
      check.call("#{mode} cleared pending receipt", !File.exist?(pending))
      check.call("Dev GPT-OSS remains pinned after reload", fixture.payloads.one? && fixture.payloads.first["keep_alive"] == -1) if mode == :dev
    else
      check.call("#{mode} withheld transcript", error && value.nil?)
      if %i[free corrupt busy unknown lock disabled foreign placement memory stale].include?(mode)
        check.call("#{mode} no workload or mutation", !fixture.worked && fixture.commands.empty?)
      elsif %i[cleanup restore reload identity multi_restore unsettled].include?(mode)
        check.call("#{mode} recovery receipt retained", File.file?(pending))
        if mode == :multi_restore
          check.call("remaining borrowed runtime restored despite first failure", fixture.commands.last == ["warm", "soul-model-dev.service"] && fixture.states["soul-model-dev.service"] == "active")
        end
      elsif mode == :stop_unchanged
        check.call("unchanged partial stop avoids reload", fixture.commands.map(&:first) == ["stop"] && !File.exist?(pending))
      else
        check.call("#{mode} restores before returning failure", fixture.commands.map(&:first) == %w[stop start warm] && !File.exist?(pending))
      end
    end
    check.call("#{mode} NVIDIA never mutated", fixture.commands.none? { |_, unit| unit == "llama-server.service" })
  end
end
puts "#{checks} AMD handoff checks passed"

Dir.mktmpdir("amd-clock-bound-") do |root|
  FileUtils.mkdir_p(File.join(root, "Soul/runtime/model_runtime"))
  fixture = AmdHandoffFixture.new(:busy)
  coordinator = SoulCore::AmdWhisperRuntimeHandoff.new(root:root, env:{}, control:fixture,
    runner:fixture, device:fixture, selection:fixture, clock:-> { 0 }, sleeper:->(_) {})
  begin
    coordinator.run { raise "must not run" }
    raise "fixed-clock admission unexpectedly succeeded"
  rescue SoulCore::WhisperRuntimeHandoff::Error => error
    check.call("fixed clock still has bounded admission attempts", error.message.include?("attempt limit") && fixture.commands.empty?)
  end
end
