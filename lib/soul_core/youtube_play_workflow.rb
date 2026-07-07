# frozen_string_literal: true

require "json"
require "time"
require_relative "skill_registry"
require_relative "skill_runner"
require_relative "task_log"
require_relative "confirmation_parser"

module SoulCore
  module YouTubePlayIntentPatch
    def route(text)
      input = text.to_s.strip
      normalized = input.downcase

      if youtube_play_request?(normalized)
        query = extract_youtube_query(input)
        youtube_play_result_class = self.class.const_get(:Result)
        return youtube_play_result_class.new(
          ok: true,
          intent: "youtube.play",
          parameters: { "query" => query, "query_source" => query.empty? ? "missing" : "extracted" },
          confidence: query.empty? ? 0.72 : 0.91,
          reason: query.empty? ? "Matched YouTube playback phrasing, but no song/query was found." : "Matched YouTube playback phrasing and extracted a song/search query.",
          source: "deterministic"
        )
      end

      super
    end

    private

    def youtube_play_request?(normalized)
      mentions_youtube = normalized.match?(/\byoutube\b/) || normalized.match?(/\byt\b/)
      action = normalized.match?(/\bplay\b/) || normalized.match?(/\bopen\b/) || normalized.match?(/\bsearch\b/) || normalized.match?(/\bfind\b/)
      mentions_youtube && action
    end

    def extract_youtube_query(input)
      value = input.to_s.strip
      value = value.sub(/[?.!]\z/, "").strip

      patterns = [
        /\A(?:please\s+)?(?:can you\s+)?(?:search|find)\s+(?:youtube|yt)\s+(?:for\s+)?(.+)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:search|find)\s+(.+?)\s+(?:on|in)\s+(?:youtube|yt)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:play|open)\s+(.+?)\s+(?:on|in)\s+(?:youtube|yt)\z/i,
        /\A(?:please\s+)?(?:can you\s+)?(?:play|open)\s+(?:youtube|yt)\s+(.+)\z/i
      ]

      patterns.each do |pattern|
        match = value.match(pattern)
        next unless match

        return clean_youtube_query(match[1])
      end

      cleaned = value.dup
      cleaned.gsub!(/\A(?:please\s+)?(?:can you\s+)?/, "")
      cleaned.gsub!(/\b(?:play|open|search|find)\b/i, "")
      cleaned.gsub!(/\b(?:on|in)\s+(?:youtube|yt)\b/i, "")
      cleaned.gsub!(/\b(?:youtube|yt)\b/i, "")
      clean_youtube_query(cleaned)
    end

    def clean_youtube_query(value)
      value.to_s.strip.gsub(/\s+/, " ").sub(/\A["']/, "").sub(/["']\z/, "").strip
    end
  end

  module YouTubePlayWorkflowRunnerPatch
    def run(intent:, parameters:, original_text:)
      return run_youtube_play(parameters: parameters, original_text: original_text) if intent == "youtube.play"

      super
    end

    private

    def run_youtube_play(parameters:, original_text:)
      query = parameters.fetch("query", "").to_s.strip

      if query.empty?
        state = {
          "workflow" => "youtube.play",
          "status" => "needs_youtube_query",
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => { "query" => nil, "query_source" => "missing" },
          "skill_runs" => [],
          "next_expected" => "youtube_query",
          "verification" => {
            "query_present" => false,
            "resolved_candidate" => false,
            "browser_launch_attempted" => false,
            "complete" => false
          }
        }
        workflow_path = write_workflow_state(state, suffix: "youtube.play")
        state["workflow_path"] = workflow_path
        save_session(state)
        return { ok: false, workflow_path: workflow_path, state: state, user_message: @renderer.render_youtube_needs_query(state) }
      end

      registry = SkillRegistry.new
      runner = SkillRunner.new(registry: registry)
      resolve_args = ["--query", query]
      resolve_args << "--dry-run" if ENV["SOUL_YOUTUBE_PLAY_DRY_RUN"] == "1"

      resolve_result = runner.run("youtube.video_resolve", args: resolve_args)
      resolve_log = @task_log.write(kind: "skill.youtube.video_resolve", payload: resolve_result)
      payload = resolve_result[:json] || {}
      candidate = payload["candidate"]

      if resolve_result[:ok] && candidate && candidate["watch_url"].to_s.start_with?("https://www.youtube.com/watch?v=")
        state = {
          "workflow" => "youtube.play",
          "status" => "waiting_for_youtube_open_confirmation",
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => {
            "query" => query,
            "query_source" => parameters.fetch("query_source", "extracted")
          },
          "skill_runs" => [
            { "skill" => "youtube.video_resolve", "args" => resolve_args, "ok" => resolve_result[:ok], "task_log" => resolve_log }
          ],
          "resolver_result" => payload,
          "candidate" => candidate,
          "next_expected" => "youtube_open_confirmation",
          "verification" => {
            "query_present" => true,
            "resolver_log" => resolve_log,
            "resolved_candidate" => true,
            "watch_url_present" => true,
            "browser_launch_attempted" => false,
            "requires_confirmation_before_browser_launch" => true,
            "complete" => false
          }
        }
        workflow_path = write_workflow_state(state, suffix: "youtube.play")
        state["workflow_path"] = workflow_path
        save_session(state)
        return { ok: true, workflow_path: workflow_path, state: state, user_message: @renderer.render_youtube_candidate_confirmation(state) }
      end

      fallback_result = runner.run("youtube.song_search", args: ["--query", query, "--plan-only"])
      fallback_log = @task_log.write(kind: "skill.youtube.song_search", payload: fallback_result)
      fallback = fallback_result[:json] || {}

      state = {
        "workflow" => "youtube.play",
        "status" => fallback_result[:ok] ? "waiting_for_youtube_search_confirmation" : "failed",
        "generated_at" => Time.now.iso8601,
        "updated_at" => Time.now.iso8601,
        "original_text" => original_text,
        "parameters" => {
          "query" => query,
          "query_source" => parameters.fetch("query_source", "extracted")
        },
        "skill_runs" => [
          { "skill" => "youtube.video_resolve", "args" => resolve_args, "ok" => resolve_result[:ok], "task_log" => resolve_log },
          { "skill" => "youtube.song_search", "args" => ["--query", query, "--plan-only"], "ok" => fallback_result[:ok], "task_log" => fallback_log }
        ],
        "resolver_result" => payload,
        "fallback_search" => fallback,
        "next_expected" => fallback_result[:ok] ? "youtube_search_confirmation" : "none",
        "verification" => {
          "query_present" => true,
          "resolver_log" => resolve_log,
          "resolved_candidate" => false,
          "fallback_search_log" => fallback_log,
          "fallback_search_available" => fallback_result[:ok],
          "browser_launch_attempted" => false,
          "requires_confirmation_before_browser_launch" => true,
          "complete" => false
        }
      }
      workflow_path = write_workflow_state(state, suffix: "youtube.play")
      state["workflow_path"] = workflow_path
      save_session(state)

      {
        ok: fallback_result[:ok],
        workflow_path: workflow_path,
        state: state,
        user_message: fallback_result[:ok] ? @renderer.render_youtube_fallback_confirmation(state) : @renderer.render_youtube_resolve_failed(state)
      }
    end
  end

  module YouTubePlayWorkflowSessionPatch
    def respond(text)
      state = @runner.load_session("latest")
      case state.fetch("status")
      when "needs_youtube_query"
        return handle_youtube_query_response(state, text)
      when "waiting_for_youtube_open_confirmation"
        return handle_youtube_open_confirmation(state, text)
      when "waiting_for_youtube_search_confirmation"
        return handle_youtube_search_confirmation(state, text)
      else
        super
      end
    rescue StandardError
      super
    end

    private

    def handle_youtube_query_response(state, text)
      normalized = text.to_s.downcase.strip

      if youtube_cancel_text?(normalized)
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        @runner.save_session(state)
        return { ok: true, message: "YouTube play workflow cancelled.\nNo query was provided, and nothing was opened.", state: state }
      end

      query = text.to_s.strip.sub(/[?.!]\z/, "").strip
      if query.empty?
        return { ok: false, message: @renderer.render_youtube_needs_query(state), state: state }
      end

      result = @runner.run(
        intent: "youtube.play",
        parameters: { "query" => query, "query_source" => "provided_after_prompt" },
        original_text: state.fetch("original_text")
      )
      { ok: result[:ok], message: result[:user_message], state: result[:state] }
    end

    def handle_youtube_open_confirmation(state, text)
      parsed = @confirmation_parser.parse(text)

      if parsed.cancelled
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        state["verification"]["complete"] = false
        @runner.save_session(state)
        return { ok: true, message: "YouTube play workflow cancelled.\nNo browser was opened.", state: state }
      end

      unless parsed.confirmed
        return { ok: false, message: @renderer.render_youtube_candidate_confirmation(state), state: state }
      end

      watch_url = state.dig("candidate", "watch_url").to_s
      args = ["--url", watch_url, "--confirm"]
      result = @skill_runner.run("youtube.song_search", args: args)
      task_log_path = @task_log.write(kind: "skill.youtube.song_search", payload: result)

      state["status"] = result[:ok] ? "complete" : "failed"
      state["updated_at"] = Time.now.iso8601
      state["next_expected"] = result[:ok] ? "reflection_offer" : "none"
      state["skill_runs"] << { "skill" => "youtube.song_search", "args" => args, "ok" => result[:ok], "task_log" => task_log_path }
      state["open_result"] = result[:json] || {}
      state["verification"]["browser_launch_log"] = task_log_path
      state["verification"]["browser_launch_attempted"] = result.dig(:json, "verification", "browser_launch_attempted") || false
      state["verification"]["opened_watch_url"] = watch_url
      state["verification"]["complete"] = result[:ok]
      @runner.save_session(state)

      { ok: result[:ok], message: @renderer.render_youtube_open_execution(state, result), state: state }
    end

    def handle_youtube_search_confirmation(state, text)
      parsed = @confirmation_parser.parse(text)

      if parsed.cancelled
        state["status"] = "cancelled"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = "none"
        state["verification"]["complete"] = false
        @runner.save_session(state)
        return { ok: true, message: "YouTube search fallback cancelled.\nNo browser was opened.", state: state }
      end

      unless parsed.confirmed
        return { ok: false, message: @renderer.render_youtube_fallback_confirmation(state), state: state }
      end

      query = state.dig("parameters", "query").to_s
      args = ["--query", query, "--confirm"]
      result = @skill_runner.run("youtube.song_search", args: args)
      task_log_path = @task_log.write(kind: "skill.youtube.song_search", payload: result)

      state["status"] = result[:ok] ? "complete" : "failed"
      state["updated_at"] = Time.now.iso8601
      state["next_expected"] = result[:ok] ? "reflection_offer" : "none"
      state["skill_runs"] << { "skill" => "youtube.song_search", "args" => args, "ok" => result[:ok], "task_log" => task_log_path }
      state["open_result"] = result[:json] || {}
      state["verification"]["browser_launch_log"] = task_log_path
      state["verification"]["browser_launch_attempted"] = result.dig(:json, "verification", "browser_launch_attempted") || false
      state["verification"]["complete"] = result[:ok]
      @runner.save_session(state)

      { ok: result[:ok], message: @renderer.render_youtube_open_execution(state, result), state: state }
    end

    def youtube_cancel_text?(normalized)
      normalized.match?(/\bcancel\b/) || normalized.match?(/\bstop\b/) || normalized.match?(/\bnever mind\b/) || normalized.match?(/\bnevermind\b/)
    end
  end

  module YouTubePlayResponseRendererPatch
    def render_youtube_needs_query(_state)
      [
        "I can start a YouTube play workflow, but I need a song or search query.",
        "",
        "Try:",
        "",
        '- `ruby bin/soul respond "Bohemian Rhapsody"`',
        '- `ruby bin/soul respond "Hurt Johnny Cash"`',
        '- `ruby bin/soul respond "cancel"`'
      ].join("\n")
    end

    def render_youtube_candidate_confirmation(state)
      candidate = state.fetch("candidate", {})
      [
        "I found this YouTube result:",
        "",
        "- Title: #{candidate['title'] || 'unavailable'}",
        "- Channel: #{candidate['channel_title'] || 'unavailable'}",
        "- URL: #{candidate['watch_url'] || 'unavailable'}",
        "",
        "Open this video in your default browser?",
        "",
        '- `ruby bin/soul respond "yes"`',
        '- `ruby bin/soul respond "cancel"`',
        "",
        "Soul will open the watch URL. It cannot guarantee playback starts or skip ads."
      ].join("\n")
    end

    def render_youtube_fallback_confirmation(state)
      query = state.dig("parameters", "query")
      fallback = state.fetch("fallback_search", {})
      resolver = state.fetch("resolver_result", {})
      [
        "I could not resolve a specific YouTube video candidate.",
        "",
        "- Query: #{query}",
        "- Resolver outcome: #{resolver['outcome'] || 'unknown'}",
        "- Search URL: #{fallback['url'] || 'unavailable'}",
        "",
        "Open YouTube search results instead?",
        "",
        '- `ruby bin/soul respond "yes"`',
        '- `ruby bin/soul respond "cancel"`'
      ].join("\n")
    end

    def render_youtube_resolve_failed(state)
      resolver = state.fetch("resolver_result", {})
      [
        "YouTube play workflow failed before browser launch.",
        "",
        "- Resolver outcome: #{resolver['outcome'] || 'unknown'}",
        "- Resolver status: #{resolver['status'] || 'unknown'}",
        "- Final state: failed",
        "",
        "No browser was opened."
      ].join("\n")
    end

    def render_youtube_open_execution(state, result)
      data = result[:json] || {}
      [
        result[:ok] ? "YouTube workflow complete." : "YouTube workflow failed during browser launch.",
        "",
        "- Outcome: #{data['outcome'] || 'unknown'}",
        "- URL: #{data['url'] || state.dig('candidate', 'watch_url') || 'unavailable'}",
        "- Browser launch attempted: #{data.dig('verification', 'browser_launch_attempted')}",
        "- Final state: #{state.fetch('status')}",
        "",
        "Soul opened the watch/search URL. Browser playback and ads are outside Soul's control.",
        "",
        "Next: `ruby bin/soul reflect last` if this task should produce a reflection candidate."
      ].join("\n")
    end
  end
end

SoulCore::IntentRouter.prepend(SoulCore::YouTubePlayIntentPatch)
SoulCore::WorkflowRunner.prepend(SoulCore::YouTubePlayWorkflowRunnerPatch)
SoulCore::WorkflowSession.prepend(SoulCore::YouTubePlayWorkflowSessionPatch)
SoulCore::ResponseRenderer.prepend(SoulCore::YouTubePlayResponseRendererPatch)
