# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"

module SoulCore
  class ModelRuntimeControlService
    UNIT_PATTERN = /\A(?:llama-server|soul-[A-Za-z0-9@_.-]+)\.service\z/
    CONFIRMATIONS = {
      "load" => "LOAD_MODEL_RUNTIME",
      "unload" => "UNLOAD_MODEL_RUNTIME"
    }.freeze
    COMMAND_TIMEOUT_SECONDS = 12
    HTTP_TIMEOUT_SECONDS = 2
    MAX_HTTP_BYTES = 128 * 1024

    def initialize(root: Dir.pwd, env: ENV, lease_store: nil, runner: BoundedCommandRunner.new, http_get: nil)
      @root = File.expand_path(root)
      @env = env.to_h
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @runner = runner
      @http_get = http_get || method(:bounded_http_get)
    end

    def status
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime service is not allowlisted") unless valid_unit?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      @lease_store.with_control_lock { success(status_unlocked) }
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy", data: base_projection.merge("control_busy" => true))
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message, data: base_projection.merge("lease_integrity" => false))
    end

    def preview(action:)
      normalized = normalize_action(action)
      return normalized if normalized.is_a?(Hash)
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime service is not allowlisted") unless valid_unit?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      @lease_store.with_control_lock do
        observation = status_unlocked
        blocker = mutation_blocker(normalized, observation)
        return blocked(blocker, data: observation) if blocker

        scope = preview_scope(normalized, observation)
        success(observation.merge(
          "action" => normalized,
          "expected_digest" => digest(scope),
          "confirmation_phrase" => CONFIRMATIONS.fetch(normalized),
          "preview_scope" => scope,
          "mutation" => "none"
        ))
      end
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy")
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message)
    end

    def execute(action:, confirmation:, expected_digest:)
      normalized = normalize_action(action)
      return normalized if normalized.is_a?(Hash)
      return awaiting("confirmation is required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return blocked("exact model runtime confirmation did not match") unless confirmation == CONFIRMATIONS.fetch(normalized)
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime service is not allowlisted") unless valid_unit?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      @lease_store.with_control_lock do
        before = status_unlocked
        blocker = mutation_blocker(normalized, before)
        return blocked(blocker, data: before) if blocker
        return blocked("model runtime state changed; preview again", data: before) unless secure_compare(expected_digest, digest(preview_scope(normalized, before)))

        result = @runner.run(
          "systemctl", "--user", normalized == "load" ? "start" : "stop", unit,
          timeout_seconds: COMMAND_TIMEOUT_SECONDS,
          max_output_bytes: 8 * 1024
        )
        return failed("model runtime service command #{result.status}", data: before.merge("command_exit_status" => result.exit_status)) unless result.success?

        after = status_unlocked
        verified = normalized == "load" ? after["service_state"] == "active" : after["service_state"] == "inactive"
        return failed("model runtime service did not reach the expected state", data: after) unless verified

        success(after.merge(
          "action" => normalized,
          "mutation" => normalized == "load" ? "model_runtime_loaded" : "model_runtime_unloaded"
        ), mutation: normalized == "load" ? "model_runtime_loaded" : "model_runtime_unloaded")
      end
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy")
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message)
    end

    private

    def status_unlocked
      leases = @lease_store.active_leases_unlocked
      service_state = observe_service_state
      server = service_state == "active" ? observe_server : offline_server
      server_processing = [server.fetch("active_slots", 0), server.fetch("processing_requests", 0)].max
      active_work = leases.length + server_processing + server.fetch("deferred_requests", 0)
      certain = %w[active inactive].include?(service_state) && (service_state == "inactive" || server["slots_reachable"])

      base_projection.merge(
        "service_state" => service_state,
        "loaded" => service_state == "active",
        "state" => runtime_state(service_state, server, active_work, certain),
        "active_work_count" => active_work,
        "active_leases" => leases,
        "server" => server,
        "idle_certain" => certain && active_work.zero?,
        "can_load" => service_state == "inactive",
        "can_unload" => service_state == "active" && certain && active_work.zero?,
        "automatic_load" => false,
        "automatic_unload" => false
      )
    end

    def observe_service_state
      result = @runner.run("systemctl", "--user", "is-active", unit, timeout_seconds: 4, max_output_bytes: 4096)
      state = result.stdout.to_s.strip
      return "active" if result.success? && state == "active"
      return "inactive" if %w[inactive failed].include?(state)

      "unknown"
    end

    def observe_server
      slots_response = @http_get.call(slots_uri)
      slots = parse_slots(slots_response)
      metrics = parse_metrics(@http_get.call(metrics_uri))
      health = parse_health(@http_get.call(health_uri))
      {
        "slots_reachable" => !slots.nil?,
        "health" => health,
        "total_slots" => slots&.length,
        "active_slots" => slots ? slots.count { |slot| slot["is_processing"] == true } : 0,
        "processing_requests" => metrics.fetch("processing_requests", 0),
        "deferred_requests" => metrics.fetch("deferred_requests", 0),
        "metrics_available" => metrics.fetch("available", false)
      }
    end

    def offline_server
      {
        "slots_reachable" => false,
        "health" => "offline",
        "total_slots" => 0,
        "active_slots" => 0,
        "processing_requests" => 0,
        "deferred_requests" => 0,
        "metrics_available" => false
      }
    end

    def parse_slots(response)
      return nil unless response && response.fetch(:status, 0).between?(200, 299)

      value = JSON.parse(response.fetch(:body))
      return nil unless value.is_a?(Array) && value.length <= 64
      return nil unless value.all? { |slot| slot.is_a?(Hash) && [true, false].include?(slot["is_processing"]) }

      value
    rescue JSON::ParserError, KeyError
      nil
    end

    def parse_health(response)
      return "unreachable" unless response
      return "loading" if response.fetch(:status, 0) == 503
      return "ready" if response.fetch(:status, 0).between?(200, 299)

      "failed"
    end

    def parse_metrics(response)
      return { "available" => false, "processing_requests" => 0, "deferred_requests" => 0 } unless response && response.fetch(:status, 0).between?(200, 299)

      values = { "available" => true, "processing_requests" => 0, "deferred_requests" => 0 }
      response.fetch(:body).each_line do |line|
        values["processing_requests"] = line.split.last.to_i if line.start_with?("llamacpp:requests_processing ")
        values["deferred_requests"] = line.split.last.to_i if line.start_with?("llamacpp:requests_deferred ")
      end
      values
    end

    def bounded_http_get(uri)
      request = Net::HTTP::Get.new(uri.request_uri)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: HTTP_TIMEOUT_SECONDS, read_timeout: HTTP_TIMEOUT_SECONDS) { |http| http.request(request) }
      body = response.body.to_s
      return nil if body.bytesize > MAX_HTTP_BYTES

      { status: response.code.to_i, body: body }
    rescue StandardError
      nil
    end

    def mutation_blocker(action, observation)
      if action == "load"
        return "model runtime service state is uncertain" if observation["service_state"] == "unknown"
        return "model runtime is already loaded" unless observation["service_state"] == "inactive"
      else
        return "model runtime service state is uncertain" if observation["service_state"] == "unknown"
        return "model runtime is already unloaded" unless observation["service_state"] == "active"
        return "active model work must complete or be canceled before unload" unless observation["active_work_count"].zero?
        return "llama.cpp slots state is unavailable; safe idle state cannot be established" unless observation["idle_certain"]
      end
      nil
    end

    def preview_scope(action, observation)
      {
        "action" => action,
        "unit" => unit,
        "profile" => profile,
        "model" => model,
        "service_state" => observation["service_state"],
        "active_work_count" => observation["active_work_count"],
        "active_lease_ids" => observation.fetch("active_leases", []).map { |lease| lease["lease_id"] }.sort,
        "active_slots" => observation.dig("server", "active_slots"),
        "deferred_requests" => observation.dig("server", "deferred_requests"),
        "slots_reachable" => observation.dig("server", "slots_reachable")
      }
    end

    def base_projection
      {
        "configured" => enabled? && valid_unit? && !slots_uri.nil?,
        "control_enabled" => enabled?,
        "service" => valid_unit? ? unit : nil,
        "profile" => profile,
        "model" => model,
        "provider_endpoint" => @env["SOUL_LOCAL_OPENAI_BASE_URL"],
        "slots_url" => slots_uri&.to_s,
        "manual_only" => true
      }
    end

    def runtime_state(service_state, server, active_work, certain)
      return "unloaded" if service_state == "inactive"
      return "unavailable" if service_state == "unknown"
      return "busy" if active_work.positive?
      return "loaded" if certain && server["health"] == "ready"
      return "loading" if server["health"] == "loading"

      "uncertain"
    end

    def normalize_action(value)
      action = value.to_s
      return action if CONFIRMATIONS.key?(action)

      awaiting("action must be load or unload")
    end

    def enabled?
      %w[1 true yes on].include?(@env["SOUL_MODEL_RUNTIME_CONTROL"].to_s.downcase)
    end

    def unit
      @env["SOUL_MODEL_RUNTIME_SERVICE"].to_s
    end

    def valid_unit?
      unit.match?(UNIT_PATTERN)
    end

    def profile
      @env["SOUL_MODEL_RUNTIME_PROFILE"].to_s.empty? ? "local-model" : @env["SOUL_MODEL_RUNTIME_PROFILE"].to_s.slice(0, 80)
    end

    def model
      (@env["SOUL_LOCAL_OPENAI_MODEL"] || @env["SOUL_MODEL_ALIAS"]).to_s.slice(0, 160)
    end

    def slots_uri
      @slots_uri ||= loopback_uri(@env["SOUL_MODEL_RUNTIME_SLOTS_URL"], required_path: "/slots")
    end

    def metrics_uri
      replace_path(slots_uri, "/metrics")
    end

    def health_uri
      replace_path(slots_uri, "/health")
    end

    def replace_path(uri, path)
      copy = uri.dup
      copy.path = path
      copy.query = nil
      copy
    end

    def loopback_uri(value, required_path:)
      uri = URI.parse(value.to_s)
      return nil unless uri.is_a?(URI::HTTP) && uri.scheme == "http" && %w[127.0.0.1 localhost ::1].include?(uri.host)
      return nil unless uri.path == required_path && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?

      uri
    rescue URI::InvalidURIError
      nil
    end

    def digest(scope)
      Digest::SHA256.hexdigest(JSON.generate(scope.sort.to_h))
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def success(data, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    end

    def blocked(reason, data: {})
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => data, "mutation" => "none" }
    end

    def failed(reason, data: {})
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => "none" }
    end

    def unavailable(reason)
      blocked(reason, data: base_projection)
    end
  end
end
