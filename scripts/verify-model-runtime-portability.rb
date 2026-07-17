#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/soul_core/application_facade"
require_relative "../lib/soul_core/bounded_command_runner"
require_relative "../lib/soul_core/conversation_provider_client"
require_relative "../lib/soul_core/conversation_provider_contract"
require_relative "../lib/soul_core/model_runtime_control_service"
require_relative "../lib/soul_core/model_runtime_lease_store"

errors = []

def check(label, condition, errors)
  puts "- #{label}: #{condition ? 'ok' : 'missing'}"
  errors << label unless condition
end

class FakeRunner
  attr_accessor :state
  attr_reader :commands

  def initialize(state: "active")
    @state = state
    @commands = []
  end

  def run(*command, **_options)
    @commands << command
    case command[2]
    when "show"
      result(true, "loaded\n", 0)
    when "is-active"
      result(@state == "active", "#{@state}\n", @state == "active" ? 0 : 3)
    when "start"
      @state = "active"
      result(true, "", 0)
    when "stop"
      @state = "inactive"
      result(true, "", 0)
    else
      result(false, "", 1)
    end
  end

  private

  def result(ok, stdout, exit_status)
    SoulCore::BoundedCommandRunner::Result.new(
      stdout: stdout,
      stderr: "",
      exit_status: exit_status,
      status: ok ? "ok" : "failed",
      truncated: false
    )
  end
end

class LeaseSpy
  attr_reader :observed

  def initialize
    @observed = []
    @active = false
  end

  def with_lease(**scope)
    @active = true
    @observed << scope.merge(active_inside: @active)
    yield
  ensure
    @active = false
  end

  def active?
    @active
  end
end

class FakeProviderClient < SoulCore::ConversationProviderClient
  private

  def openai_chat(_provider, _request, _timeout_seconds)
    raise "lease missing during provider call" unless @lease_store.active?

    :provider_response
  end
end

class FailingProviderClient < SoulCore::ConversationProviderClient
  private

  def openai_chat(_provider, _request, _timeout_seconds)
    raise "synthetic provider failure"
  end
end

puts "Soul Model Runtime Portability verification:"

