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
      handlers = safe_handler_registry
      workflows = safe_workflow_registry(handler_intents: handlers.fetch("intents", []))
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
        lines << "  Missing: #{data['missing'].join(', ')}" if data["missing"].is_a?(Array) && data["missing"].any?
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

      lines << "\nOutput: #{report['output_path']}" if report["output_path"]
      lines.join("\n")
    end

    private

    def safe_skill_registry
      names = []

      begin
        registry = SkillRegistry.new
        if registry.respond_to?(:to_h)
          names.concat(extract_names(registry.to_h))
        elsif registry.respond_to?(:skills)
          names.concat(extract_names(registry.skills))
        end
      rescue StandardError
        nil
      end

      names.concat(filesystem_skill_names)
      names = names.compact.map(&:to_s).uniq.sort

      {"status" => "ok", "names" => names, "source" => "registry_or_filesystem"}
    end

    def filesystem_skill_names
      patterns = [
        File.join(@root, "lib", "soul_core", "skills", "**", "*.rb"),
        File.join(@root, "Soul", "skills", "**", "*.rb")
      ]

      patterns.flat_map do |pattern|
        Dir.glob(pattern).map do |path|
          relative = path.sub(@root + "/", "").sub(/\.rb\z/, "")
          relative.split("/").last(3).join(".").gsub("_", ".")
        end
      end
    end

    def extract_names(value)
      case value
      when Hash
        if value["skills"].is_a?(Array)
          value["skills"].flat_map { |item| extract_names(item) }
        else
          value.keys
        end
      when Array
        value.flat_map { |item| extract_names(item) }
      else
        value.respond_to?(:name) ? [value.name] : [value.to_s]
      end
    end

    def safe_workflow_registry(handler_intents:)
      intents = []
      definitions = []

      begin
        registry = WorkflowRegistry.new
        if registry.respond_to?(:definitions)
          definitions = registry.definitions.map do |definition|
            intent = definition.respond_to?(:intent) ? definition.intent : nil
            intents << intent
            {"intent" => intent, "description" => definition.respond_to?(:description) ? definition.description : nil}
          end
        elsif registry.respond_to?(:to_h)
          data = registry.to_h
          definitions = Array(data["workflows"] || data["definitions"])
          intents.concat(definitions.map { |item| item.is_a?(Hash) ? item["intent"] : item.to_s })
        end
      rescue StandardError
        nil
      end

      intents.concat(handler_intents)
      intents = intents.compact.map(&:to_s).uniq.sort
      definitions = intents.map { |intent| {"intent" => intent} } if definitions.empty? && intents.any?

      {"status" => "ok", "definitions" => definitions, "intents" => intents, "source" => "registry_or_handlers"}
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
      youtube_ready = workflow_intents.include?("youtube.play") && handler_intents.include?("youtube.play")
      model_endpoint_reachable = !!models.dig("endpoints", "llama_cpp_openai", "reachable") || !!models.dig("endpoints", "ollama", "reachable")
      contract_valid = contracts["valid"] == true

      {
        "youtube_playback" => capability(
          status: youtube_ready ? "available" : "partial",
          detail: "YouTube playback is available when the YouTube workflow handler and confirmation flow are registered.",
          provides: ["natural_language_youtube_request", "candidate_resolution", "confirmation_gate", "browser_launch"],
          current_support: ["workflow:youtube.play", "handler:youtube.play", "skills:youtube.*"],
          missing: youtube_ready ? [] : missing(["workflow:youtube.play", "handler:youtube.play"], workflow_intents, handler_intents)
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
          status: "available",
          detail: "Soul can create local gap intakes, review exact proposal revisions, and preserve human Gate 1 before Beta implementation.",
          provides: ["proposal_drafting", "proposal_review", "capability_gap_intake", "human_gate_1"],
          current_support: ["skill.brief.draft", "skill.brief.review", "CapabilityGapIntakeService", "SkillStudioService"],
          missing: []
        ),
        "alpha_skill_generation" => capability(
          status: "available",
          detail: "Soul can generate isolated alpha/Beta artifacts and hold them outside the production registry for testing and human Gate 2 review.",
          provides: ["implementation_plan_generator", "alpha_skill_generator", "alpha_verifier_generator", "beta_registry", "human_gate_2"],
          current_support: ["AlphaSkillPlanGenerator", "AlphaSkillGenerator", "AlphaReview", "SkillStudioService", "AlphaPromotionGate"],
          missing: []
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
      {"status" => status, "detail" => detail, "provides" => provides, "current_support" => current_support, "missing" => missing}
    end

    def missing(required, workflow_intents, handler_intents)
      required.filter_map do |item|
        type, value = item.split(":", 2)
        case type
        when "workflow" then workflow_intents.include?(value) ? nil : item
        when "handler" then handler_intents.include?(value) ? nil : item
        else item
        end
      end
    end

    def summarize(capabilities)
      {"available" => capabilities.values.count { |v| v["status"] == "available" }, "partial" => capabilities.values.count { |v| v["status"] == "partial" }, "missing" => capabilities.values.count { |v| v["status"] == "missing" }, "blocked" => capabilities.values.count { |v| v["status"] == "blocked" }}
    end

    def recommendations(capabilities)
      recs = []
      recs << rec("info", "Model suitability routing is partial", "Soul can detect endpoints but does not yet know which model should handle which task.", "Add a model capability registry and task routing policy.") if capabilities.dig("model_suitability_routing", "status") == "partial"
      recs << rec("info", "Vision/screen understanding is missing", "Soul cannot yet answer questions about the screen or use screenshot context.", "Add screenshot capture, a vision model runtime, and a bounded vision workflow.") if capabilities.dig("vision_screen_understanding", "status") == "missing"
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
