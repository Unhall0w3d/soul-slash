# frozen_string_literal: true

require "json"
require_relative "env_loader"
require_relative "model_client"
require_relative "skill_registry"
require_relative "skill_runner"
require_relative "task_log"
require_relative "reflection"
require_relative "reflection_review"
require_relative "intent_router"
require_relative "workflow_runner"
require_relative "workflow_registry"
require_relative "workflow_tools"
require_relative "workflow_session"
require_relative "youtube_play_workflow"
require_relative "workflow_registry_execution"

module SoulCore
  class App
    def initialize(argv)
      EnvLoader.load
      @argv = argv
      @log = TaskLog.new
    end

    def run
      command = @argv.shift

      case command
      when "doctor"
        doctor
      when "ask"
        ask
      when "intent"
        intent
      when "do"
        do_request
      when "respond"
        respond
      when "workflow"
        workflow
      when "workflows"
        workflows
      when "skill"
        skill
      when "skills"
        skills
      when "reflect"
        reflect
      when "reflection"
        reflection
      when "reflections"
        reflections
      when "help", nil
        help
      else
        warn "Unknown command: #{command}"
        help
        exit 1
      end
    end

    private

    def doctor
      client = ModelClient.new
      registry = SkillRegistry.new

      puts "Soul/ doctor"
      puts "base_url: #{client.base_url}"
      puts "model: #{client.model}"
      puts "weather_location: #{ENV.fetch('SOUL_WEATHER_LOCATION', 'unset')}"
      puts "skills: #{registry.list.keys.join(', ')}"

      begin
        models = client.models
        puts "model endpoint: ok"
        puts JSON.pretty_generate(models)
      rescue StandardError => e
        puts "model endpoint: failed"
        puts "#{e.class}: #{e.message}"
      end
    end

    def ask
      mode = (@argv.shift || "fast").to_sym
      prompt = @argv.join(" ").strip

      if prompt.empty?
        warn 'Usage: ruby bin/soul ask fast|think "your prompt"'
        exit 1
      end

      client = ModelClient.new
      result = client.chat(prompt, mode: mode)
      puts(result[:content].to_s.strip.empty? ? result[:reasoning_content] : result[:content])
      path = @log.write(kind: "ask.#{mode}", payload: result)
      warn "logged: #{path}"
    end

    def intent
      text = @argv.join(" ").strip

      if text.empty?
        warn 'Usage: ruby bin/soul intent "what is the weather today in Syracuse, NY"'
        exit 1
      end

      router = IntentRouter.new
      routed = router.route(text)

      puts JSON.pretty_generate({
        ok: routed.ok,
        intent: routed.intent,
        confidence: routed.confidence,
        source: routed.source,
        reason: routed.reason,
        parameters: routed.parameters
      })

      exit 1 unless routed.ok
    rescue StandardError => e
      warn "intent failed: #{e.class}: #{e.message}"
      exit 1
    end

    def do_request
      text = @argv.join(" ").strip

      if text.empty?
        warn 'Usage: ruby bin/soul do "what is the weather today in Syracuse, NY"'
        exit 1
      end

      router = IntentRouter.new
      routed = router.route(text)

      unless routed.ok
        warn "No workflow matched."
        warn "Reason: #{routed.reason}"
        warn
        warn "Currently supported examples:"
        warn '  ruby bin/soul do "cleanup files in my downloads folder older than 30 days"'
        warn '  ruby bin/soul do "run a file cleanup in Downloads"'
        warn '  ruby bin/soul do "restore the last downloads cleanup"'
        warn '  ruby bin/soul do "what is the weather today in Syracuse, NY"'
        exit 1
      end

      runner = WorkflowRunner.new
      result = runner.run(intent: routed.intent, parameters: routed.parameters, original_text: text)

      puts "Intent: #{routed.intent}"
      puts "Confidence: #{routed.confidence}"
      puts "Source: #{routed.source}"
      puts "Reason: #{routed.reason}"
      puts
      puts result[:user_message]

      exit 1 unless result[:ok]
    rescue StandardError => e
      warn "do failed: #{e.class}: #{e.message}"
      exit 1
    end

    def respond
      text = @argv.join(" ").strip

      if text.empty?
        warn 'Usage: ruby bin/soul respond "yes"'
        exit 1
      end

      session = WorkflowSession.new
      result = session.respond(text)
      puts result[:message]
      exit 1 unless result[:ok]
    rescue StandardError => e
      warn "respond failed: #{e.class}: #{e.message}"
      exit 1
    end

    def workflow
  subcommand = @argv.shift || "show"
  runner = WorkflowRunner.new
  tools = WorkflowTools.new

  case subcommand
  when "show"
    target = @argv.shift || "latest"
    puts runner.show(target)
  when "status"
    target = @argv.shift || "latest"
    payload = tools.status(target)
    puts tools.render_status(payload)
  when "list"
    include_all = !@argv.include?("--active")
    payload = tools.list(include_all: include_all)
    puts tools.render_list(payload)
  when "clear-complete"
    confirm = false
    if @argv.include?("--confirm")
      index = @argv.index("--confirm")
      confirm = @argv[index + 1] == "CLEAR_COMPLETE"
    end

    payload = tools.clear_complete(confirm: confirm)
    puts tools.render_clear_complete(payload)
    exit 1 if payload["outcome"] == "awaiting_confirmation" && payload.fetch("candidate_count", 0).positive?
  else
    warn "Unknown workflow subcommand: #{subcommand}"
    warn "Usage: ruby bin/soul workflow show|status|list|clear-complete [latest|path]"
    exit 1
  end
