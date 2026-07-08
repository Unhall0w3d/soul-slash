# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

require_relative "../confirmation_parser"
require_relative "../skill_registry"
require_relative "../skill_runner"
require_relative "../task_log"
require_relative "../workflow_runner"
require_relative "base_handler"

module SoulCore
  module Workflows
    class YouTubePlayHandler < BaseHandler
      SESSION_ROOT = "Soul/workflows/sessions"

      HANDLED_STATUSES = [
        "needs_youtube_query",
        "waiting_for_youtube_open_confirmation",
        "waiting_for_youtube_search_confirmation"
      ].freeze

      def responds_to_status?(status)
        HANDLED_STATUSES.include?(status.to_s)
      end

      def run(parameters:, original_text:)
        query = parameters.fetch("query", "").to_s.strip

        if query.empty?
          state = base_state(
            status: "needs_youtube_query",
            original_text: original_text,
            parameters: { "query" => nil, "query_source" => "missing" },
            next_expected: "youtube_query",
            verification: {
              "query_present" => false,
              "resolved_candidate" => false,
              "browser_launch_attempted" => false,
              "complete" => false
            }
          )

          workflow_path = write_workflow_state(state)
          save_state(state)

          return {
            ok: false,
            workflow_path: workflow_path,
            state: enrich_handler_state(state),
            user_message: render_needs_query(state)
          }
        end

        registry = SkillRegistry.new
        skill_runner = SkillRunner.new(registry: registry)
        task_log = TaskLog.new

        resolve_args = ["--query", query]
        resolve_args << "--dry-run" if ENV["SOUL_YOUTUBE_PLAY_DRY_RUN"] == "1"

        resolve_result = skill_runner.run("youtube.video_resolve", args: resolve_args)
        resolve_log = task_log.write(kind: "skill.youtube.video_resolve", payload: resolve_result)
        payload = resolve_result[:json] || {}
        candidate = payload["candidate"]

        if resolve_result[:ok] && candidate && candidate["watch_url"].to_s.start_with?("https://www.youtube.com/watch?v=")
          state = base_state(
            status: "waiting_for_youtube_open_confirmation",
            original_text: original_text,
            parameters: {
              "query" => query,
              "query_source" => parameters.fetch("query_source", "extracted")
            },
            skill_runs: [
              { "skill" => "youtube.video_resolve", "args" => resolve_args, "ok" => resolve_result[:ok], "task_log" => resolve_log }
            ],
            next_expected: "youtube_open_confirmation",
            verification: {
              "query_present" => true,
              "resolver_log" => resolve_log,
              "resolved_candidate" => true,
              "watch_url_present" => true,
              "browser_launch_attempted" => false,
              "requires_confirmation_before_browser_launch" => true,
              "complete" => false
            }
          )

          state["resolver_result"] = payload
          state["candidate"] = candidate

          workflow_path = write_workflow_state(state)
          save_state(state)

          return {
            ok: true,
            workflow_path: workflow_path,
            state: enrich_handler_state(state),
            user_message: render_candidate_confirmation(state)
          }
        end

        fallback_result = skill_runner.run("youtube.song_search", args: ["--query", query, "--plan-only"])
        fallback_log = task_log.write(kind: "skill.youtube.song_search", payload: fallback_result)
        fallback = fallback_result[:json] || {}

        state = base_state(
          status: fallback_result[:ok] ? "waiting_for_youtube_search_confirmation" : "failed",
          original_text: original_text,
          parameters: {
            "query" => query,
            "query_source" => parameters.fetch("query_source", "extracted")
          },
          skill_runs: [
            { "skill" => "youtube.video_resolve", "args" => resolve_args, "ok" => resolve_result[:ok], "task_log" => resolve_log },
            { "skill" => "youtube.song_search", "args" => ["--query", query, "--plan-only"], "ok" => fallback_result[:ok], "task_log" => fallback_log }
          ],
          next_expected: fallback_result[:ok] ? "youtube_search_confirmation" : "none",
          verification: {
            "query_present" => true,
            "resolver_log" => resolve_log,
            "resolved_candidate" => false,
            "fallback_search_log" => fallback_log,
            "fallback_search_available" => fallback_result[:ok],
            "browser_launch_attempted" => false,
            "requires_confirmation_before_browser_launch" => true,
            "complete" => false
          }
        )

        state["resolver_result"] = payload
        state["fallback_search"] = fallback

        workflow_path = write_workflow_state(state)
        save_state(state)

        {
          ok: fallback_result[:ok],
          workflow_path: workflow_path,
          state: enrich_handler_state(state),
          user_message: fallback_result[:ok] ? render_fallback_confirmation(state) : render_resolve_failed(state)
        }
      end

      def respond(state:, text:)
        case state.fetch("status")
        when "needs_youtube_query"
          handle_query_response(state, text)
        when "waiting_for_youtube_open_confirmation"
          handle_open_confirmation(state, text)
        when "waiting_for_youtube_search_confirmation"
          handle_search_confirmation(state, text)
        else
          {
            ok: false,
            message: "YouTube handler does not support workflow status: #{state.fetch('status')}",
            state: state
          }
        end
      end

      private

      def handle_query_response(state, text)
        normalized = text.to_s.downcase.strip

        if cancel_text?(normalized)
          state["status"] = "cancelled"
          state["updated_at"] = Time.now.iso8601
          state["next_expected"] = "none"
          state["verification"]["complete"] = false
          state["handler_response"] = handler_response_metadata("cancelled_before_query")
          save_state(state)

          return {
            ok: true,
            message: "YouTube play workflow cancelled.\nNo query was provided, and nothing was opened.",
            state: state
          }
        end

        query = text.to_s.strip.sub(/[?.!]\z/, "").strip
        if query.empty?
          return { ok: false, message: render_needs_query(state), state: state }
        end

        result = WorkflowRunner.new.run(
          intent: "youtube.play",
          parameters: {
            "query" => query,
            "query_source" => "provided_after_prompt"
          },
          original_text: state.fetch("original_text")
        )

        { ok: result[:ok], message: result[:user_message], state: result[:state] }
      end

      def handle_open_confirmation(state, text)
        parsed = ConfirmationParser.new.parse(text)

        if parsed.cancelled
          state["status"] = "cancelled"
          state["updated_at"] = Time.now.iso8601
          state["next_expected"] = "none"
          state["verification"]["complete"] = false
          state["handler_response"] = handler_response_metadata("cancelled_before_open")
          save_state(state)

          return {
            ok: true,
            message: "YouTube play workflow cancelled.\nNo browser was opened.",
            state: state
          }
        end

        unless parsed.confirmed
          return { ok: false, message: render_candidate_confirmation(state), state: state }
        end

        watch_url = state.dig("candidate", "watch_url").to_s
        args = ["--url", watch_url, "--confirm"]

        skill_runner = SkillRunner.new(registry: SkillRegistry.new)
        result = skill_runner.run("youtube.song_search", args: args)
        task_log_path = TaskLog.new.write(kind: "skill.youtube.song_search", payload: result)

        state["status"] = result[:ok] ? "complete" : "failed"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = result[:ok] ? "reflection_offer" : "none"
        state["skill_runs"] << { "skill" => "youtube.song_search", "args" => args, "ok" => result[:ok], "task_log" => task_log_path }
        state["open_result"] = result[:json] || {}
        state["handler_response"] = handler_response_metadata("open_confirmation")
        state["verification"]["browser_launch_log"] = task_log_path
        state["verification"]["browser_launch_attempted"] = result.dig(:json, "verification", "browser_launch_attempted") || false
        state["verification"]["opened_watch_url"] = watch_url
        state["verification"]["complete"] = result[:ok]
        save_state(state)

        {
          ok: result[:ok],
          message: render_open_execution(state, result),
          state: state
        }
      end

      def handle_search_confirmation(state, text)
        parsed = ConfirmationParser.new.parse(text)

        if parsed.cancelled
          state["status"] = "cancelled"
          state["updated_at"] = Time.now.iso8601
          state["next_expected"] = "none"
          state["verification"]["complete"] = false
          state["handler_response"] = handler_response_metadata("cancelled_before_search")
          save_state(state)

          return {
            ok: true,
            message: "YouTube search fallback cancelled.\nNo browser was opened.",
            state: state
          }
        end

        unless parsed.confirmed
          return { ok: false, message: render_fallback_confirmation(state), state: state }
        end

        query = state.dig("parameters", "query").to_s
        args = ["--query", query, "--confirm"]

        skill_runner = SkillRunner.new(registry: SkillRegistry.new)
        result = skill_runner.run("youtube.song_search", args: args)
        task_log_path = TaskLog.new.write(kind: "skill.youtube.song_search", payload: result)

        state["status"] = result[:ok] ? "complete" : "failed"
        state["updated_at"] = Time.now.iso8601
        state["next_expected"] = result[:ok] ? "reflection_offer" : "none"
        state["skill_runs"] << { "skill" => "youtube.song_search", "args" => args, "ok" => result[:ok], "task_log" => task_log_path }
        state["open_result"] = result[:json] || {}
        state["handler_response"] = handler_response_metadata("search_confirmation")
        state["verification"]["browser_launch_log"] = task_log_path
        state["verification"]["browser_launch_attempted"] = result.dig(:json, "verification", "browser_launch_attempted") || false
        state["verification"]["complete"] = result[:ok]
        save_state(state)

        {
          ok: result[:ok],
          message: render_open_execution(state, result),
          state: state
        }
      end

      def base_state(status:, original_text:, parameters:, next_expected:, verification:, skill_runs: [])
        {
          "workflow" => "youtube.play",
          "status" => status,
          "generated_at" => Time.now.iso8601,
          "updated_at" => Time.now.iso8601,
          "original_text" => original_text,
          "parameters" => parameters,
          "skill_runs" => skill_runs,
          "next_expected" => next_expected,
          "verification" => verification
        }
      end

      def enrich_handler_state(state)
        state["handler_execution"] = {
          "checked" => true,
          "handler" => self.class.name,
          "intent" => intent,
          "delegated_to_existing_workflow_method" => false
        }
        save_state(state) if state["workflow_path"]
        state
      end

      def handler_response_metadata(action)
        {
          "checked" => true,
          "handler" => self.class.name,
          "intent" => intent,
          "action" => action,
          "handled_at" => Time.now.iso8601
        }
      end

      def write_workflow_state(state)
        FileUtils.mkdir_p(SESSION_ROOT)
        timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        path = File.join(SESSION_ROOT, "#{timestamp}-youtube.play.json")
        state["workflow_path"] = path
        File.write(path, JSON.pretty_generate(state))
        path
      end

      def save_state(state)
        path = state.fetch("workflow_path")
        File.write(path, JSON.pretty_generate(state))
        path
      end

      def cancel_text?(normalized)
        normalized.match?(/\bcancel\b/) ||
          normalized.match?(/\bstop\b/) ||
          normalized.match?(/\bnever mind\b/) ||
          normalized.match?(/\bnevermind\b/) ||
          normalized.match?(/\bquit\b/)
      end

      def render_needs_query(_state)
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

      def render_candidate_confirmation(state)
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

      def render_fallback_confirmation(state)
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

      def render_resolve_failed(state)
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

      def render_open_execution(state, result)
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
end
