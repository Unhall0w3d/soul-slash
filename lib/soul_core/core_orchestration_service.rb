# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require_relative "model_runtime_control_service"

module SoulCore
  class CoreOrchestrationService
    SELECTION_SCHEMA = "soul.core_selection.v1"
    SELECTION_PATH = File.join("Soul", "runtime", "model_runtime", "core_selection.json")
    MAX_SELECTION_BYTES = 4 * 1024
    CORE_DEFINITIONS = {
      "daily-chat" => { "id" => "daily", "label" => "Daily Core", "purpose" => "AMD chat with NVIDIA available on demand" },
      "reserve-chat" => { "id" => "amd-free", "label" => "AMD-Free Core", "purpose" => "NVIDIA chat with AMD released to the Operator" },
      "music-chat" => { "id" => "music", "label" => "Music Core", "purpose" => "Dedicated music-planning chat" }
    }.freeze
    CORE_ID = /\A[a-z][a-z0-9-]{0,39}\z/

    def initialize(root: Dir.pwd, runtime_control: nil, env: ENV)
      @root = File.expand_path(root)
      @runtime_control = runtime_control || ModelRuntimeControlService.new(root: @root, env: env)
      @selection_path = File.expand_path(SELECTION_PATH, @root)
      raise ArgumentError, "Core selection path must remain inside the project root" unless within?(@selection_path, @root)
    end

    def status
      runtime = @runtime_control.status
      return runtime unless runtime["ok"]

      success(project(runtime.fetch("data")))
    rescue IntegrityError => error
      blocked(error.message)
    end

    def preview(core_id:)
      runtime = @runtime_control.status
      return runtime unless runtime["ok"]

      observation = runtime.fetch("data")
      core = core_for_id(observation, core_id)
      return awaiting("known configured core_id is required") unless core
      return awaiting("requested Core is already active", data: project(observation)) if core.fetch("active")

      target = core.fetch("target_profile")
      action = observation["active_profile_id"] ? "switch" : "load"
      preview = @runtime_control.preview(action: action, profile_id: target.fetch("id"))
      return preview unless preview["ok"]

      data = preview.fetch("data").merge(
        "core_action" => "activate",
        "source_core" => current_core(observation),
        "target_core" => core,
        "cores" => project(observation).fetch("cores")
      )
      success(data)
    rescue IntegrityError => error
      blocked(error.message)
    end

    def execute(core_id:, target_profile_id:, confirmation:, expected_digest:)
      return awaiting("target_profile_id, confirmation, and preview digest are required") if target_profile_id.to_s.empty? || confirmation.to_s.empty? || expected_digest.to_s.empty?

      before_envelope = @runtime_control.status
      return before_envelope unless before_envelope["ok"]
      before = before_envelope.fetch("data")
      core = core_for_id(before, core_id)
      return awaiting("known configured core_id is required") unless core

      target = before.fetch("profiles").find { |profile| profile.fetch("id") == target_profile_id.to_s }
      return blocked("target profile does not belong to the requested Core") unless target && core_id_for_profile(target) == core.fetch("id")
      return blocked("Core target changed; preview again") unless core.dig("target_profile", "id") == target.fetch("id")

      action = before["active_profile_id"] ? "switch" : "load"
      result = @runtime_control.execute(
        action: action,
        profile_id: target.fetch("id"),
        confirmation: confirmation,
        expected_digest: expected_digest
      )
      return result unless result["ok"]

      remember_successful_profiles(before, result.fetch("data"), target)
      success(project(result.fetch("data")).merge(
        "core_action" => "activate",
        "activated_core_id" => core.fetch("id"),
        "mutation" => "core_activated"
      ), mutation: "core_activated")
    rescue IntegrityError => error
      blocked(error.message)
    end

    class IntegrityError < StandardError; end

    private

    def project(observation)
      cores = configured_cores(observation)
      current = cores.find { |core| core.fetch("active") }
      selected = cores.find { |core| core.fetch("selected") }
      observation.merge(
        "cores" => cores,
        "active_core_id" => current&.fetch("id", nil),
        "active_core_label" => current&.fetch("label", nil),
        "selected_core_id" => selected&.fetch("id", nil),
        "selected_core_label" => selected&.fetch("label", nil),
        "core_mode" => current&.fetch("id", nil) || "unloaded",
        "music_lane" => {
          "engine" => "ACE-Step 1.5",
          "accelerator" => "NVIDIA CUDA",
          "available_in_active_core" => current&.fetch("id", nil) != "amd-free",
          "conflict" => current&.fetch("id", nil) == "amd-free" ? "NVIDIA chat must be released before music generation" : nil
        }.compact,
        "automatic_core_switch" => false
      )
    end

    def configured_cores(observation)
      profiles = observation.fetch("profiles")
      preferences = read_preferences(profiles)
      CORE_DEFINITIONS.filter_map do |role, definition|
        members = profiles.select { |profile| profile.fetch("core_role") == role }
        next if members.empty?

        target = members.find { |profile| profile.fetch("active") } ||
                 members.find { |profile| profile.fetch("selected") } ||
                 members.find { |profile| profile.fetch("id") == preferences[definition.fetch("id")] } || members.first
        definition.merge(
          "role" => role,
          "profile_ids" => members.map { |profile| profile.fetch("id") },
          "target_profile" => target,
          "active" => members.any? { |profile| profile.fetch("active") },
          "selected" => members.any? { |profile| profile.fetch("selected") },
          "can_activate" => !members.any? { |profile| profile.fetch("active") } && target.fetch("service_state") == "inactive" &&
            (observation.fetch("active_profile_count").zero? ? observation.fetch("can_load_profile", false) : observation.fetch("can_switch", false))
        )
      end
    end

    def current_core(observation, cores: nil)
      configured = cores || configured_cores(observation)
      profile_id = observation["active_profile_id"]
      configured.find { |core| core.fetch("profile_ids").include?(profile_id) }
    end

    def core_for_id(observation, core_id)
      configured_cores(observation).find { |core| core.fetch("id") == core_id.to_s }
    end

    def core_id_for_profile(profile)
      CORE_DEFINITIONS.dig(profile.fetch("core_role"), "id")
    end

    def remember_successful_profiles(before, after, target)
      profiles = after.fetch("profiles")
      preferences = read_preferences(profiles)
      source_id = before["active_profile_id"]
      source = before.fetch("profiles").find { |profile| profile.fetch("id") == source_id }
      source_core_id = core_id_for_profile(source) if source
      preferences[source_core_id] = source.fetch("id") if source_core_id
      target_core_id = core_id_for_profile(target)
      preferences[target_core_id] = target.fetch("id") if target_core_id
      write_preferences(preferences, profiles)
    end

    def read_preferences(profiles)
      return {} unless File.exist?(@selection_path) || File.symlink?(@selection_path)

      stat = File.lstat(@selection_path)
      raise IntegrityError, "Core selection must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise IntegrityError, "Core selection exceeds size limit" if stat.size > MAX_SELECTION_BYTES

      record = JSON.parse(File.binread(@selection_path, MAX_SELECTION_BYTES))
      raise IntegrityError, "Core selection document is invalid" unless record.is_a?(Hash) && record.keys.sort == %w[profiles schema_version] && record["schema_version"] == SELECTION_SCHEMA
      values = record["profiles"]
      raise IntegrityError, "Core selection profiles are invalid" unless values.is_a?(Hash) && values.length <= CORE_DEFINITIONS.length

      values.each_with_object({}) do |(core_id, profile_id), memo|
        raise IntegrityError, "Core selection identifier is invalid" unless core_id.is_a?(String) && core_id.match?(CORE_ID)
        profile = profiles.find { |item| item.fetch("id") == profile_id.to_s }
        raise IntegrityError, "Core selection profile is invalid" unless profile && core_id_for_profile(profile) == core_id
        memo[core_id] = profile.fetch("id")
      end
    rescue JSON::ParserError
      raise IntegrityError, "Core selection document is invalid"
    end

    def write_preferences(preferences, profiles)
      validated = preferences.each_with_object({}) do |(core_id, profile_id), memo|
        profile = profiles.find { |item| item.fetch("id") == profile_id }
        raise IntegrityError, "Core selection profile is invalid" unless profile && core_id_for_profile(profile) == core_id
        memo[core_id] = profile_id
      end
      directory = File.dirname(@selection_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      stat = File.lstat(directory)
      raise IntegrityError, "Core selection directory must not be a symlink" unless stat.directory? && !stat.symlink?
      File.chmod(0o700, directory)
      body = JSON.generate("schema_version" => SELECTION_SCHEMA, "profiles" => validated.sort.to_h) + "\n"
      raise IntegrityError, "Core selection exceeds size limit" if body.bytesize > MAX_SELECTION_BYTES
      temporary = "#{@selection_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body); file.flush; file.fsync }
      File.rename(temporary, @selection_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def within?(path, parent)
      path == parent || path.start_with?(parent + File::SEPARATOR)
    end

    def success(data, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason, data: {})
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => data, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => {}, "mutation" => "none" }
    end
  end
end