rescue StandardError => e
  warn "workflow #{subcommand} failed: #{e.class}: #{e.message}"
  exit 1
end 

    def workflows
  registry = WorkflowRegistry.new

  if @argv.include?("--json")
    puts JSON.pretty_generate(registry.to_h)
  else
    puts registry.render_list
  end
rescue StandardError => e
  warn "workflows failed: #{e.class}: #{e.message}"
  exit 1
end 

    def skill
      name = @argv.shift

      unless name
        warn "Usage: ruby bin/soul skill weather.report -- --location 'Syracuse, NY'"
        exit 1
      end

      @argv.shift if @argv.first == "--"
      skill_args = @argv

      registry = SkillRegistry.new
      runner = SkillRunner.new(registry: registry)
      result = runner.run(name, args: skill_args)

      if result[:json]
        puts JSON.pretty_generate(result[:json])
      else
        puts result[:stdout]
      end

      path = @log.write(kind: "skill.#{name}", payload: result)
      warn "logged: #{path}"

      exit 1 unless result[:ok]
    end

    def skills
      registry = SkillRegistry.new
      registry.list.each do |name, meta|
        puts "#{name} - #{meta['description']} [risk=#{meta['risk']}]"
      end
    end

    def reflect
      target = @argv.shift || "last"
      reflection = Reflection.new
      result = reflection.reflect(target)

      puts "Reflection candidate staged."
      puts "source: #{result[:source_log]}"
      puts "json: #{result[:json_path]}"
      puts "markdown: #{result[:markdown_path]}"
    rescue StandardError => e
      warn "reflect failed: #{e.class}: #{e.message}"
      exit 1
    end

    def reflection
      subcommand = @argv.shift || "show"
      review = ReflectionReview.new

      case subcommand
      when "show"
        target = @argv.shift || "latest"
        puts review.show(target)
      when "approve"
        target = @argv.shift || "latest"
        note = extract_option_value("--note")
        result = review.approve(target, note: note)
        puts "Reflection candidate approved."
        puts "json: #{result[:approved_json_path]}"
        puts "markdown: #{result[:approved_markdown_path]}"
        puts "lessons: #{result[:lessons_appended_to]}"
        puts "rules: #{result[:rules_appended_to]}"
      when "reject"
        target = @argv.shift || "latest"
        reason = extract_option_value("--reason") || @argv.join(" ")
        result = review.reject(target, reason: reason)
        puts "Reflection candidate rejected."
        puts "json: #{result[:rejected_json_path]}"
        puts "markdown: #{result[:rejected_markdown_path]}"
      else
        warn "Unknown reflection subcommand: #{subcommand}"
        warn "Usage: ruby bin/soul reflection show|approve|reject latest"
        exit 1
      end
    rescue StandardError => e
      warn "reflection #{subcommand} failed: #{e.class}: #{e.message}"
      exit 1
    end

    def reflections
      reflection = Reflection.new
      pending = reflection.pending

      if pending.empty?
        puts "No pending reflection candidates."
      else
        pending.each { |path| puts path }
      end
    end

    def extract_option_value(name)
      index = @argv.index(name)
      return nil unless index

      value = @argv[index + 1]
      @argv.slice!(index, 2)
      value
    end

    def help
      puts <<~HELP
        Soul/ CLI

        Commands:
          ruby bin/soul doctor
          ruby bin/soul skills

          ruby bin/soul intent "what is the weather today in Syracuse, NY"
          ruby bin/soul do "what is the weather today in Syracuse, NY"
          ruby bin/soul do "what is the weather like today"
          ruby bin/soul respond "yes"
          ruby bin/soul respond "no"

          ruby bin/soul intent "run a file cleanup in Downloads"
          ruby bin/soul intent "restore the last downloads cleanup"

          ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
          ruby bin/soul do "run a file cleanup in Downloads"
          ruby bin/soul do "restore the last downloads cleanup"
          ruby bin/soul respond "move all"
          ruby bin/soul respond "move all except F1"
          ruby bin/soul respond "only move F1 and D1"
          ruby bin/soul respond "restore all"
          ruby bin/soul respond "restore all except F1"
          ruby bin/soul respond "only restore F1 and D1"
          ruby bin/soul respond "yeah, do it"
          ruby bin/soul respond "cancel"

          ruby bin/soul workflows
