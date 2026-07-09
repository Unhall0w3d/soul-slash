# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "skill_registry"
require_relative "workflow_registry"
require_relative "workflow_handler_registry"
require_relative "workflow_contract_validator"
require_relative "model_runtime_assessor"

module SoulCore
  class CapabilityMatrix
    OUTPUT_PATH = "Soul/runtime/capability_matrix.json"

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess(persist: false)
      skills = safe_skill_registry
      workflows = safe_workflow_registry
      handlers = safe_handler_registry
      contracts = safe_contract_health
      models = safe_model_runtime

      capabilities = build_capabilities(
        skills: skills,
        workflows: workflows,
        handlers: handlers,
        contracts: contracts,
        models: models
      )

      report = {
        "status" => "ok",
        "assessment" => "capability_matrix",
        "generated_at" => Time.now.iso8601,
        "read_only" => !persist,
        "persist_requested" => persist,
        "output_path" => persist ? File.join(@root, OUTPUT_PATH) : nil,
        "summary" => summarize(capabilities),
        "sources" => {
          "skills" => skills,
          "workflows" => workflows,
          "handlers" => handlers,
          "workflow_contracts" => contracts,
          "model_runtime" => models
        },
        "capabilities" => capabilities,
        "recommendations" => recommendations(capabilities),
        "verification" => {
          "no_skills_modified" => true,
          "no_workflows_modified" => true,
          "no_models_downloaded" => true,
          "only_persisted_when_requested" => persist
        }
      }

      persist_report(report) if persist
      report
    end

    def render(report)
      lines = []
      lines << "Soul Capability Matrix"
      lines << "Generated: #{report['generated_at']}"
      lines << "Persisted: #{report['persist_requested']}"
      lines << ""

      summary = report.fetch("summary")
      lines << "Summary"
      lines << "- Available: #{summary['available']}"
      lines << "- Partial: #{summary['partial']}"
      lines << "- Missing: #{summary['missing']}"
      lines << "- Blocked: #{summary['blocked']}"
      lines << ""

      lines << "Capabilities"
      report.fetch("capabilities").each do |name, data|
        lines << "- #{name}: #{data['status']}"
        lines << "  #{data['detail']}"
        if data["missing"].is_a?(Array) && data["missing"].any?
          lines << "  Missing: #{data['missing'].join(', ')}"
        end
      end
      lines << ""

      lines << "Recommendations"
      if report.fetch("recommendations").empty?
        lines << "- No recommendations generated."
      else
        report.fetch("recommendations").each_with_index do |rec, index|
          lines << "#{index + 1}. [#{rec['severity'].upcase}] #{rec['title']}"
          lines << "   #{rec['detail']}"
          lines << "   Recommended action: #{rec['action']}"
        end
      end

      if report["output_path"]
        lines << ""
        lines << "Output: #{report['output_path']}"
      end

      lines.join("\n")
    end

    private

    def safe_skill_registry
      registry = SkillRegistry.new
      data = registry.to_h
      {
        "status" => "ok",
        "items" => data,
        "names" => extract_skill_names(data)
      }
    rescue StandardError => e
      {"status" => "error", "error" => "#{e.class}: #{e.message}", "items" => {}, "names" => []}
    end

    def extract_skill_names(data)
      case data
      when Hash
        if data["skills"].is_a?(Array)
          data["skills"].map { |item| item.is_a?(Hash) ? item["name"] : item }.compact
        else
          data.keys
        end
      else
        []
      end
    end

    def safe_workflow_registry
      registry = WorkflowRegistry.new
      definitions = registry.definitions.map do |definition|
        {
          "intent" => definition.intent,
          "description" => definition.description,
          "requires_confirmation" => definition.respond_to?(:requires_confirmation) ? definition.requires_confirmation : nil,
          "write_capable" => definition.respond_to?(:write_capable) ? definition.write_capable : nil
        }
      end

      {"status" => "ok", "definitions" => definitions, "intents" => definitions.map { |item| item["intent"] }}
    rescue StandardError => e
      {"status" => "error", "error" => "#{e.class}: #{e.message}", "definitions" => [], "intents" => []}
    end

    def safe_handler_registry
      registry = WorkflowHandlerRegistry.new
      handlers = registry.handlers.map do |handler|
        {
          "class" => handler.class.name,
          "intent" => handler.intent,
          "match_intent" => handler.respond_to?(:match_intent),
          "run" => handler.respond_to?(:run),
          "respond" => handler.respond_to?(:respond),
          "responds_to_status" => handler.respond_to?(:responds_to_status?)
        }
      end

      {"status" => "ok", "handlers" => handlers, "intents" => handlers.map { |item| item["intent"] }}
    rescue StandardError => e
      {"status" => "error", "error" => "#{e.class}: #{e.message}", "handlers" => [], "intents" => []}
    end

    def safe_contract_health
      WorkflowContractValidator.new.health_report(WorkflowHandlerRegistry.new)
    rescue StandardError => e
      {"valid" => false, "error" => "#{e.class}: #{e.message}"}
    end

    def safe_model_runtime
      ModelRuntimeAssessor.new(root: @root).assess(include_processes: false)
    rescue StandardError => e
      {"status" => "error", "error" => "#{e.class}: #{e.message}"}
    end

    def build_capabilities(skills:, workflows:, handlers:, contracts:, models:)
      skill_names = Array(skills["names"])
      workflow_intents = Array(workflows["intents"])
      handler_intents = Array(handlers["intents"])
      model_endpoint_reachable = !!models.dig("endpoints", "llama_cpp_openai", "reachable") || !!models.dig("endpoints", "ollama", "reachable")
      contract_valid = contracts["valid"] == true

      {
        "youtube_playback" => capability(
          status: workflow_intents.include?("youtube.play") && handler_intents.include?("youtube.play") && skill_names.any? { |n| n.to_s.include?("youtube") } ? "available" : "partial",
          detail: "YouTube playback is available when the youtube workflow, handler, resolver skill, and launcher skill are registered.",
          provides: ["natural_language_youtube_request", "candidate_resolution", "confirmation_gate", "browser_launch"],
          current_support: ["workflow:youtube.play", "handler:youtube.play", "skills:youtube.*"],
          missing: missing(["workflow:youtube.play", "handler:youtube.play"], workflow_intents, handler_intents)
        ),
        "workflow_contract_enforcement" => capability(
          status: contract_valid ? "available" : "blocked",
          detail: "Workflow handlers are validated at startup and exposed through doctor output.",
          provides: ["startup_validation", "doctor_report", "handler_contracts"],
          current_support: ["WorkflowContractValidator", "WorkflowHandlerRegistry"],
          missing: contract_valid ? [] : ["valid_workflow_contracts"]
        ),
        "environment_assessment" => capability(
          status: "available",
          detail: "Soul can inspect local OS, package managers, runtimes, repo state, and read-only update/orphan status.",
          provides: ["runtime_inventory", "package_manager_detection", "repo_health", "read_only_update_checks"],
          current_support: ["EnvironmentAssessor", "PackageManagerAssessor", "RuntimeAssessor", "SoulProjectAssessor"],
          missing: []
        ),
        "model_runtime_assessment" => capability(
          status: "available",
          detail: "Soul can inspect local model endpoints, GPU telemetry hooks, local model file paths, and capability gaps.",
          provides: ["llama_cpp_endpoint_check", "ollama_endpoint_check", "gpu_telemetry_check", "capability_gap_seed"],
          current_support: ["ModelRuntimeAssessor"],
          missing: []
        ),
        "local_model_reasoning" => capability(
          status: model_endpoint_reachable ? "available" : "missing",
          detail: "Soul has a reachable local model endpoint when llama.cpp/OpenAI-compatible or Ollama responds.",
          provides: ["local_llm_endpoint"],
          current_support: model_endpoint_reachable ? ["reachable_model_endpoint"] : [],
          missing: model_endpoint_reachable ? [] : ["reachable_llama_cpp_or_ollama_endpoint"]
        ),
        "skill_brief_pipeline" => capability(
          status: skill_names.any? { |n| n.to_s.include?("skill.brief.draft") } && skill_names.any? { |n| n.to_s.include?("skill.brief.review") } ? "available" : "partial",
          detail: "Soul can draft and review skill proposals, but does not yet generate alpha implementations.",
          provides: ["proposal_drafting", "proposal_review"],
          current_support: ["skill.brief.draft", "skill.brief.review"],
          missing: ["alpha_skill_generator", "promotion_workflow"]
        ),
        "alpha_skill_generation" => capability(
          status: "missing",
          detail: "Soul does not yet turn approved proposals into isolated alpha skill artifacts.",
          provides: [],
          current_support: [],
          missing: ["implementation_plan_generator", "alpha_skill_generator", "alpha_verifier_generator"]
        ),
        "model_suitability_routing" => capability(
          status: "partial",
          detail: "Soul can detect model endpoints but does not yet route tasks by model capability.",
          provides: ["endpoint_inventory"],
          current_support: ["ModelRuntimeAssessor"],
          missing: ["model_capability_registry", "task_router_policy"]
        ),
        "vision_screen_understanding" => capability(
          status: "missing",
          detail: "Soul cannot yet capture screenshots, invoke a vision model, or reason over screen contents.",
          provides: [],
          current_support: [],
          missing: ["screenshot_capture_skill", "vision_model_runtime", "vision_workflow_handler"]
        ),
        "speech_to_text" => capability(
          status: "missing",
          detail: "Soul does not yet have a local audio transcription capability.",
          provides: [],
          current_support: [],
          missing: ["audio_capture", "stt_runtime", "transcription_skill"]
        )
      }
    end

    def capability(status:, detail:, provides:, current_support:, missing:)
      {
        "status" => status,
        "detail" => detail,
        "provides" => provides,
        "current_support" => current_support,
        "missing" => missing
      }
    end

    def missing(required, workflow_intents, handler_intents)
      required.filter_map do |item|
        type, value = item.split(":", 2)
        case type
        when "workflow"
          workflow_intents.include?(value) ? nil : item
        when "handler"
          handler_intents.include?(value) ? nil : item
        else
          item
        end
      end
    end

    def summarize(capabilities)
      {
        "available" => capabilities.values.count { |value| value["status"] == "available" },
        "partial" => capabilities.values.count { |value| value["status"] == "partial" },
        "missing" => capabilities.values.count { |value| value["status"] == "missing" },
        "blocked" => capabilities.values.count { |value| value["status"] == "blocked" }
      }
    end

    def recommendations(capabilities)
      recs = []

      if capabilities.dig("alpha_skill_generation", "status") == "missing"
        recs << rec(
          "info",
          "Alpha skill generation is missing",
          "Soul can draft/review skill proposals but cannot yet create isolated alpha skill artifacts.",
          "Build an alpha skill generator that writes to proposal-local alpha folders and requires human promotion."
        )
      end

      if capabilities.dig("model_suitability_routing", "status") == "partial"
        recs << rec(
          "info",
          "Model suitability routing is partial",
          "Soul can detect endpoints but does not yet know which model should handle which task.",
          "Add a model capability registry and task routing policy."
        )
      end

      if capabilities.dig("vision_screen_understanding", "status") == "missing"
        recs << rec(
          "info",
          "Vision/screen understanding is missing",
          "Soul cannot yet answer questions about the screen or use screenshot context.",
          "Add screenshot capture, a vision model runtime, and a bounded vision workflow."
        )
      end

      recs
    end

    def rec(severity, title, detail, action)
      {"severity" => severity, "title" => title, "detail" => detail, "action" => action}
    end

    def persist_report(report)
      path = File.join(@root, OUTPUT_PATH)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(report))
    end
  end
end