Dir.mktmpdir("soul-model-runtime-") do |root|
  now = Time.utc(2026, 7, 15, 12, 0, 0)
  clock = -> { now }
  lease_store = SoulCore::ModelRuntimeLeaseStore.new(root: root, clock: clock)
  runner = FakeRunner.new
  active_slots = 0
  metrics_processing = 0
  slots_reachable = true
  http_get = lambda do |uri|
    case uri.path
    when "/slots"
      slots_reachable ? { status: 200, body: JSON.generate([{ "is_processing" => active_slots.positive? }]) } : nil
    when "/health"
      { status: runner.state == "active" ? 200 : 503, body: JSON.generate({ "status" => "ok" }) }
    when "/metrics"
      { status: 200, body: "llamacpp:requests_processing #{metrics_processing}\nllamacpp:requests_deferred 0\n" }
    end
  end
  env = {
    "SOUL_MODEL_RUNTIME_CONTROL" => "1",
    "SOUL_MODEL_RUNTIME_SERVICE" => "llama-server.service",
    "SOUL_MODEL_RUNTIME_SLOTS_URL" => "http://127.0.0.1:8082/slots",
    "SOUL_MODEL_RUNTIME_PROFILE" => "nvidia-fallback",
    "SOUL_LOCAL_OPENAI_BASE_URL" => "http://127.0.0.1:8082/v1",
    "SOUL_LOCAL_OPENAI_MODEL" => "fixture-model"
  }
  service = SoulCore::ModelRuntimeControlService.new(root: root, env: env, lease_store: lease_store, runner: runner, http_get: http_get)

  status = service.status
  check("idle active runtime status", status["ok"] && status.dig("data", "state") == "loaded" && status.dig("data", "can_unload"), errors)
  facade = SoulCore::ApplicationFacade.new(root: root, process_env: {}, model_runtime_control_service: service)
  facade_status = facade.call({
    "schema_version" => "soul.application.v1", "request_id" => "runtime-status-fixture",
    "operation" => "model_runtime.status", "parameters" => {}, "context" => { "interface" => "dashboard_test" }
  })
  check("application facade returns the bounded runtime projection", facade_status["ok"] && facade_status.dig("data", "service") == "llama-server.service", errors)

  unload = service.preview(action: "unload")
  check("unload preview has exact digest gate", unload["ok"] && unload.dig("data", "confirmation_phrase") == "UNLOAD_MODEL_RUNTIME" && unload.dig("data", "expected_digest").to_s.length == 64, errors)
  wrong = service.execute(action: "unload", confirmation: "UNLOAD_MODEL_RUNTIME", expected_digest: "0" * 64)
  check("changed preview blocks mutation", wrong["lifecycle_state"] == "blocked_for_human_review" && runner.state == "active", errors)
  stopped = service.execute(action: "unload", confirmation: "UNLOAD_MODEL_RUNTIME", expected_digest: unload.dig("data", "expected_digest"))
  check("verified unload stops only configured user unit", stopped["ok"] && runner.state == "inactive" && runner.commands.include?(["systemctl", "--user", "stop", "llama-server.service"]), errors)

  music_lease = lease_store.acquire(provider_id: "nvidia-music", model_id: "ace-step-1.5", request_id: "candidate-fixture", ttl_seconds: 120)
  music_busy = service.preview(action: "load")
  check("active Music lease blocks unloaded NVIDIA runtime load", music_busy["lifecycle_state"] == "blocked_for_human_review" && music_busy.dig("data", "active_work_count") == 1 && runner.state == "inactive", errors)
  lease_store.release(music_lease.fetch("lease_id"))

  load = service.preview(action: "load")
  started = service.execute(action: "load", confirmation: "LOAD_MODEL_RUNTIME", expected_digest: load.dig("data", "expected_digest"))
  check("verified load starts only configured user unit", load["ok"] && started["ok"] && runner.commands.include?(["systemctl", "--user", "start", "llama-server.service"]), errors)

  lease = lease_store.acquire(provider_id: "local.openai_compatible", model_id: "fixture-model", request_id: "request-active", ttl_seconds: 120)
  busy = service.preview(action: "unload")
  check("live Soul provider lease blocks unload", busy["lifecycle_state"] == "blocked_for_human_review" && busy.dig("data", "active_work_count") == 1, errors)
  lease_store.release(lease.fetch("lease_id"))

  active_slots = 1
  slot_busy = service.preview(action: "unload")
  check("active llama.cpp slot blocks unload", slot_busy["lifecycle_state"] == "blocked_for_human_review" && slot_busy.dig("data", "server", "active_slots") == 1, errors)
  active_slots = 0

  metrics_processing = 1
  metrics_busy = service.preview(action: "unload")
  check("provider metrics can independently block unload", metrics_busy["lifecycle_state"] == "blocked_for_human_review" && metrics_busy.dig("data", "active_work_count") == 1, errors)
  metrics_processing = 0

  slots_reachable = false
  uncertain = service.preview(action: "unload")
  check("unreachable slots block unload", uncertain["lifecycle_state"] == "blocked_for_human_review" && !uncertain.dig("data", "idle_certain"), errors)
  slots_reachable = true

  expiring = lease_store.acquire(provider_id: "local.openai_compatible", model_id: "fixture-model", request_id: "request-expiring", ttl_seconds: 1)
  now += 2
  expired_path = File.join(root, "Soul", "runtime", "model_runtime", "leases", "#{expiring['lease_id']}.json")
  check("expired lease is removed by bounded foreground inspection", lease_store.active_leases.empty? && !File.exist?(expired_path), errors)

  disabled = SoulCore::ModelRuntimeControlService.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_CONTROL" => "0"), lease_store: lease_store, runner: runner, http_get: http_get).status
  check("control is disabled by default contract", disabled["lifecycle_state"] == "blocked_for_human_review", errors)
  invalid = SoulCore::ModelRuntimeControlService.new(root: root, env: env.merge("SOUL_MODEL_RUNTIME_SERVICE" => "ssh.service"), lease_store: lease_store, runner: runner, http_get: http_get).status
  check("arbitrary user units are rejected", invalid["lifecycle_state"] == "blocked_for_human_review" && invalid.dig("data", "service").nil?, errors)

  spy = LeaseSpy.new
  client = FakeProviderClient.new(env: {}, root: root, lease_store: spy)
  provider = SoulCore::ConversationProviderContract::ProviderDefinition.new(
    id: "local.openai_compatible", label: "Fixture", transport: "openai_compatible",
    endpoint: "http://127.0.0.1:8082/v1", model: "fixture-model", privacy_class: "local_only",
    capabilities: ["chat"], configured: true
  )
  request = SoulCore::ConversationProviderContract::RequestEnvelope.new(
    request_id: "request-provider-lease", conversation_id: "chat_fixture",
    messages: [{ "role" => "user", "content" => "synthetic" }]
  )
  response = client.chat(provider: provider, request: request, timeout_seconds: 3)
  check("local provider call holds and releases a lease", response == :provider_response && !spy.active? && spy.observed.one? && spy.observed.first[:active_inside], errors)
  failure_spy = LeaseSpy.new
  failure = FailingProviderClient.new(env: {}, root: root, lease_store: failure_spy).chat(provider: provider, request: request, timeout_seconds: 3)
  check("provider failure releases its lease", !failure.error.nil? && !failure_spy.active? && failure_spy.observed.one?, errors)
end

contract = File.read(File.join(__dir__, "..", "lib", "soul_core", "application_contract.rb"))
facade = File.read(File.join(__dir__, "..", "lib", "soul_core", "application_facade.rb"))
dashboard = File.read(File.join(__dir__, "..", "assets", "dashboard", "dashboard.js"))
html = File.read(File.join(__dir__, "..", "assets", "dashboard", "index.html"))
brief = File.read(File.join(__dir__, "..", "docs", "soul", "MODEL_RUNTIME_PORTABILITY_BRIEF.md"))

operations = %w[model_runtime.status model_runtime.load.preview model_runtime.load.execute model_runtime.unload.preview model_runtime.unload.execute]
check("application operations are explicitly allowlisted", operations.all? { |operation| contract.include?(%("#{operation}")) && facade.include?(%(when "#{operation}")) }, errors)
check("dashboard exposes manual model controls", %w[refresh-model-runtime load-model-runtime unload-model-runtime model-runtime-dialog].all? { |id| html.include?(%(id="#{id}")) }, errors)
check("dashboard has no automatic runtime timer", !dashboard.match?(/setInterval|setTimeout|requestAnimationFrame/), errors)
check("approved brief prohibits force and automatic unload", brief.include?("implementation_authorized: yes") && brief.include?("No automatic idle unload") && brief.include?("No forced termination"), errors)

if errors.empty?
  puts "Verification complete."
  puts "Model Runtime Portability is candidate-complete for deterministic review."
else
  warn "Verification failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
