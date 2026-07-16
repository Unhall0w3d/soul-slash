# frozen_string_literal: true

require "json"
require_relative "bounded_command_runner"
require_relative "model_runtime_lease_store"
require_relative "model_runtime_profile_registry"

module SoulCore
  class ModelRuntimeSelectedStarter
    MAX_SELECTION_BYTES = 1024
    COMMAND_TIMEOUT_SECONDS = 12
    MAX_OUTPUT_BYTES = 16 * 1024

    Result = Struct.new(:ok, :lifecycle_state, :message, :details, keyword_init: true) do
      def to_h
        { "ok" => ok, "lifecycle_state" => lifecycle_state, "message" => message, "details" => details }
      end
    end

    def initialize(root:, env:, runner: BoundedCommandRunner.new, lease_store: nil, profile_registry: nil, systemctl_path: nil)
      @root = File.expand_path(root)
      @env = env.to_h
      @runner = runner
      @lease_store = lease_store || ModelRuntimeLeaseStore.new(root: @root)
      @profile_registry = profile_registry || ModelRuntimeProfileRegistry.new(root: @root, env: @env)
      @systemctl_path = systemctl_path || @runner.which("systemctl")
    end

    def run
      return failed("systemctl is unavailable") unless executable?(@systemctl_path)

      configuration = @profile_registry.configuration
      @lease_store.with_control_lock do
        selected_id = selected_profile_id(configuration)
        profiles = configuration.fetch("profiles")
        states = profiles.to_h { |profile| [profile.fetch("id"), service_state(profile.fetch("service"))] }
        return blocked("one or more model runtime service states are uncertain", selected_id, states) if states.value?("unknown")

        active_ids = states.select { |_id, state| state == "active" }.keys
        if active_ids == [selected_id]
          return complete("Selected model runtime is already active; no startup mutation was needed.", selected_id, states, started: false)
        end
        unless active_ids.empty?
          return blocked("a non-selected or conflicting model runtime is already active", selected_id, states)
        end

        selected = profiles.find { |profile| profile.fetch("id") == selected_id }
        started = run_systemctl("start", selected.fetch("service"))
        return failed("selected model runtime start command #{started.status}", "selected_profile_id" => selected_id, "states" => states, "command_exit_status" => started.exit_status) unless started.success?

        after = profiles.to_h { |profile| [profile.fetch("id"), service_state(profile.fetch("service"))] }
        return failed("selected model runtime did not become solely active", "selected_profile_id" => selected_id, "states" => after) unless after[selected_id] == "active" && after.count { |_id, state| state == "active" } == 1

        complete("Selected model runtime started.", selected_id, after, started: true)
      end
    rescue ModelRuntimeProfileRegistry::ConfigurationError, ModelRuntimeLeaseStore::IntegrityError => error
      blocked(error.message, nil, {})
    rescue ModelRuntimeLeaseStore::LockUnavailable
      blocked("model runtime control is busy", nil, {})
    end

    private

    def selected_profile_id(configuration)
      path = File.join(@root, ModelRuntimeLeaseStore::DEFAULT_DIRECTORY, "selected_profile.json")
      return configuration.fetch("default_profile") unless File.exist?(path) || File.symlink?(path)

      stat = File.lstat(path)
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection exceeds size limit" if stat.size > MAX_SELECTION_BYTES

      record = JSON.parse(File.binread(path, MAX_SELECTION_BYTES))
      id = record["profile_id"].to_s
      valid = record.keys == ["profile_id"] && configuration.fetch("profiles").any? { |profile| profile.fetch("id") == id }
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid" unless valid

      id
    rescue JSON::ParserError
      raise ModelRuntimeLeaseStore::IntegrityError, "model runtime selection is invalid"
    end

    def service_state(service)
      loaded = run_systemctl("show", service, "--property=LoadState", "--value", "--no-pager")
      return "unknown" unless loaded.success? && loaded.stdout.to_s.strip == "loaded"

      active = run_systemctl("is-active", service)
      value = active.stdout.to_s.strip
      return "active" if active.success? && value == "active"
      return "inactive" if value == "inactive"

      "unknown"
    end

    def run_systemctl(*arguments)
      @runner.run(@systemctl_path, "--user", *arguments, timeout_seconds: COMMAND_TIMEOUT_SECONDS, max_output_bytes: MAX_OUTPUT_BYTES)
    end

    def executable?(path)
      path && File.file?(path) && File.executable?(path) && !File.symlink?(path)
    end

    def complete(message, selected_id, states, started:)
      Result.new(ok: true, lifecycle_state: "complete", message: message, details: {
        "selected_profile_id" => selected_id, "profile_states" => states, "started" => started,
        "automatic_stop" => false, "retries" => 0
      })
    end

    def blocked(message, selected_id, states)
      Result.new(ok: false, lifecycle_state: "blocked_for_human_review", message: message, details: {
        "selected_profile_id" => selected_id, "profile_states" => states, "started" => false
      })
    end

    def failed(message, details = {})
      Result.new(ok: false, lifecycle_state: "failed", message: message, details: details.merge("started" => false))
    end
  end
end
