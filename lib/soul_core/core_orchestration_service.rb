# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "securerandom"
require_relative "model_runtime_control_service"
require_relative "dev_model_runtime_coordinator"
require_relative "memory_embedding_runtime_coordinator"

module SoulCore
  class CoreOrchestrationService
    SELECTION_SCHEMA = "soul.core_selection.v2"
    LEGACY_SELECTION_SCHEMA = "soul.core_selection.v1"
    SELECTION_PATH = File.join("Soul", "runtime", "model_runtime", "core_selection.json")
    MAX_SELECTION_BYTES = 4 * 1024
    CORE_DEFINITIONS = {
      "daily-chat" => { "id" => "daily", "label" => "Soul Core", "purpose" => "Gemma chat on AMD with NVIDIA available on demand" },
      "reserve-chat" => { "id" => "amd-free", "label" => "Soul-Lite Core", "purpose" => "Qwen chat on NVIDIA with AMD released to the Operator" },
      "music-chat" => { "id" => "music", "label" => "Creative Core", "purpose" => "Qwen chat on NVIDIA with AMD reserved for creative work" }
    }.freeze
    VIRTUAL_CORE_DEFINITIONS = [
      { "id" => "free", "label" => "Free Core", "purpose" => "No chat or development model loaded" },
      { "id" => "dev", "label" => "Dev Core", "purpose" => "Qwen chat on NVIDIA with GPT-OSS resident on AMD" }
    ].freeze
    CORE_ID = /\A[a-z][a-z0-9-]{0,39}\z/
    SHARED_INTENT_CORE_IDS = %w[amd-free music dev].freeze

    def initialize(root: Dir.pwd, runtime_control: nil, dev_runtime: nil, memory_runtime: nil, env: ENV)
      @root = File.expand_path(root)
      @runtime_control = runtime_control || ModelRuntimeControlService.new(root: @root, env: env)
      @dev_runtime = dev_runtime || DevModelRuntimeCoordinator.new(root: @root, env: env)
      @memory_runtime = memory_runtime
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

      source = current_core(observation)
      return virtual_core_preview(observation, source, core) if %w[free dev].include?(core.fetch("id")) || source&.fetch("id") == "dev"

      target = core.fetch("target_profile")
      if observation["active_profile_id"] == target.fetch("id")
        return shared_intent_preview(observation, core)
      end
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

      source = current_core(before)
      return execute_virtual_transition(before, source, core, target_profile_id, confirmation, expected_digest) if %w[free dev].include?(core.fetch("id")) || source&.fetch("id") == "dev"

      target = before.fetch("profiles").find { |profile| profile.fetch("id") == target_profile_id.to_s }
      return blocked("target profile does not belong to the requested Core") unless target && profile_belongs_to_core?(target, core.fetch("id"))
      return blocked("Core target changed; preview again") unless core.dig("target_profile", "id") == target.fetch("id")

      if before["active_profile_id"] == target.fetch("id")
        return execute_shared_intent_transition(
          core_id: core.fetch("id"),
          target_profile_id: target.fetch("id"),
          confirmation: confirmation,
          expected_digest: expected_digest
        )
      end

      action = before["active_profile_id"] ? "switch" : "load"
      result = @runtime_control.execute(
        action: action,
        profile_id: target.fetch("id"),
        confirmation: confirmation,
        expected_digest: expected_digest
      )
      return result unless result["ok"]

      remember_successful_profiles(before, result.fetch("data"), target, core.fetch("id"))
      memory = reconcile_memory_runtime(core.fetch("id"))
      success(project(result.fetch("data")).merge(
        "core_action" => "activate",
        "activated_core_id" => core.fetch("id"),
        "memory_embedding_reconciliation" => memory,
        "mutation" => "core_activated"
      ), mutation: "core_activated")
    rescue IntegrityError => error
      blocked(error.message)
    end

    class IntegrityError < StandardError; end

    private

    def project(observation, dev: nil)
      dev ||= dev_runtime_data
      cores = configured_cores(observation, dev: dev)
      current = current_core(observation, cores: cores, dev: dev)
      selected = cores.find { |core| core.fetch("selected") }
      observation.merge(
        "cores" => cores,
        "active_core_id" => current&.fetch("id", nil),
        "active_core_label" => current&.fetch("label", nil),
        "selected_core_id" => selected&.fetch("id", nil),
        "selected_core_label" => selected&.fetch("label", nil),
        "core_mode" => current&.fetch("id", nil) || "unloaded",
        "music_lane" => music_lane(current),
        "development_lane" => development_lane(current, status: dev),
        "memory_embedding_lane" => memory_runtime_status,
        "automatic_core_switch" => false
      )
    end

    def configured_cores(observation, dev: nil)
      profiles = observation.fetch("profiles")
      selection = read_selection(profiles: profiles)
      preferences = selection.fetch("profiles")
      active_intent = selection["active_core_id"]
      cores = CORE_DEFINITIONS.filter_map do |role, definition|
        members = profiles.select { |profile| profile.fetch("core_role") == role }
        members = profiles.select { |profile| profile.fetch("core_role") == "reserve-chat" } if role == "music-chat" && members.empty?
        next if members.empty?

        target = members.find { |profile| profile.fetch("active") } ||
                 members.find { |profile| profile.fetch("selected") } ||
                 members.find { |profile| profile.fetch("id") == preferences[definition.fetch("id")] } || members.first
        definition.merge(
          "role" => role,
          "profile_ids" => members.map { |profile| profile.fetch("id") },
          "target_profile" => target,
          "active" => false,
          "selected" => members.any? { |profile| profile.fetch("selected") },
          "can_activate" => can_activate_core?(
            definition.fetch("id"), target, observation, active_intent
          )
        )
      end
      reserve = cores.find { |core| core.fetch("id") == "amd-free" }
      dev ||= dev_runtime_data
      cores + VIRTUAL_CORE_DEFINITIONS.map do |definition|
        target = definition.fetch("id") == "dev" ? reserve&.fetch("target_profile", nil) : nil
        definition.merge(
          "role" => "virtual-#{definition.fetch('id')}",
          "profile_ids" => target ? [target.fetch("id")] : [],
          "target_profile" => target,
          "active" => false,
          "selected" => active_intent == definition.fetch("id"),
          "runtime_resident" => definition.fetch("id") == "dev" ? dev.fetch("resident", false) == true : false,
          "can_activate" => can_activate_virtual?(definition.fetch("id"), observation, target, dev)
        )
      end
    end

    def can_activate_core?(core_id, target, observation, active_intent)
      if target.fetch("active")
        source_intent = active_intent || core_id_for_profile(target)
        return shared_intent_pair?(source_intent, core_id) && shared_intent_blocker(observation, target).nil?
      end

      target.fetch("service_state") == "inactive" &&
        (observation.fetch("active_profile_count").zero? ? observation.fetch("can_load_profile", false) : observation.fetch("can_switch", false))
    end

    def current_core(observation, cores: nil, dev: nil)
      configured = cores || configured_cores(observation, dev: dev)
      profile_id = observation["active_profile_id"]
      preferred = read_selection(profiles: observation.fetch("profiles"))["active_core_id"]
      if preferred == "free" && observation.fetch("active_profile_count").zero?
        selected = configured.find { |core| core.fetch("id") == "free" }
        configured.each { |core| core["active"] = core.equal?(selected) }
        return selected
      end
      if preferred == "dev"
        selected = configured.find do |core|
          core.fetch("id") == "dev" && core.fetch("runtime_resident", false) == true && core.fetch("profile_ids").include?(profile_id)
        end
        if selected
          configured.each { |core| core["active"] = core.equal?(selected) }
          return selected
        end
      end
      candidates = configured.select do |core|
        core.fetch("profile_ids").include?(profile_id) &&
          (core.fetch("id") != "dev" || core.fetch("runtime_resident", false) == true)
      end
      selected = candidates.find { |core| core.fetch("id") == preferred } ||
                 candidates.find { |core| core.fetch("role") == observation.fetch("profiles").find { |profile| profile.fetch("id") == profile_id }&.fetch("core_role", nil) } ||
                 candidates.first
      configured.each { |core| core["active"] = core.equal?(selected) }
      selected
    end

    def core_for_id(observation, core_id, dev: nil)
      cores = configured_cores(observation, dev: dev)
      current_core(observation, cores: cores, dev: dev)
      cores.find { |core| core.fetch("id") == core_id.to_s }
    end

    def core_id_for_profile(profile)
      CORE_DEFINITIONS.dig(profile.fetch("core_role"), "id")
    end

    def profile_belongs_to_core?(profile, core_id)
      direct = core_id_for_profile(profile)
      direct == core_id || (%w[music dev].include?(core_id) && profile.fetch("core_role") == "reserve-chat")
    end

    def shared_intent_preview(observation, core)
      source = current_core(observation)
      target = core.fetch("target_profile")
      return awaiting("requested Core is already active", data: project(observation)) if source&.fetch("id", nil) == core.fetch("id")
      return blocked("shared chat profile cannot represent this Core transition") unless shared_intent_pair?(source&.fetch("id", nil), core.fetch("id"))

      blocker = shared_intent_blocker(observation, target)
      return blocked(blocker) if blocker

      scope = shared_intent_scope(observation, source, core, target)
      success(observation.merge(
        "action" => "core_intent",
        "target_profile" => target,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => shared_intent_confirmation(core.fetch("id")),
        "preview_scope" => scope,
        "core_action" => "activate",
        "source_core" => source,
        "target_core" => core,
        "cores" => project(observation).fetch("cores"),
        "service_mutation_required" => false,
        "mutation" => "none"
      ))
    end

    def execute_shared_intent_transition(core_id:, target_profile_id:, confirmation:, expected_digest:)
      # Capture Dev status before entering the model-runtime control lock. Dev
      # status reads the shared lease store, so refreshing it while that same
      # non-reentrant lock is held would falsely report runtime control busy.
      dev = dev_runtime_data
      @runtime_control.with_controlled_observation do |before|
        core = core_for_id(before, core_id, dev: dev)
        return awaiting("known configured core_id is required") unless core
        target = before.fetch("profiles").find { |profile| profile.fetch("id") == target_profile_id }
        return blocked("Core target changed; preview again") unless target && core.dig("target_profile", "id") == target.fetch("id")

        source = current_core(before, dev: dev)
        return awaiting("requested Core is already active", data: project(before, dev: dev)) if source&.fetch("id", nil) == core.fetch("id")
        return blocked("shared chat profile cannot represent this Core transition") unless shared_intent_pair?(source&.fetch("id", nil), core.fetch("id"))

        blocker = shared_intent_blocker(before, target)
        return blocked(blocker) if blocker
        return blocked("exact Core intent confirmation did not match") unless confirmation == shared_intent_confirmation(core.fetch("id"))

        scope = shared_intent_scope(before, source, core, target)
        return blocked("Core intent state changed; preview again") unless secure_compare(expected_digest, digest(scope))

        selection = read_selection(profiles: before.fetch("profiles"))
        preferences = selection.fetch("profiles")
        preferences[source.fetch("id")] = target.fetch("id")
        preferences[core.fetch("id")] = target.fetch("id")
        write_selection({ "active_core_id" => core.fetch("id"), "profiles" => preferences }, profiles: before.fetch("profiles"))
        memory = reconcile_memory_runtime(core.fetch("id"))
        success(project(before, dev: dev).merge(
          "core_action" => "activate",
          "activated_core_id" => core.fetch("id"),
          "service_mutation_required" => memory.fetch("changed", false),
          "memory_embedding_reconciliation" => memory,
          "mutation" => "core_intent_changed"
        ), mutation: "core_intent_changed")
      end
    end

    def shared_intent_pair?(source_core_id, target_core_id)
      source_core_id != target_core_id && SHARED_INTENT_CORE_IDS.include?(source_core_id) && SHARED_INTENT_CORE_IDS.include?(target_core_id)
    end

    def shared_intent_blocker(observation, target)
      return "multiple model runtime profiles are active; resolve the conflict manually" if observation["profile_conflict"]
      return "exactly one shared chat profile must be active" unless observation["active_profile_count"] == 1
      return "shared chat profile changed; preview again" unless observation["active_profile_id"] == target.fetch("id")
      return "active model work must complete or be canceled before the Core intent changes" unless observation["active_work_count"].zero?
      return "runtime activity state is unavailable; safe idle state cannot be established" unless observation["idle_certain"]

      nil
    end

    def shared_intent_scope(observation, source, target_core, target_profile)
      {
        "action" => "core_intent",
        "source_core_id" => source.fetch("id"),
        "target_core_id" => target_core.fetch("id"),
        "shared_profile_id" => target_profile.fetch("id"),
        "shared_service" => target_profile.fetch("service"),
        "profile_states" => observation.fetch("profiles").map { |profile| profile.slice("id", "service", "service_state") },
        "active_work_count" => observation.fetch("active_work_count"),
        "active_lease_ids" => observation.fetch("active_leases", []).map { |lease| lease["lease_id"] }.sort,
        "idle_certain" => observation.fetch("idle_certain"),
        "service_mutation_required" => false
      }
    end

    def shared_intent_confirmation(core_id)
      "ACTIVATE_#{core_id.upcase.tr('-', '_')}_CORE"
    end

    def can_activate_virtual?(core_id, observation, target, dev)
      return false if current_core_id_hint(observation) == core_id
      return false unless observation.fetch("active_work_count").zero?
      return false if observation.fetch("active_profile_count").positive? && !observation.fetch("idle_certain")
      return dev.fetch("active_work_count", 0).to_i.zero? if core_id == "free"

      target && target.fetch("service_state") != "unavailable" &&
        %w[inactive active].include?(dev.fetch("service_state", "unavailable")) &&
        dev.fetch("active_work_count", 0).to_i.zero?
    end

    def current_core_id_hint(observation)
      selection = read_selection(profiles: observation.fetch("profiles"))
      preferred = selection["active_core_id"]
      return "free" if preferred == "free" && observation.fetch("active_profile_count").zero?
      return "dev" if preferred == "dev" && observation.fetch("active_profile_count") == 1 && dev_runtime_data.fetch("resident", false) == true
      profile = observation.fetch("profiles").find { |item| item.fetch("id") == observation["active_profile_id"] }
      return preferred if profile && %w[amd-free music].include?(preferred) && profile.fetch("core_role") == "reserve-chat"
      profile ? core_id_for_profile(profile) : nil
    end

    def virtual_core_preview(observation, source, target_core)
      source_id = source&.fetch("id", nil)
      target_id = target_core.fetch("id")
      return awaiting("requested Core is already active", data: project(observation)) if source_id == target_id

      blocker = virtual_transition_blocker(observation, source_id, target_id)
      return blocked(blocker) if blocker

      target_profile = virtual_target_profile(observation, target_core)
      return blocked("target Core has no configured chat profile") unless target_profile
      scope = virtual_transition_scope(observation, source_id, target_id, target_profile)
      success(observation.merge(
        "action" => "core_composite",
        "target_profile" => target_profile,
        "expected_digest" => digest(scope),
        "confirmation_phrase" => shared_intent_confirmation(target_id),
        "preview_scope" => scope,
        "core_action" => "activate",
        "source_core" => source,
        "target_core" => target_core,
        "cores" => project(observation).fetch("cores"),
        "service_mutation_required" => scope.fetch("runtime_action") != "none" || source_id == "dev" || target_id == "dev",
        "mutation" => "none"
      ))
    end

    def execute_virtual_transition(before, source, target_core, target_profile_id, confirmation, expected_digest)
      source_id = source&.fetch("id", nil)
      target_id = target_core.fetch("id")
      return awaiting("requested Core is already active", data: project(before)) if source_id == target_id
      return blocked("exact Core confirmation did not match") unless confirmation == shared_intent_confirmation(target_id)

      blocker = virtual_transition_blocker(before, source_id, target_id)
      return blocked(blocker) if blocker
      target_profile = virtual_target_profile(before, target_core)
      return blocked("target Core has no configured chat profile") unless target_profile
      return blocked("Core target changed; preview again") unless target_profile.fetch("id") == target_profile_id.to_s
      scope = virtual_transition_scope(before, source_id, target_id, target_profile)
      return blocked("Core state changed; preview again") unless secure_compare(expected_digest, digest(scope))

      if target_id == "free" && @memory_runtime
        memory = @memory_runtime.reconcile(core_id: "free")
        return memory unless memory["ok"]
      end

      source_profile_id = before["active_profile_id"]
      dev_stopped = false
      runtime_changed = false
      if source_id == "dev" && target_id != "dev"
        stopped = @dev_runtime.deactivate_selected
        return stopped unless stopped["ok"]
        dev_stopped = true
      end

      action = scope.fetch("runtime_action")
      if action != "none"
        changed = automatic_runtime_transition(action, target_profile.fetch("id"))
        unless changed["ok"]
          @dev_runtime.activate_selected if dev_stopped
          return changed
        end
        runtime_changed = true
      end

      if target_id == "dev"
        activated = @dev_runtime.activate_selected
        unless activated["ok"]
          automatic_runtime_transition(source_profile_id ? "switch" : "unload", source_profile_id) if runtime_changed
          return activated
        end
      end

      profiles = @runtime_control.status.dig("data", "profiles") || before.fetch("profiles")
      selection = read_selection(profiles: profiles)
      preferences = selection.fetch("profiles")
      preferences[source_id] = source_profile_id if source_id && source_profile_id && source_id != "free"
      preferences[target_id] = target_profile.fetch("id") unless target_id == "free"
      write_selection({ "active_core_id" => target_id, "profiles" => preferences }, profiles: profiles)
      current = @runtime_control.status
      return current unless current["ok"]
      memory = target_id == "free" ? memory_runtime_status : reconcile_memory_runtime(target_id)
      success(project(current.fetch("data")).merge(
        "core_action" => "activate",
        "activated_core_id" => target_id,
        "source_core_id" => source_id,
        "service_mutation_required" => scope.fetch("runtime_action") != "none" || source_id == "dev" || target_id == "dev",
        "memory_embedding_reconciliation" => memory,
        "mutation" => "core_composite_changed"
      ), mutation: "core_composite_changed")
    rescue IntegrityError => error
      blocked(error.message)
    end

    def memory_runtime_status
      return { "available" => false, "service_state" => "unmanaged", "resident" => false, "context_length" => 1_024 } unless @memory_runtime

      result = @memory_runtime.status
      result.fetch("data", {}).merge("available" => result["ok"] == true, "message" => result["message"])
    rescue StandardError => error
      { "available" => false, "service_state" => "unknown", "resident" => false, "context_length" => 1_024,
        "message" => "Embedding runtime status failed safely: #{error.class}" }
    end

    def reconcile_memory_runtime(core_id)
      return memory_runtime_status unless @memory_runtime

      result = @memory_runtime.reconcile(core_id: core_id)
      result.fetch("data", {}).merge("available" => result["ok"] == true, "message" => result["message"])
    rescue StandardError => error
      { "available" => false, "service_state" => "unknown", "changed" => false,
        "message" => "Embedding runtime reconciliation failed safely: #{error.class}" }
    end

    def virtual_transition_blocker(observation, source_id, target_id)
      return "multiple model runtime profiles are active; resolve the conflict manually" if observation["profile_conflict"]
      return "active model work must complete or be canceled before the Core changes" unless observation.fetch("active_work_count").zero?
      if observation.fetch("active_profile_count").positive? && !observation.fetch("idle_certain")
        return "runtime activity state is unavailable; safe idle state cannot be established"
      end
      dev = dev_runtime_data
      return "Dev work must reach a terminal state before the Core changes" unless dev.fetch("active_work_count", 0).to_i.zero?
      if target_id == "dev"
        return "Dev runtime unit is not installed exactly" if dev.fetch("service_state", "unavailable") == "unavailable"
        return "Creative Core must be idle before Dev Core activation" if source_id == "music" && observation.fetch("active_work_count").positive?
      end
      nil
    end

    def virtual_target_profile(observation, target_core)
      if target_core.fetch("id") == "free"
        source = observation.fetch("profiles").find { |profile| profile.fetch("id") == observation["active_profile_id"] }
        source&.merge("label" => "No model", "model_name" => "No model", "accelerator" => "Released")
      else
        target_core["target_profile"]
      end
    end

    def virtual_transition_scope(observation, source_id, target_id, target_profile)
      action = if target_id == "free"
                 observation.fetch("active_profile_count").positive? ? "unload" : "none"
               elsif observation.fetch("active_profile_count").zero?
                 "load"
               elsif observation["active_profile_id"] == target_profile.fetch("id")
                 "none"
               else
                 "switch"
               end
      {
        "action" => "core_composite",
        "source_core_id" => source_id,
        "target_core_id" => target_id,
        "target_profile_id" => target_profile.fetch("id"),
        "runtime_action" => action,
        "active_profile_id" => observation["active_profile_id"],
        "active_work_count" => observation.fetch("active_work_count"),
        "active_lease_ids" => observation.fetch("active_leases", []).map { |lease| lease["lease_id"] }.sort,
        "dev_runtime" => dev_runtime_data.slice("service", "service_state", "loaded", "active_work_count", "expected_digest"),
        "idle_certain" => observation.fetch("idle_certain")
      }
    end

    def automatic_runtime_transition(action, profile_id)
      preview = @runtime_control.preview(action: action, profile_id: profile_id)
      return preview unless preview["ok"]
      data = preview.fetch("data")
      @runtime_control.execute(
        action: action, profile_id: profile_id,
        confirmation: data.fetch("confirmation_phrase"),
        expected_digest: data.fetch("expected_digest")
      )
    end

    def dev_runtime_data
      envelope = @dev_runtime.status
      envelope["ok"] ? envelope.fetch("data") : {
        "service" => DevModelRuntimeCoordinator::UNIT_NAME,
        "service_state" => "unavailable", "loaded" => false,
        "active_work_count" => 0, "expected_digest" => DevModelRuntimeCoordinator::DEFAULT_DIGEST
      }
    end

    def development_conflict(current)
      case current&.fetch("id", nil)
      when "dev" then nil
      when "music" then "Creative Core owns the AMD generation lane"
      when "free" then "Select Dev Core before development work"
      else "Available through one bounded scoped Dev transaction"
      end
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
    end

    def canonicalize(value)
      case value
      when Hash then value.keys.map(&:to_s).sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
      when Array then value.map { |item| canonicalize(item) }
      else value
      end
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, pair| difference | (pair[0] ^ pair[1]) }.zero?
    end

    def remember_successful_profiles(before, after, target, target_core_id)
      profiles = after.fetch("profiles")
      selection = read_selection(profiles: profiles)
      preferences = selection.fetch("profiles")
      source_id = before["active_profile_id"]
      source = before.fetch("profiles").find { |profile| profile.fetch("id") == source_id }
      source_core_id = current_core(before)&.fetch("id") if source
      preferences[source_core_id] = source.fetch("id") if source_core_id
      preferences[target_core_id] = target.fetch("id") if target_core_id
      write_selection({ "active_core_id" => target_core_id, "profiles" => preferences }, profiles: profiles)
    end

    def read_selection(profiles:)
      return { "active_core_id" => nil, "profiles" => {} } unless File.exist?(@selection_path) || File.symlink?(@selection_path)

      stat = File.lstat(@selection_path)
      raise IntegrityError, "Core selection must be a regular non-symlink file" unless stat.file? && !stat.symlink?
      raise IntegrityError, "Core selection exceeds size limit" if stat.size > MAX_SELECTION_BYTES

      record = JSON.parse(File.binread(@selection_path, MAX_SELECTION_BYTES))
      valid_legacy = record.is_a?(Hash) && record.keys.sort == %w[profiles schema_version] && record["schema_version"] == LEGACY_SELECTION_SCHEMA
      valid_current = record.is_a?(Hash) && record.keys.sort == %w[active_core_id profiles schema_version] && record["schema_version"] == SELECTION_SCHEMA
      raise IntegrityError, "Core selection document is invalid" unless valid_legacy || valid_current
      values = record["profiles"]
      maximum_preferences = CORE_DEFINITIONS.length + VIRTUAL_CORE_DEFINITIONS.length
      raise IntegrityError, "Core selection profiles are invalid" unless values.is_a?(Hash) && values.length <= maximum_preferences

      validated = values.each_with_object({}) do |(core_id, profile_id), memo|
        raise IntegrityError, "Core selection identifier is invalid" unless core_id.is_a?(String) && core_id.match?(CORE_ID)
        profile = profiles.find { |item| item.fetch("id") == profile_id.to_s }
        raise IntegrityError, "Core selection profile is invalid" unless profile && profile_belongs_to_core?(profile, core_id)
        memo[core_id] = profile.fetch("id")
      end
      active_core_id = valid_current ? record["active_core_id"] : nil
      known_ids = CORE_DEFINITIONS.values.map { |definition| definition.fetch("id") } + VIRTUAL_CORE_DEFINITIONS.map { |definition| definition.fetch("id") }
      raise IntegrityError, "active Core selection is invalid" unless active_core_id.nil? || (active_core_id.is_a?(String) && active_core_id.match?(CORE_ID) && known_ids.include?(active_core_id))
      { "active_core_id" => active_core_id, "profiles" => validated }
    rescue JSON::ParserError
      raise IntegrityError, "Core selection document is invalid"
    end

    def write_selection(selection, profiles:)
      active_core_id = selection.fetch("active_core_id")
      validated = selection.fetch("profiles").each_with_object({}) do |(core_id, profile_id), memo|
        profile = profiles.find { |item| item.fetch("id") == profile_id }
        raise IntegrityError, "Core selection profile is invalid" unless profile && profile_belongs_to_core?(profile, core_id)
        memo[core_id] = profile_id
      end
      directory = File.dirname(@selection_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      stat = File.lstat(directory)
      raise IntegrityError, "Core selection directory must not be a symlink" unless stat.directory? && !stat.symlink?
      File.chmod(0o700, directory)
      body = JSON.generate("schema_version" => SELECTION_SCHEMA, "active_core_id" => active_core_id, "profiles" => validated.sort.to_h) + "\n"
      raise IntegrityError, "Core selection exceeds size limit" if body.bytesize > MAX_SELECTION_BYTES
      temporary = "#{@selection_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(body); file.flush; file.fsync }
      File.rename(temporary, @selection_path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def music_lane(current)
      case current&.fetch("id", nil)
      when "music"
        { "engine" => "ACE-Step 1.5 4B LM / 2B Turbo Q8_0", "accelerator" => "AMD Vulkan", "available_in_active_core" => true,
          "residency" => "foreground_on_demand", "duration_range_seconds" => { "minimum" => 30, "maximum" => 300 },
          "fixed_durations" => [600], "conflict" => nil }.compact
      when "amd-free"
        { "engine" => "ACE-Step 1.5", "accelerator" => "NVIDIA CUDA", "available_in_active_core" => false,
          "conflict" => "NVIDIA chat is active and AMD is reserved for the Operator" }
      else
        { "engine" => "ACE-Step 1.5 4B LM / 2B Turbo Q8_0", "accelerator" => "AMD Vulkan", "available_in_active_core" => false,
          "conflict" => "Activate Creative Core to release AMD and preserve chat on NVIDIA" }
      end
    end

    def development_lane(current, status: nil)
      status ||= dev_runtime_data
      {
        "engine" => "GPT-OSS 20B MXFP4",
        "accelerator" => "AMD Vulkan",
        "available_in_active_core" => current&.fetch("id", nil) == "dev",
        "residency" => current&.fetch("id", nil) == "dev" ? (status["resident"] ? "resident" : "on_demand") : "scoped_on_demand",
        "service_state" => status["service_state"],
        "loaded" => status["loaded"] == true,
        "active_work_count" => status["active_work_count"].to_i,
        "conflict" => development_conflict(current)
      }.compact
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
