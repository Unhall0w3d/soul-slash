# frozen_string_literal: true

require_relative "conversation_capability_registry"
require_relative "conversation_orchestrator"

module SoulCore
  class Phase8DeclaredCapabilityBoundariesAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      registry = ConversationCapabilityRegistry.new
      catalog = registry.resolve("What host checks can you perform?")
      smart = registry.resolve("Can you inspect SMART health?")
      hardware_raid = registry.resolve("Check the hardware RAID controller state")
      scheduled_jobs = registry.resolve("Inspect scheduled jobs")
      support = registry.resolve("Do you support host system status?")
      action = registry.resolve("Check host system status")
      mdraid_action = registry.resolve("Check Linux MD RAID state")
      unrelated = registry.resolve("What about dinner tonight?")
      catalog_text = registry.render_catalog
      smart_text = registry.render(smart)

      orchestrator = ConversationOrchestrator.new(capability_registry: registry)
      catalog_plan = orchestrator.plan(
        message: "What host checks can you perform?",
        provider_available: false,
        recent_evidence: []
      )
      smart_plan = orchestrator.plan(
        message: "Can you inspect SMART health?",
        provider_available: false,
        recent_evidence: []
      )
      support_plan = orchestrator.plan(
        message: "Do you support host system status?",
        provider_available: false,
        recent_evidence: []
      )
      host_plan = orchestrator.plan(
        message: "Check host system status",
        provider_available: false,
        recent_evidence: []
      )
      mdraid_plan = orchestrator.plan(
        message: "Check Linux MD RAID state",
        provider_available: false,
        recent_evidence: []
      )

      source = File.read(
        File.join(@root, "lib/soul_core/conversation_capability_registry.rb"),
        encoding: "UTF-8"
      )

      verification = {
        "capability_ids_are_unique" =>
          registry.definitions.map(&:id).uniq.length == registry.definitions.length,
        "catalog_query_is_deterministic" => catalog.catalog?,
        "catalog_groups_declared_statuses" =>
          catalog_text.include?("Available now:") &&
          catalog_text.include?("Conditionally available:") &&
          catalog_text.include?("Not currently registered:"),
        "smart_has_specific_capability_identity" =>
          smart.gap? && smart.capability&.id == "host.smart_health",
        "hardware_raid_is_distinct_from_linux_mdraid" =>
          hardware_raid.gap? &&
          hardware_raid.capability&.id == "host.hardware_raid" &&
          mdraid_action.available_action? &&
          mdraid_action.capability&.id == "host.linux_mdraid",
        "scheduled_jobs_have_specific_boundary" =>
          scheduled_jobs.gap? && scheduled_jobs.capability&.id == "host.scheduled_jobs",
        "available_support_question_returns_info" =>
          support.info? && support.capability&.id == "host.system_status",
        "available_action_is_not_blocked" =>
          action.available_action? && action.capability&.tool_id == "host.system_status",
        "unrelated_prompt_is_not_captured" => !unrelated.matched?,
        "unavailable_rendering_rejects_model_substitution" =>
          smart_text.include?("No model-generated substitute") &&
          smart_text.include?("Capability ID: host.smart_health"),
        "legacy_host_gap_wording_remains_compatible" =>
          smart_text.include?("does not collect that deeper host category"),
        "orchestrator_routes_capability_catalog" =>
          catalog_plan.kind == "capability_catalog",
        "orchestrator_routes_specific_capability_gap" =>
          smart_plan.kind == "capability_gap" &&
          smart_plan.flags["requested_capability"] == "host.smart_health",
        "orchestrator_routes_available_capability_info" =>
          support_plan.kind == "capability_info",
        "available_host_action_reaches_registered_tool" =>
          host_plan.kind == "skill_only" && host_plan.tool_ids == ["host.system_status"],
        "conditional_mdraid_action_reaches_registered_tool" =>
          mdraid_plan.kind == "skill_only" && mdraid_plan.tool_ids == ["host.system_status"],
        "legacy_aggregate_host_gap_is_removed" =>
          !file_contains?("lib/soul_core/conversation_orchestrator.rb", "UNSUPPORTED_DEEP_HOST_PATTERNS") &&
          !file_contains?("lib/soul_core/conversation_runtime.rb", "host.system_status.extended"),
        "runtime_uses_declared_capability_registry" =>
          file_contains?("lib/soul_core/conversation_runtime.rb", "@capability_registry.render") &&
          file_contains?("lib/soul_core/conversation_runtime.rb", 'when "capability_catalog"'),
        "registry_does_not_call_models_or_execute_tools" =>
          !source.match?(/provider|model_client|\.chat\s*\(|system\s*\(|Open3|spawn|exec\s*\(/)
      }

      blockers = verification.filter_map do |name, passed|
        name.tr("_", " ").capitalize unless passed
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase8_declared_capability_boundaries",
        "milestone" => "conversational_soul",
        "phase" => 8,
        "status" => blockers.empty? ? "ready" : "blocked",
        "summary" => registry.summary(domain: "host"),
        "verification" => verification,
        "samples" => {
          "catalog" => catalog.to_h,
          "smart" => smart.to_h,
          "hardware_raid" => hardware_raid.to_h,
          "scheduled_jobs" => scheduled_jobs.to_h,
          "support" => support.to_h,
          "action" => action.to_h,
          "mdraid_action" => mdraid_action.to_h,
          "unrelated" => unrelated.to_h
        },
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 8 Declared Capability Boundaries Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "",
        "Capability summary"
      ]

      report.fetch("summary").each do |name, value|
        lines << "- #{name}: #{value}"
      end

      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |name, passed|
        lines << "- #{name}: #{passed}"
      end

      lines << ""
      lines << "Blockers"
      blockers = Array(report["blockers"])
      if blockers.empty?
        lines << "- None"
      else
        blockers.each { |blocker| lines << "- #{blocker}" }
      end

      lines.join("\n")
    end

    private

    def file_contains?(relative_path, text)
      path = File.join(@root, relative_path)
      File.exist?(path) && File.read(path, encoding: "UTF-8").include?(text)
    end
  end
end
