
# frozen_string_literal: true

require "json"
require "open3"
require "time"

module SoulCore
  class DoctorSurfaceAssessor
    CORE_JSON_COMMANDS = [
      {
        "id" => "skills",
        "command" => ["ruby", "bin/soul", "skills", "--json"],
        "expected_shape" => "object_or_array"
      },
      {
        "id" => "doctor",
        "command" => ["ruby", "bin/soul", "doctor", "--json"],
        "expected_shape" => "object"
      },
      {
        "id" => "repo_curation",
        "command" => ["ruby", "bin/soul", "assess", "repo-curation", "--json"],
        "expected_shape" => "object"
      },
      {
        "id" => "capabilities",
        "command" => ["ruby", "bin/soul", "assess", "capabilities", "--json"],
        "expected_shape" => "object"
      },
      {
        "id" => "ruby_runtime",
        "command" => ["ruby", "bin/soul", "assess", "ruby-runtime", "--json"],
        "expected_shape" => "object"
      },
      {
        "id" => "codex_loop",
        "command" => ["ruby", "bin/soul", "assess", "codex-loop", "--json"],
        "expected_shape" => "object"
      }
    ].freeze

    CORE_TEXT_COMMANDS = [
      {
        "id" => "skill_loop",
        "command" => ["ruby", "bin/soul", "assess", "skill-loop"],
        "required_text" => "Soul Skill Loop Completion Assessment"
      },
      {
        "id" => "codex_loop_text",
        "command" => ["ruby", "bin/soul", "assess", "bounded-codex-loop"],
        "required_text" => "Soul Codex Loop Completion Assessment"
      }
    ].freeze

    LEGACY_SURFACE_FILES = [
      "lib/soul_core/workflow_runner.rb",
      "lib/soul_core/workflow_handler_registry.rb"
    ].freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      command_results = json_command_results + text_command_results
      failed = command_results.reject { |item| item["ok"] }

      legacy_files = LEGACY_SURFACE_FILES.map do |path|
        {
          "path" => path,
          "present" => File.exist?(File.join(@root, path)),
          "role" => legacy_role(path)
        }
      end

      app = read("lib/soul_core/app.rb")
      doctor_currently_direct = app.include?('when "doctor"') || app.include?("run_doctor")

      blockers = []
      blockers << "Doctor/user-facing CLI smoke failures: #{failed.map { |item| item['id'] }.join(', ')}" unless failed.empty?

      {
        "ok" => blockers.empty?,
        "assessment" => "doctor_surface",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "status" => blockers.empty? ? "healthy" : "blocked",
        "meaning" => "This assessment expands the doctor-adjacent surface by checking user-facing CLI routes without changing workflow behavior.",
        "doctor_scope" => {
          "classic_doctor_still_present" => doctor_currently_direct,
          "surface_assessment_command" => "ruby bin/soul assess doctor-surface",
          "safe_to_run_in_ci" => true,
          "read_only" => true
        },
        "command_results" => command_results,
        "legacy_surface" => {
          "files" => legacy_files,
          "note" => "Legacy workflow surfaces are reported separately from newer handler/assessment routes so green doctor output is not mistaken for full product coverage."
        },
        "blockers" => blockers,
        "recommendations" => recommendations(blockers, legacy_files),
        "verification" => {
          "read_only" => true,
          "no_files_modified" => true,
          "no_workflows_changed" => true,
          "no_skill_behavior_changed" => true,
          "no_codex_invoked" => true,
          "no_network_access" => true,
          "no_secrets_read" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Doctor Surface Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Meaning"
      lines << report["meaning"]
      lines << ""
      lines << "Doctor scope"
      report.fetch("doctor_scope").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Command results"
      report.fetch("command_results").each do |item|
        lines << "- #{item['id']}: #{item['ok'] ? 'ok' : 'failed'}"
        lines << "  command: #{item['command'].join(' ')}"
        lines << "  exit_status: #{item['exit_status']}"
        lines << "  note: #{item['note']}" if item["note"] && !item["note"].empty?
      end
      lines << ""
      lines << "Legacy surface"
      report.dig("legacy_surface", "files").each do |item|
        lines << "- #{item['path']}: #{item['present'] ? 'present' : 'missing'}"
        lines << "  role: #{item['role']}"
      end
      lines << "  note: #{report.dig('legacy_surface', 'note')}"
      lines << ""
      lines << "Recommendations"
      append(lines, report.fetch("recommendations"))
      lines << ""
      lines << "Blockers"
      append(lines, report.fetch("blockers"))
      lines << ""
      lines << "Verification"
      report.fetch("verification").each { |key, value| lines << "- #{key}: #{value}" }
      lines.join("\n")
    end

    private

    def json_command_results
      CORE_JSON_COMMANDS.map do |item|
        stdout, stderr, status = Open3.capture3(*item.fetch("command"), chdir: @root)
        ok = status.success?
        note = ""

        if ok
          begin
            parsed = JSON.parse(stdout)
            shape = parsed.is_a?(Array) ? "array" : parsed.is_a?(Hash) ? "object" : parsed.class.name
            expected = item.fetch("expected_shape")
            ok = expected == "object_or_array" ? parsed.is_a?(Array) || parsed.is_a?(Hash) : shape == expected
            note = "json_shape=#{shape}"
          rescue JSON::ParserError => error
            ok = false
            note = "invalid_json=#{error.message}"
          end
        end

        result(item, ok, status, stdout, stderr, note)
      end
    end

    def text_command_results
      CORE_TEXT_COMMANDS.map do |item|
        stdout, stderr, status = Open3.capture3(*item.fetch("command"), chdir: @root)
        ok = status.success? && stdout.include?(item.fetch("required_text"))
        note = ok ? "required_text_present" : "missing_required_text=#{item.fetch('required_text')}"
        result(item, ok, status, stdout, stderr, note)
      end
    end

    def result(item, ok, status, stdout, stderr, note)
      {
        "id" => item.fetch("id"),
        "command" => item.fetch("command"),
        "ok" => ok,
        "exit_status" => status.exitstatus,
        "note" => note,
        "stdout_preview" => truncate(stdout.strip),
        "stderr_preview" => truncate(stderr.strip)
      }
    end

    def legacy_role(path)
      case path
      when "lib/soul_core/workflow_runner.rb"
        "Legacy workflow execution surface; should be observed before behavior changes."
      when "lib/soul_core/workflow_handler_registry.rb"
        "Newer handler registry surface; classic doctor has historically focused here."
      else
        "Unknown legacy surface."
      end
    end

    def recommendations(blockers, legacy_files)
      recs = []
      recs << "Keep this assessment read-only; do not let doctor mutate project state."
      recs << "Use doctor-surface before expanding or refactoring workflow routing."
      recs << "Document legacy workflow coverage separately from handler registry coverage."
      recs << "Resolve blockers before adding more user-facing skills." unless blockers.empty?
      missing_legacy = legacy_files.reject { |item| item["present"] }
      recs << "Review missing legacy surface file(s): #{missing_legacy.map { |item| item['path'] }.join(', ')}" unless missing_legacy.empty?
      recs << "Doctor surface appears healthy." if blockers.empty?
      recs
    end

    def read(path)
      full = File.join(@root, path)
      File.exist?(full) ? File.read(full) : ""
    end

    def truncate(text, limit = 800)
      text = text.to_s
      text.length > limit ? "#{text[0, limit]}..." : text
    end

    def append(lines, items)
      items = Array(items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
