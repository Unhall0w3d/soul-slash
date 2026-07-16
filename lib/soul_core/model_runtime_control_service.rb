# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "uri"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"
require_relative "model_runtime_profile_registry"

module SoulCore
  class ModelRuntimeControlService
    CONFIRMATIONS = {
      "load" => "LOAD_MODEL_RUNTIME",
      "unload" => "UNLOAD_MODEL_RUNTIME"
    }.freeze
    ACTIONS = %w[load unload switch].freeze
    COMMAND_TIMEOUT_SECONDS = 12
    HTTP_TIMEOUT_SECONDS = 2
    MAX_HTTP_BYTES = 128 * 1024
    MAX_SELECTION_BYTES = 1024

    def initialize(root: Dir.pwd, env: ENV, lease_store: nil, runner: BoundedCommandRunner.new, http_get: nil, profile_registry: nil)
      @root = File.expand_path(root)
      @env = env.to_h
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @runner = runner
      @http_get = http_get || method(:bounded_http_get)
      @profile_registry = profile_registry || ModelRuntimeProfileRegistry.new(root: @root, env: @env)
    end

    def status
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      configuration
      @lease_store.with_control_lock { success(status_unlocked) }
    rescue ModelRuntimeProfileRegistry::ConfigurationError => error
      unavailable(error.message)
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy", data: safe_base_projection.merge("control_busy" => true))
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message, data: safe_base_projection.merge("lease_integrity" => false))
    end

    def preview(action:, profile_id: nil)
      normalized = normalize_action(action)
      return normalized if normalized.is_a?(Hash)
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      configuration
      @lease_store.with_control_lock do
        observation = status_unlocked
        target = target_profile(normalized, profile_id, observation)
        return target if target.is_a?(Hash) && target.key?("ok")

        blocker = mutation_blocker(normalized, observation, target)
        return blocked(blocker, data: observation) if blocker

        scope = preview_scope(normalized, observation, target)
        success(observation.merge(
          "action" => normalized,
          "target_profile" => public_profile(target, observation),
          "expected_digest" => digest(scope),
          "confirmation_phrase" => confirmation_for(normalized, target),
          "preview_scope" => scope,
          "mutation" => "none"
        ))
      end
    rescue ModelRuntimeProfileRegistry::ConfigurationError => error
      unavailable(error.message)
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy")
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message)
    end

    def execute(action:, confirmation:, expected_digest:, profile_id: nil)
      normalized = normalize_action(action)
      return normalized if normalized.is_a?(Hash)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?
      return unavailable("model runtime control is disabled") unless enabled?
      return unavailable("model runtime slots URL must be loopback HTTP") unless slots_uri

      configuration
      @lease_store.with_control_lock do
        before = status_unlocked
        target = target_profile(normalized, profile_id, before)
        return target if target.is_a?(Hash) && target.key?("ok")

        blocker = mutation_blocker(normalized, before, target)
        return blocked(blocker, data: before) if blocker
        return blocked("exact model runtime confirmation did not match", data: before) unless confirmation == confirmation_for(normalized, target)
        return blocked("model runtime state changed; preview again", data: before) unless secure_compare(expected_digest, digest(preview_scope(normalized, before, target)))

        mutate(normalized, target, before)
      end
    rescue ModelRuntimeProfileRegistry::ConfigurationError => error
      unavailable(error.message)
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy")
    rescue ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message)
    end

    private

    def mutate(action, target, before)
      case action
      when "load"
        result = service_command("start", target)
        return command_failure("start", result, before) unless result.success?
        return failed("model runtime service did not become active", data: status_unlocked) unless observe_service_state(target.fetch("service")) == "active"

        persist_selected_profile(target.fetch("id"))
        success(status_unlocked.merge("action" => action, "mutation" => "model_runtime_loaded"), mutation: "model_runtime_loaded")
      when "unload"
        result = service_command("stop", target)
        return command_failure("stop", result, before) unless result.success?
        return failed("model runtime service did not become inactive", data: status_unlocked) unless observe_service_state(target.fetch("service")) == "inactive"

        success(status_unlocked.merge("action" => action, "mutation" => "model_runtime_unloaded"), mutation: "model_runtime_unloaded")
      else
        source = active_profile(before)
        stopped = service_command("stop", source)
        return command_failure("stop", stopped, before) unless stopped.success?
        unless observe_service_state(source.fetch("service")) == "inactive"
          return failed("source model runtime did not become inactive", data: status_unlocked.merge("completed" => []))
        end

        completed = [{ "action" => "stop", "profile_id" => source.fetch("id") }]
        started = service_command("start", target)
        unless started.success?
          return failed("target model runtime start command #{started.status}", data: status_unlocked.merge("completed" => completed, "rollback_profile_id" => source.fetch("id")))
        end
        unless observe_service_state(target.fetch("service")) == "active"
          return failed("target model runtime did not become active", data: status_unlocked.merge("completed" => completed, "rollback_profile_id" => source.fetch("id")))
        end

        persist_selected_profile(target.fetch("id"))
        success(status_unlocked.merge(
          "action" => action,
          "source_profile_id" => source.fetch("id"),
          "target_profile_id" => target.fetch("id"),
          "mutation" => "model_runtime_switched"
        ), mutation: "model_runtime_switched")
      end
    end

    def command_failure(command, result, observation)
      failed("model runtime service #{command} command #{result.status}", data: observation.merge("command_exit_status" => result.exit_status))
    end

    def service_command(command, profile)
      @runner.run("systemctl", "--user", command, profile.fetch("service"), timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: 8 * 1024)
    end

    def status_unlocked
      profiles = configuration.fetch("profiles").map do |profile|
        load_state = observe_unit_load_state(profile.fetch("service"))
        profile.merge(
          "unit_load_state" => load_state,
          "service_state" => load_state == "loaded" ? observe_service_state(profile.fetch("service")) : "unavailable"
        )
      end
      selected_id = selected_profile_id(profiles)
      active = profiles.select { |profile| profile.fetch("service_state") == "active" }
      current = active.one? ? active.first : profiles.find { |profile| profile.fetch("id") == selected_id }
      conflict = active.length > 1
      uncertain_units = profiles.any? { |profile| profile.fetch("service_state") == "unknown" }
      leases = @lease_store.active_leases_unlocked
      server = active.one? ? observe_server : offline_server
      server_processing = [server.fetch("active_slots", 0), server.fetch("processing_requests", 0)].max
      active_work = leases.length + server_processing + server.fetch("deferred_requests", 0)
      idle_certain = active.one? && !uncertain_units && server["slots_reachable"] && active_work.zero?

      projection = base_projection(current).merge(
        "profiles" => profiles.map { |profile| public_profile(profile, nil, selected_id: selected_id, active_ids: active.map { |item| item.fetch("id") }) },
        "selected_profile_id" => selected_id,
        "active_profile_id" => active.one? ? active.first.fetch("id") : nil,
        "active_profile_count" => active.length,
        "profile_conflict" => conflict,
        "service_state" => current&.fetch("service_state", "unknown") || "unknown",
        "loaded" => active.one?,
        "state" => aggregate_state(active, server, active_work, idle_certain, conflict, uncertain_units),
        "active_work_count" => active_work,
        "active_leases" => leases,
        "server" => server,
        "idle_certain" => idle_certain,
        "can_load" => active.empty? && !uncertain_units && profiles.any? { |profile| profile.fetch("id") == selected_id && profile.fetch("service_state") == "inactive" },
        "can_load_profile" => active.empty? && !uncertain_units && profiles.any? { |profile| profile.fetch("service_state") == "inactive" },
        "can_unload" => active.one? && idle_certain,
        "can_switch" => active.one? && idle_certain && profiles.any? { |profile| profile.fetch("service_state") == "inactive" },
        "automatic_load" => false,
        "automatic_unload" => false,
        "automatic_switch" => false
      )
      projection
    end

    def target_profile(action, requested_id, observation)
      profiles = configuration.fetch("profiles")
      active = observation.fetch("profiles").select { |profile| profile.fetch("service_state") == "active" }
      value = requested_id.to_s.strip
      value = if value.empty?
                action == "unload" && active.one? ? active.first.fetch("id") : observation.fetch("selected_profile_id")
              else
                value
              end
      target = profiles.find { |profile| profile.fetch("id") == value }
      return awaiting("known model runtime profile_id is required") unless target
      return awaiting("switch requires an explicit target profile_id") if action == "switch" && requested_id.to_s.strip.empty?

      target
    end

    def mutation_blocker(action, observation, target)
      return "multiple model runtime profiles are active; resolve the conflict manually" if observation["profile_conflict"]
      return "one or more model runtime service states are uncertain" if observation.fetch("profiles").any? { |profile| profile.fetch("service_state") == "unknown" }

      active = observation.fetch("profiles").select { |profile| profile.fetch("service_state") == "active" }
      case action
      when "load"
        return "a model runtime profile is already loaded" unless active.empty?
        target_state = observation.fetch("profiles").find { |profile| profile.fetch("id") == target.fetch("id") }.fetch("service_state")
        return "target model runtime profile service is not installed and loaded" if target_state == "unavailable"
        return "target model runtime profile must be inactive" unless target_state == "inactive"
      when "unload"
        return "exactly one model runtime profile must be loaded" unless active.one?
        return "requested profile is not the active runtime" unless active.first.fetch("id") == target.fetch("id")
        return idle_blocker(observation)
      when "switch"
        return "exactly one source model runtime profile must be loaded" unless active.one?
        return "target model runtime profile is already active" if active.first.fetch("id") == target.fetch("id")
        target_state = observation.fetch("profiles").find { |profile| profile.fetch("id") == target.fetch("id") }.fetch("service_state")
        return "target model runtime profile must be inactive" unless target_state == "inactive"
        return idle_blocker(observation)
      end
      nil
    end

    def idle_blocker(observation)
      return "active model work must complete or be canceled before the runtime changes" unless observation["active_work_count"].zero?
      return "llama.cpp slots state is unavailable; safe idle state cannot be established" unless observation["idle_certain"]

      nil
    end

    def preview_scope(action, observation, target)
      {
        "action" => action,
        "target_profile_id" => target.fetch("id"),
        "target_service" => target.fetch("service"),
        "selected_profile_id" => observation.fetch("selected_profile_id"),
        "active_profile_id" => observation["active_profile_id"],
        "profile_states" => observation.fetch("profiles").map { |profile| profile.slice("id", "service", "service_state") },
        "active_work_count" => observation.fetch("active_work_count"),
        "active_lease_ids" => observation.fetch("active_leases", []).map { |lease| lease["lease_id"] }.sort,
        "active_slots" => observation.dig("server", "active_slots"),
        "deferred_requests" => observation.dig("server", "deferred_requests"),
        "slots_reachable" => observation.dig("server", "slots_reachable")
      }
    end

    def confirmation_for(action, target)
      return CONFIRMATIONS.fetch(action) unless configuration.fetch("multi_profile")

      token = target.fetch("id").upcase.tr("-", "_")
      return "SWITCH_MODEL_RUNTIME_TO_#{token}" if action == "switch"

      "#{action.upcase}_MODEL_RUNTIME_#{token}"
    end

    def public_profile(profile, observation = nil, selected_id: nil, active_ids: nil)
      selected_id ||= observation&.fetch("selected_profile_id", nil)
      active_ids ||= observation ? [observation["active_profile_id"]].compact : []
      {
        "id" => profile.fetch("id"),
        "label" => profile.fetch("label"),
        "service" => profile.fetch("service"),
        "service_state" => profile["service_state"] || observation&.fetch("profiles", [])&.find { |item| item["id"] == profile["id"] }&.fetch("service_state", "unknown") || "unknown",
        "selected" => selected_id == profile.fetch("id"),
        "active" => active_ids.include?(profile.fetch("id"))
      }
    end

    def active_profile(observation)
      id = observation.fetch("active_profile_id")
      configuration.fetch("profiles").find { |profile| profile.fetch("id") == id }
    end

    def observe_service_state(service)
      result = @runner.run("systemctl", "--user", "is-active", service, timeout_seconds: 4, max_output_bytes: 4096)
      state = result.stdout.to_s.strip
      return "active" if result.success? && state == "active"
      return "inactive" if %w[inactive failed].include?(state)

      "unknown"
    end

    def observe_unit_load_state(service)
      result = @runner.run(
        "systemctl", "--user", "show", service, "--property=LoadState", "--value",
        timeout_seconds: 4, max_output_bytes: 4096
      )
      value = result.stdout.to_s.strip
      return "loaded" if result.success? && value == "loaded"
      return "not-found" if value == "not-found"

      "unknown"
    end

    def observe_server
      slots = parse_slots(@http_get.call(slots_uri))
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
      { "slots_reachable" => false, "health" => "offline", "total_slots" => 0, "active_slots" => 0,
        "processing_requests" => 0, "deferred_requests" => 0, "metrics_available" => false }
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

    def aggregate_state(active, server, active_work, idle_certain, conflict, uncertain_units)
      return "unavailable" if conflict || uncertain_units
      return "unloaded" if active.empty?
      return "busy" if active_work.positive?
      return "loaded" if idle_certain && server["health"] == "ready"
      return "loading" if server["health"] == "loading"

      "uncertain"
    end

    def configuration
      @configuration ||= @profile_registry.configuration
    end

    def selected_profile_id(profiles)
      path = selection_path
      return configuration.fetch("default_profile") unless File.exist?(path)

      stat = File.lstat(path)
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection must be a regular file" unless stat.file? && !stat.symlink?
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection exceeds size limit" if stat.size > MAX_SELECTION_BYTES
      record = JSON.parse(File.binread(path, MAX_SELECTION_BYTES))
      id = record["profile_id"].to_s
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid" unless record.keys == ["profile_id"] && profiles.any? { |profile| profile.fetch("id") == id }

      id
    rescue JSON::ParserError
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid"
    end

    def persist_selected_profile(profile_id)
      directory = File.dirname(selection_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
      temporary = "#{selection_path}.#{Process.pid}.tmp"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate("profile_id" => profile_id) + "\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, selection_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    def selection_path
      File.join(@root, ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "selected_profile.json")
    end

    def base_projection(profile)
      {
        "configured" => true,
        "control_enabled" => enabled?,
        "service" => profile&.fetch("service", nil),
        "profile" => profile&.fetch("id", nil),
        "profile_label" => profile&.fetch("label", nil),
        "model" => model,
        "provider_endpoint" => @env["SOUL_LOCAL_OPENAI_BASE_URL"],
        "slots_url" => slots_uri&.to_s,
        "manual_only" => true,
        "multi_profile" => configuration.fetch("multi_profile")
      }
    end

    def safe_base_projection
      base_projection(configuration.fetch("profiles").first)
    rescue StandardError
      { "configured" => false, "control_enabled" => enabled?, "manual_only" => true }
    end

    def normalize_action(value)
      action = value.to_s
      return action if ACTIONS.include?(action)

      awaiting("action must be load, unload, or switch")
    end

    def enabled?
      %w[1 true yes on].include?(@env["SOUL_MODEL_RUNTIME_CONTROL"].to_s.downcase)
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
      Digest::SHA256.hexdigest(JSON.generate(deep_sort(scope)))
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    end

    def success(data, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    end

    def blocked(reason, data: {})
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => data, "mutation" => "none" }
    end

    def failed(reason, data: {})
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => "partial_or_none" }
    end

    def unavailable(reason)
      blocked(reason, data: safe_base_projection)
    end
  end
end
