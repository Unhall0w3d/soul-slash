# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "time"
require "uri"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"

module SoulCore
  class DevModelRuntimeCoordinator
    UNIT_NAME = "soul-model-dev.service"
    DEFAULT_ENDPOINT = "http://127.0.0.1:18083"
    DEFAULT_MODEL = "gpt-oss:20b"
    DEFAULT_DIGEST = "17052f91a42e97930aa6e28a6c6c06a983e6a58dbb00434885a0cf5313e376f7"
    RESOURCE_GROUP = "amd-vulkan-generation"
    REQUEST_TTL_SECONDS = 1_860
    START_TIMEOUT_SECONDS = 180
    STOP_TIMEOUT_SECONDS = 30
    POLL_SECONDS = 0.5
    MAX_HTTP_BYTES = 256 * 1024

    class Busy < StandardError; end
    class IntegrityError < StandardError; end
    class RuntimeError < StandardError; end

    def initialize(root: Dir.pwd, env: ENV, runner: BoundedCommandRunner.new,
                   lease_store: nil, http_get: nil, http_post: nil,
                   sleeper: ->(seconds) { sleep(seconds) },
                   monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @root = File.expand_path(root)
      @env = env.to_h
      @runner = runner
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @http_get = http_get || method(:bounded_http_get)
      @http_post = http_post || method(:bounded_http_post)
      @sleeper = sleeper
      @monotonic_clock = monotonic_clock
      @endpoint = validated_endpoint(@env.fetch("SOUL_DEV_MODEL_ENDPOINT", DEFAULT_ENDPOINT))
      @model = validated_model(@env.fetch("SOUL_DEV_MODEL", DEFAULT_MODEL))
      @expected_digest = validated_digest(@env.fetch("SOUL_DEV_MODEL_DIGEST", DEFAULT_DIGEST))
    end

    def status
      unit = observe_unit
      server = unit == "active" ? observe_server : offline_server
      model = unit == "active" ? observe_loaded_model : nil
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "data" => {
          "service" => UNIT_NAME,
          "service_state" => unit,
          "endpoint" => @endpoint.to_s,
          "model" => @model,
          "expected_digest" => @expected_digest,
          "server" => server,
          "loaded" => !model.nil?,
          "resident" => !model.nil?,
          "placement" => model,
          "active_leases" => dev_leases,
          "active_work_count" => dev_leases.length,
          "ready" => unit == "active" && server["health"] == "ready"
        },
        "mutation" => "none"
      }
    rescue IntegrityError, ModelRuntimeLeaseStore::IntegrityError => error
      outcome(false, "blocked_for_human_review", error.message)
    end

    def activate_selected(on_progress: nil)
      lease = acquire_setup_lease("activate")
      progress(on_progress, "dev_runtime_starting", "Starting the reviewed local GPT-OSS Dev runtime.")
      ensure_started
      progress(on_progress, "dev_model_loading", "Loading and pinning GPT-OSS on the AMD development lane.")
      placement = ensure_loaded(keep_alive: -1)
      progress(on_progress, "dev_core_ready", "GPT-OSS is resident and Dev Core is ready.")
      outcome(true, "complete", "Dev runtime is resident", {
        "service" => UNIT_NAME, "model" => @model, "placement" => placement,
        "residency" => "selected_core", "restoration_required" => false
      }, mutation: "dev_runtime_activated")
    rescue ModelRuntimeLeaseStore::ResourceBusy => error
      outcome(false, "awaiting_input", "AMD development lane is busy: #{error.message}")
    rescue RuntimeError, IntegrityError => error
      outcome(false, "failed", error.message)
    ensure
      @lease_store.release(lease["lease_id"]) if defined?(lease) && lease
    end

    def deactivate_selected(on_progress: nil)
      active = dev_leases
      return outcome(false, "awaiting_input", "Dev work must reach a terminal state before leaving Dev Core", { "active_leases" => active }) unless active.empty?

      progress(on_progress, "dev_runtime_stopping", "Releasing the resident GPT-OSS development lane.")
      stop_service
      outcome(true, "complete", "Dev runtime is unloaded", {
        "service" => UNIT_NAME, "model" => @model, "resident" => false
      }, mutation: "dev_runtime_deactivated")
    rescue RuntimeError, IntegrityError => error
      outcome(false, "failed", error.message)
    end

    def with_request(request_id:, purpose:, selected_core:, on_progress: nil)
      lease = @lease_store.acquire_exclusive(
        provider_id: "local.dev", model_id: @model, request_id: request_id,
        conversation_id: purpose, resource_group: RESOURCE_GROUP,
        ttl_seconds: REQUEST_TTL_SECONDS
      )
      started_here = observe_unit != "active"
      progress(on_progress, "dev_runtime_starting", "Acquired the AMD development lane; starting GPT-OSS.") if started_here
      ensure_started
      placement = ensure_loaded(keep_alive: selected_core ? -1 : "30m")
      progress(on_progress, "dev_model_ready", "GPT-OSS is ready for one bounded development transaction.")
      value = yield({ "lease" => lease, "placement" => placement, "endpoint" => @endpoint.to_s, "model" => @model })
      [value, { "lease_id" => lease.fetch("lease_id"), "placement" => placement, "selected_core" => selected_core }]
    rescue ModelRuntimeLeaseStore::ResourceBusy => error
      raise Busy, "AMD development lane is busy: #{error.message}"
    ensure
      @lease_store.release(lease["lease_id"]) if defined?(lease) && lease
      if defined?(started_here) && started_here && !selected_core
        progress(on_progress, "dev_runtime_stopping", "The scoped Dev transaction is terminal; releasing GPT-OSS.")
        stop_service rescue nil
      end
    end

    private

    def acquire_setup_lease(action)
      @lease_store.acquire_exclusive(
        provider_id: "local.dev.control", model_id: @model,
        request_id: "dev-#{action}-#{SecureRandom.hex(4)}",
        resource_group: RESOURCE_GROUP, ttl_seconds: START_TIMEOUT_SECONDS + 60
      )
    end

    def ensure_started
      state = observe_unit
      return if state == "active" && observe_server["health"] == "ready"
      raise RuntimeError, "Dev runtime unit is not installed" if state == "unavailable"
      result = service_command("start")
      raise RuntimeError, "Dev runtime start command #{result.status}" unless result.success?

      wait_until(START_TIMEOUT_SECONDS) { observe_unit == "active" && observe_server["health"] == "ready" } ||
        raise(RuntimeError, "Dev runtime did not become ready before timeout")
    end

    def ensure_loaded(keep_alive:)
      current = observe_loaded_model
      return current if current && current["digest"] == @expected_digest

      response = @http_post.call(URI.join(@endpoint.to_s + "/", "api/generate"), {
        "model" => @model, "prompt" => "", "stream" => false,
        "keep_alive" => keep_alive, "options" => { "num_predict" => 1, "num_ctx" => 16_384 }
      })
      raise RuntimeError, "GPT-OSS load request failed" unless response[:status].to_i.between?(200, 299)
      placement = wait_until(START_TIMEOUT_SECONDS) { observe_loaded_model }
      raise RuntimeError, "GPT-OSS did not become resident before timeout" unless placement
      raise IntegrityError, "loaded Dev model digest does not match the reviewed artifact" unless placement["digest"] == @expected_digest
      placement
    end

    def stop_service
      state = observe_unit
      return if %w[inactive failed].include?(state)
      raise RuntimeError, "Dev runtime service state is uncertain" unless state == "active"
      result = service_command("stop")
      raise RuntimeError, "Dev runtime stop command #{result.status}" unless result.success?
      wait_until(STOP_TIMEOUT_SECONDS) { %w[inactive failed].include?(observe_unit) } ||
        raise(RuntimeError, "Dev runtime did not stop before timeout")
    end

    def observe_unit
      loaded = @runner.run("systemctl", "--user", "show", UNIT_NAME, "--property=LoadState", "--value", "--no-pager", timeout_seconds: 5, max_output_bytes: 1_024)
      return "unavailable" unless loaded.success? && loaded.stdout.to_s.strip == "loaded"
      active = @runner.run("systemctl", "--user", "is-active", UNIT_NAME, timeout_seconds: 5, max_output_bytes: 1_024)
      value = active.stdout.to_s.strip
      %w[active inactive failed activating deactivating].include?(value) ? value : "unknown"
    end

    def observe_server
      response = @http_get.call(URI.join(@endpoint.to_s + "/", "api/version"))
      response[:status].to_i.between?(200, 299) ? { "health" => "ready" } : offline_server
    rescue StandardError
      offline_server
    end

    def observe_loaded_model
      response = @http_get.call(URI.join(@endpoint.to_s + "/", "api/ps"))
      return nil unless response[:status].to_i.between?(200, 299)
      data = JSON.parse(response[:body].to_s)
      entry = Array(data["models"]).find { |item| [item["name"], item["model"]].include?(@model) }
      return nil unless entry
      entry.slice("name", "model", "digest", "size", "size_vram", "context_length", "details")
    rescue JSON::ParserError
      raise IntegrityError, "Dev runtime process inventory is invalid"
    end

    def dev_leases
      @lease_store.active_leases.select { |lease| lease["provider_id"].to_s.start_with?("local.dev") }
    end

    def service_command(action)
      @runner.run("systemctl", "--user", action, UNIT_NAME, timeout_seconds: 12, max_output_bytes: 8 * 1_024)
    end

    def wait_until(seconds)
      deadline = @monotonic_clock.call + seconds
      loop do
        value = yield
        return value if value
        return nil if @monotonic_clock.call >= deadline
        @sleeper.call(POLL_SECONDS)
      end
    end

    def bounded_http_get(uri)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 5) { |http| http.request(Net::HTTP::Get.new(uri)) }
      { status: response.code.to_i, body: response.body.to_s.byteslice(0, MAX_HTTP_BYTES) }
    end

    def bounded_http_post(uri, payload)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: START_TIMEOUT_SECONDS) { |http| http.request(request) }
      { status: response.code.to_i, body: response.body.to_s.byteslice(0, MAX_HTTP_BYTES) }
    end

    def validated_endpoint(value)
      uri = URI(value.to_s)
      raise IntegrityError, "Dev runtime endpoint must be loopback HTTP" unless uri.scheme == "http" && %w[127.0.0.1 localhost].include?(uri.host) && uri.port.between?(1_024, 65_535) && uri.path.to_s.match?(%r{\A/?\z})
      uri
    rescue URI::InvalidURIError
      raise IntegrityError, "Dev runtime endpoint is invalid"
    end

    def validated_model(value)
      text = value.to_s
      raise IntegrityError, "Dev model identifier is invalid" unless text.match?(%r{\A[A-Za-z0-9][A-Za-z0-9_.:/-]{0,119}\z})
      text
    end

    def validated_digest(value)
      text = value.to_s
      raise IntegrityError, "Dev model digest is invalid" unless text.match?(/\A[a-f0-9]{64}\z/)
      text
    end

    def offline_server = { "health" => "offline" }

    def progress(callback, stage, message)
      callback&.call("stage" => stage, "message" => message)
    rescue StandardError
      nil
    end

    def outcome(ok, lifecycle, reason, data = {}, mutation: "none")
      { "ok" => ok, "lifecycle_state" => lifecycle, "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