ruby bin/soul workflows --json
          ruby bin/soul workflow show latest
ruby bin/soul workflow status latest
ruby bin/soul workflow list
ruby bin/soul workflow list --active
ruby bin/soul workflow clear-complete
ruby bin/soul workflow clear-complete --confirm CLEAR_COMPLETE

ruby bin/soul do "play Folsom Prison Blues on YouTube"
ruby bin/soul respond "yes"

          ruby bin/soul skill system.status
          ruby bin/soul skill weather.report -- --location "Syracuse, NY"
          ruby bin/soul skill weather.report -- --location "Syracuse, NY" --detailed
          ruby bin/soul skill downloads.inspect
          ruby bin/soul skill downloads.cleanup_plan
          ruby bin/soul skill downloads.move_to_trash -- --latest-plan
          ruby bin/soul skill downloads.move_to_trash -- --latest-plan --execute --confirm MOVE_TO_TRASH
          ruby bin/soul skill downloads.restore_last_cleanup
          ruby bin/soul skill downloads.restore_last_cleanup -- --execute --confirm RESTORE_FROM_TRASH

          ruby bin/soul reflect last
          ruby bin/soul reflections
          ruby bin/soul reflection show latest
          ruby bin/soul reflection approve latest
          ruby bin/soul reflection reject latest --reason "Not useful"

          ruby bin/soul ask fast "Say exactly: Soul CLI is online."
          ruby bin/soul ask think "Why should Soul verify actions?"

        Environment:
          SOUL_OPENAI_BASE_URL=http://127.0.0.1:8082/v1
          SOUL_MODEL_ALIAS=soul-qwen3-8b-q4
          SOUL_WEATHER_LOCATION=Syracuse, NY
          SOUL_WEATHER_UNITS=fahrenheit
      HELP
    end
  end
end
