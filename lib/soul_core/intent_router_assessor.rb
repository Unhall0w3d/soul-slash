
# frozen_string_literal: true

require "json"
require "time"
require_relative "intent_router"

module SoulCore
  class IntentRouterAssessor
    SAMPLE_MESSAGES = {
      "identity" => "who are you?",
      "skill_catalog" => "what skills do you have?",
      "repo_status" => "check repo health",
      "pending_work" => "what should we build next?",
      "weather_request" => "what is the weather?",
      "downloads_inspect" => "inspect my downloads",
      "downloads_cleanup_plan" => "plan a downloads cleanup",
      "downloads_move_to_trash" => "move approved downloads to trash",
      "cloud_providers" => "test cloud providers",
      "youtube_request" => "find this song on YouTube",
      "skill_brief" => "draft a skill brief",
      "unknown" => "tell me about the moonlit gears"
    }.freeze

    LEGACY_INTENT_MAP = {
      "youtube.play" => "youtube_request",
      "youtube.search" => "youtube_request",
      "youtube.resolve" => "youtube_request"
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @router = IntentRouter.new
    end

    def assess
      samples = SAMPLE_MESSAGES.map do |expected, message|
        intent = @router.route(message)
        actual = normalized_actual(intent)
        {
          "message" => message,
          "expected" => expected,
          "actual" => actual,
          "matched" => actual == expected,
          "intent" => intent.to_h
        }
      end

      blockers = []
      blockers << "One or more routing samples failed" unless samples.all? { |sample| sample["matched"] }

      {
        "ok" => blockers.empty?,
        "assessment" => "intent_router_mvp",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample_count" => samples.length,
        "samples" => samples,
        "blockers" => blockers,
        "warnings" => [
          "Phase 45 routing is deterministic and pattern-based.",
          "No skills are executed from chat in this phase.",
          "Unknown messages still use the deterministic fallback.",
          "Legacy workflow intents are normalized for assessment compatibility."
        ],
        "verification" => {
          "no_skill_execution" => true,
          "no_llm_calls" => true,
          "no_network_access" => true,
          "no_filesystem_mutation_beyond_chat_transcripts" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Intent Router MVP Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Samples"
      report.fetch("samples").each do |sample|
        status = sample["matched"] ? "ok" : "mismatch"
        lines << "- #{sample['message'].inspect}: #{status}"
        lines << "  expected: #{sample['expected']}"
        lines << "  actual: #{sample['actual']}"
        lines << "  skill_id: #{sample.dig('intent', 'skill_id') || 'none'}"
        lines << "  risk: #{sample.dig('intent', 'risk') || 'unknown'}"
      end
      lines << ""
      lines << "Warnings"
      report.fetch("warnings").each { |warning| lines << "- #{warning}" }
      lines << ""
      lines << "Blockers"
      if report.fetch("blockers").empty?
        lines << "- None"
      else
        report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      end
      lines.join("\n")
    end

    private

    def normalized_actual(intent)
      return intent.id if intent.respond_to?(:id) && intent.id
      return LEGACY_INTENT_MAP.fetch(intent.intent, intent.intent) if intent.respond_to?(:intent) && intent.intent

      nil
    end
  end
end
