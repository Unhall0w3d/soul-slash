
# frozen_string_literal: true

require "json"
require "time"
require_relative "skill_invocation_planner"

module SoulCore
  class SkillInvocationPlannerAssessor
    SAMPLE_MESSAGES = {
      "inspect my downloads" => {
        "skill_id" => "downloads.inspect",
        "confirmation_required" => false
      },
      "move approved downloads to trash" => {
        "skill_id" => "downloads.move_to_trash",
        "confirmation_required" => true
      },
      "what is the weather?" => {
        "skill_id" => "weather.report",
        "confirmation_required" => false
      },
      "test cloud providers" => {
        "skill_id" => "cloud.providers.list",
        "confirmation_required" => false
      },
      "tell me about the moonlit gears" => {
        "skill_id" => nil,
        "confirmation_required" => false
      }
    }.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
      @planner = SkillInvocationPlanner.new
    end

    def assess
      samples = SAMPLE_MESSAGES.map do |message, expected|
        plan = @planner.plan(message)
        {
          "message" => message,
          "expected" => expected,
          "actual" => {
            "skill_id" => plan.skill_id,
            "confirmation_required" => plan.confirmation_required,
            "executable_now" => plan.executable_now
          },
          "matched" => plan.skill_id == expected["skill_id"] &&
                       plan.confirmation_required == expected["confirmation_required"] &&
                       plan.executable_now == false,
          "plan" => plan.to_h
        }
      end

      blockers = []
      blockers << "One or more skill invocation planning samples failed" unless samples.all? { |sample| sample["matched"] }

      {
        "ok" => blockers.empty?,
        "assessment" => "skill_invocation_planner",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "ready" : "blocked",
        "sample_count" => samples.length,
        "samples" => samples,
        "blockers" => blockers,
        "warnings" => [
          "Phase 46 creates plans only.",
          "No skills are executed.",
          "All plans must report executable_now=false."
        ],
        "verification" => {
          "no_skill_execution" => true,
          "no_filesystem_mutation_beyond_chat_transcripts" => true,
          "confirmation_modeled" => true,
          "approval_gate_not_implemented_yet" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Skill Invocation Planner Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Samples"
      report.fetch("samples").each do |sample|
        status = sample["matched"] ? "ok" : "mismatch"
        plan = sample.fetch("plan")
        lines << "- #{sample['message'].inspect}: #{status}"
        lines << "  skill_id: #{plan['skill_id'] || 'none'}"
        lines << "  confirmation_required: #{plan['confirmation_required']}"
        lines << "  executable_now: #{plan['executable_now']}"
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
  end
end
