# frozen_string_literal: true

module SoulCore
  class WorkflowRegistry
    Workflow = Struct.new(
      :intent,
      :description,
      :runner,
      :session_statuses,
      :requires_confirmation,
      :write_capable,
      :skills,
      :examples,
      keyword_init: true
    )

    def initialize
      @workflows = {}
      register_defaults
    end

    def register(intent:, description:, runner:, session_statuses:, requires_confirmation:, write_capable:, skills:, examples:)
      key = intent.to_s
      raise ArgumentError, "workflow intent is required" if key.strip.empty?
      raise ArgumentError, "workflow already registered: #{key}" if @workflows.key?(key)

      @workflows[key] = Workflow.new(
        intent: key,
        description: description.to_s,
        runner: runner.to_s,
        session_statuses: Array(session_statuses).map(&:to_s),
        requires_confirmation: !!requires_confirmation,
        write_capable: !!write_capable,
        skills: Array(skills).map(&:to_s),
        examples: Array(examples).map(&:to_s)
      )
    end

    def get(intent)
      @workflows.fetch(intent.to_s)
    end

    def include?(intent)
      @workflows.key?(intent.to_s)
    end

    def list
      @workflows.keys.sort.map { |key| @workflows.fetch(key) }
    end

    def to_h
      {
        "status" => "ok",
        "outcome" => "complete",
        "workflow_count" => @workflows.length,
        "workflows" => list.map { |workflow| workflow_to_h(workflow) },
        "verification" => {
          "read_only" => true,
          "registry_present" => true,
          "registered_intents" => @workflows.keys.sort
        }
      }
    end

    def render_list
      lines = ["Registered workflows:", ""]

      list.each do |workflow|
        lines << "- #{workflow.intent}"
        lines << "  description: #{workflow.description}"
        lines << "  runner: #{workflow.runner}"
        lines << "  confirmation required: #{workflow.requires_confirmation}"
        lines << "  write capable: #{workflow.write_capable}"
        lines << "  skills: #{workflow.skills.empty? ? 'none' : workflow.skills.join(', ')}"
        unless workflow.examples.empty?
          lines << "  examples:"
          workflow.examples.each { |example| lines << "    - #{example}" }
        end
        lines << ""
      end

      lines << "This is a registry view only. Workflow execution still goes through `ruby bin/soul do \"...\"` and session continuation still goes through `ruby bin/soul respond \"...\"`."
      lines.join("\n")
    end

    private

    def workflow_to_h(workflow)
      {
        "intent" => workflow.intent,
        "description" => workflow.description,
        "runner" => workflow.runner,
        "session_statuses" => workflow.session_statuses,
        "requires_confirmation" => workflow.requires_confirmation,
        "write_capable" => workflow.write_capable,
        "skills" => workflow.skills,
        "examples" => workflow.examples
      }
    end

    def register_defaults
      register(
        intent: "downloads.cleanup",
        description: "Plan and confirm a safe Downloads cleanup using Trash, not permanent deletion.",
        runner: "WorkflowRunner#run_downloads_cleanup",
        session_statuses: ["waiting_for_selection", "waiting_for_final_confirmation", "complete_no_action", "complete", "cancelled", "failed"],
        requires_confirmation: true,
        write_capable: true,
        skills: ["downloads.cleanup_plan", "downloads.move_to_trash"],
        examples: [
          'ruby bin/soul do "cleanup files in my downloads folder older than 30 days"',
          'ruby bin/soul respond "move all"',
          'ruby bin/soul respond "yeah, do it"'
        ]
      )

      register(
        intent: "downloads.restore_last_cleanup",
        description: "Plan and confirm restoring the most recent Downloads cleanup from Trash.",
        runner: "WorkflowRunner#run_downloads_restore_last_cleanup",
        session_statuses: ["waiting_for_restore_selection", "waiting_for_restore_final_confirmation", "complete_no_action", "complete", "cancelled", "failed"],
        requires_confirmation: true,
        write_capable: true,
        skills: ["downloads.restore_last_cleanup"],
        examples: [
          'ruby bin/soul do "restore the last downloads cleanup"',
          'ruby bin/soul respond "restore all"',
          'ruby bin/soul respond "yeah, do it"'
        ]
      )

      register(
        intent: "weather.report",
        description: "Resolve a location, fetch a current weather summary, and optionally fetch a detailed report.",
        runner: "WorkflowRunner#run_weather_report",
        session_statuses: ["needs_location", "waiting_for_weather_location_choice", "waiting_for_weather_override_location", "waiting_for_weather_detail_decision", "complete", "cancelled", "failed"],
        requires_confirmation: true,
        write_capable: false,
        skills: ["weather.report"],
        examples: [
          'ruby bin/soul do "what is the weather today in Syracuse, NY"',
          'ruby bin/soul respond "yes"'
        ]
      )

      register(
        intent: "youtube.play",
        description: "Resolve a YouTube video candidate for a song/query, show it, and open only after confirmation.",
        runner: "YouTubePlayWorkflowRunnerPatch#run_youtube_play",
        session_statuses: ["needs_youtube_query", "waiting_for_youtube_open_confirmation", "waiting_for_youtube_search_confirmation", "complete", "cancelled", "failed"],
        requires_confirmation: true,
        write_capable: true,
        skills: ["youtube.video_resolve", "youtube.song_search"],
        examples: [
          'ruby bin/soul do "play Folsom Prison Blues on YouTube"',
          'ruby bin/soul respond "yes"'
        ]
      )
    end
  end
end
