# frozen_string_literal: true

require "json"
require_relative "confirmation_parser"
require_relative "env_loader"
require_relative "intent_router"
require_relative "skill_registry"
require_relative "skill_runner"
require_relative "workflow_runner"
require_relative "workflow_tools"
require_relative "workflow_registry"
require_relative "workflow_intent_handler_dispatch"
require_relative "workflow_registry_execution"
require_relative "workflow_handler_registry"
require_relative "workflow_contract_validator"
require_relative "environment_assessor"
require_relative "model_runtime_assessor"
require_relative "capability_matrix"
require_relative "response_renderer"
require_relative "workflow_session"

module SoulCore
  class App
    def initialize(positional_argv = nil, argv: nil)
      @argv = (argv || positional_argv || []).dup
      EnvLoader.load
      validate_workflow_contracts!
    end

    def run
      command = @argv.shift
      case command
      when "skills" then puts JSON.pretty_generate(SkillRegistry.new.to_h); 0
      when "skill" then run_skill
      when "intent" then run_intent
      when "do" then run_do
      when "respond" then run_respond
      when "reflect" then run_reflect
      when "workflow" then run_workflow_command
      when "workflows" then run_workflows_command
      when "doctor" then run_doctor
      when "assess" then run_assess
      else
        print_help
        command ? 1 : 0
      end
    rescue StandardError => e
      warn "Soul failed: #{e.class}: #{e.message}"
      1
    end

    private

    def validate_workflow_contracts!
      return if ENV["SOUL_SKIP_WORKFLOW_CONTRACT_VALIDATION"] == "1"
      WorkflowContractValidator.new.validate_registry!(WorkflowHandlerRegistry.new)
    end

    def run_assess
      target = @argv.shift
      case target
      when "environment"
        include_updates = @argv.include?("--updates")
        json = @argv.include?("--json")
        assessor = EnvironmentAssessor.new(root: Dir.pwd)
        report = assessor.assess(include_updates: include_updates)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "models", "model-runtime"
        json = @argv.include?("--json")
        include_processes = @argv.include?("--processes")
        assessor = ModelRuntimeAssessor.new(root: Dir.pwd)
        report = assessor.assess(include_processes: include_processes)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      when "capabilities", "capability-matrix"
        json = @argv.include?("--json")
        persist = @argv.include?("--persist")
        assessor = CapabilityMatrix.new(root: Dir.pwd)
        report = assessor.assess(persist: persist)
        puts(json ? JSON.pretty_generate(report) : assessor.render(report))
        0
      else
        puts "Unknown assessment target."
        puts
        puts "Examples:"
        puts "  ruby bin/soul assess environment"
        puts "  ruby bin/soul assess environment --updates --json"
        puts "  ruby bin/soul assess models"
        puts "  ruby bin/soul assess models --json"
        puts "  ruby bin/soul assess capabilities"
        puts "  ruby bin/soul assess capabilities --json"
        puts "  ruby bin/soul assess capabilities --persist"
        1
      end
    end

    def run_doctor
      report = WorkflowContractValidator.new.health_report(WorkflowHandlerRegistry.new)
      puts(@argv.include?("--json") ? JSON.pretty_generate(report) : report.fetch("message"))
      report.fetch("valid") ? 0 : 1
    end

    def run_skill
      name = @argv.shift
      separator_index = @argv.index("--")
      args = separator_index ? (@argv[(separator_index + 1)..] || []) : @argv
      result = SkillRunner.new(registry: SkillRegistry.new).run(name, args: args)
      puts JSON.pretty_generate(result[:json])
      result[:ok] ? 0 : 1
    end

    def run_intent
      text = @argv.join(" ").strip
      result = IntentRouter.new.route(text)
      puts JSON.pretty_generate({"ok"=>result.ok,"intent"=>result.intent,"parameters"=>result.parameters,"confidence"=>result.confidence,"reason"=>result.reason,"source"=>result.source})
      result.ok ? 0 : 1
    end

    def run_do
      text = @argv.join(" ").strip
      intent = IntentRouter.new.route(text)
      unless intent.ok
        puts "I could not map that request to a supported workflow."
        puts
        puts "Reason: #{intent.reason}"
        return 1
      end
      result = WorkflowRunner.new.run(intent: intent.intent, parameters: intent.parameters, original_text: text)
      puts "Intent: #{intent.intent}"
      puts "Workflow state: #{result.dig(:state, 'status') || 'unknown'}"
      puts "Workflow file: #{result[:workflow_path]}" if result[:workflow_path]
      puts
      puts result[:user_message]
      result[:ok] ? 0 : 1
    end

    def run_respond
      text = @argv.join(" ").strip
      result = WorkflowSession.new.respond(text)
      puts result[:message]
      result[:ok] ? 0 : 1
    end

    def run_reflect
      target = @argv.shift || "last"
      result = ResponseRenderer.new.reflect(target)
      puts result[:message]
      result[:ok] ? 0 : 1
    end

    def run_workflow_command
      subcommand = @argv.shift
      case subcommand
      when "show"
        puts JSON.pretty_generate(WorkflowTools.new.show(@argv.shift || "latest")); 0
      when "status"
        result = WorkflowTools.new.status(@argv.shift || "latest"); puts result.fetch("message"); result.fetch("ok") ? 0 : 1
      when "list"
        puts JSON.pretty_generate(WorkflowTools.new.list(active_only: @argv.include?("--active"))); 0
      when "clear-complete"
        result = WorkflowTools.new.clear_complete(confirm: @argv.include?("--confirm") && @argv.include?("CLEAR_COMPLETE")); puts JSON.pretty_generate(result); result.fetch("ok") ? 0 : 1
      else
        puts "Unknown workflow command."
        1
      end
    end

    def run_workflows_command
      registry = WorkflowRegistry.new
      if @argv.include?("--json")
        puts JSON.pretty_generate(registry.to_h)
      else
        registry.definitions.each { |definition| puts "#{definition.intent} - #{definition.description}" }
      end
      0
    end

    def print_help
      puts "Soul command examples:"
      puts "  ruby bin/soul skills"
      puts "  ruby bin/soul intent \"play Folsom Prison Blues on YouTube\""
      puts "  ruby bin/soul do \"play Folsom Prison Blues on YouTube\""
      puts "  ruby bin/soul respond \"yes\""
      puts "  ruby bin/soul doctor"
      puts "  ruby bin/soul assess environment"
      puts "  ruby bin/soul assess models"
      puts "  ruby bin/soul assess capabilities"
      puts "  ruby bin/soul assess capabilities --persist --json"
    end
  end
end
