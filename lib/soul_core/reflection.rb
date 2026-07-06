# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module SoulCore
  class Reflection
    def initialize(log_root: "Soul/logs/tasks", pending_root: "Soul/reflection/pending")
      @log_root = log_root
      @pending_root = pending_root
      FileUtils.mkdir_p(@pending_root)
    end

    def latest_log_path
      logs = Dir.glob(File.join(@log_root, "*.json")).sort
      logs.last
    end

    def reflect(target = "last")
      source_path = target == "last" ? latest_log_path : target
      raise "no task logs found in #{@log_root}" unless source_path
      raise "task log not found: #{source_path}" unless File.exist?(source_path)

      payload = JSON.parse(File.read(source_path))
      candidate = build_candidate(source_path, payload)

      timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      slug = candidate.fetch(:slug)
      json_path = File.join(@pending_root, "#{timestamp}-#{slug}.json")
      md_path = File.join(@pending_root, "#{timestamp}-#{slug}.md")

      File.write(json_path, JSON.pretty_generate(candidate))
      File.write(md_path, render_markdown(candidate))

      {
        ok: true,
        source_log: source_path,
        json_path: json_path,
        markdown_path: md_path,
        candidate: candidate
      }
    end

    def pending
      Dir.glob(File.join(@pending_root, "*.{md,json}")).sort
    end

    private

    def build_candidate(source_path, payload)
      task_kind = infer_task_kind(payload, source_path)
      now = Time.now.iso8601

      base = {
        slug: safe_slug(task_kind),
        type: "reflection_candidate",
        generated_at: now,
        source_log: source_path,
        task_kind: task_kind,
        status: "pending_review",
        promote_automatically: false,
        observations: [],
        candidate_lessons: [],
        candidate_rules: [],
        candidate_memory_updates: [],
        candidate_skill_updates: [],
        verification_summary: {},
        warnings: []
      }

      case task_kind
      when "skill.downloads.move_to_trash"
        reflect_downloads_move_to_trash(base, payload)
      when "skill.downloads.cleanup_plan"
        reflect_downloads_cleanup_plan(base, payload)
      when "skill.downloads.inspect"
        reflect_downloads_inspect(base, payload)
      when "skill.system.status"
        reflect_system_status(base, payload)
      when /^ask\./
        reflect_ask(base, payload)
      else
        reflect_generic(base, payload)
      end

      base
    end

    def infer_task_kind(payload, source_path)
      if payload.is_a?(Hash) && payload["skill"]
        "skill.#{payload['skill']}"
      elsif File.basename(source_path).include?("ask.fast")
        "ask.fast"
      elsif File.basename(source_path).include?("ask.think")
        "ask.think"
      else
        File.basename(source_path, ".json")
      end
    end

    def reflect_downloads_move_to_trash(base, payload)
      data = payload["json"] || payload
      verification = data["verification"] || {}

      base[:observations] << "downloads.move_to_trash completed with status #{data['status']} in #{data['mode']} mode."
      base[:observations] << "Outcome: #{data['outcome']}." if data["outcome"]
      base[:observations] << "Recommendation: #{data['recommendation']}." if data["recommendation"]
      base[:observations] << "Planned candidates: #{data['planned_candidate_count']}."
      base[:observations] << "Moved files: #{verification['moved_files']}."
      base[:observations] << "Moved directories: #{verification['moved_directories']}."
      base[:observations] << "Job complete: #{verification['job_complete']}."
      base[:observations] << "Trash is terminal cleanup action: #{verification['trash_is_terminal_cleanup_action']}."

      if verification["job_complete"] == true
        base[:candidate_lessons] << "A Downloads cleanup job is complete when all approved planned items are successfully moved to Trash."
      end

      base[:candidate_rules] << "Moving approved cleanup candidates to Trash is the terminal cleanup action for Soul/."
      base[:candidate_rules] << "Soul/ should not empty Trash or permanently delete trashed items as part of normal cleanup."
      base[:candidate_rules] << "Trash retention and emptying are left to the operating system or the user."
      base[:candidate_rules] << "downloads.move_to_trash must consume a verified downloads.cleanup_plan log."
      base[:candidate_rules] << "downloads.move_to_trash must require --execute and --confirm MOVE_TO_TRASH before moving anything."

      base[:verification_summary] = verification
    end

    def reflect_downloads_cleanup_plan(base, payload)
      data = payload["json"] || payload
      summary = data["summary"] || {}
      verification = data["verification"] || {}
      proposed = data["proposed_actions"] || {}

      base[:observations] << "downloads.cleanup_plan completed with status #{data['status']}."
      base[:observations] << "Target path was #{data['target_path']}." if data["target_path"]
      base[:observations] << "Cleanup candidates: #{summary['cleanup_candidate_count'] || 0}."
      base[:observations] << "Candidate folders: #{summary['cleanup_candidate_directory_count'] || 0}."
      base[:observations] << "Protected entries: #{summary['protected_count'] || 0}."
      base[:observations] << "Manual review entries: #{summary['uncertain_count'] || proposed.fetch('manual_review_required', []).length}."
      base[:observations] << "Recommendation: #{data['recommendation']}." if data["recommendation"]

      if (summary["cleanup_candidate_count"].to_i).zero?
        base[:candidate_lessons] << "Current Downloads scan produced no move-to-trash candidates at the configured age threshold."
      else
        base[:candidate_lessons] << "Downloads cleanup planning can identify top-level files and folders without moving them."
      end

      base[:candidate_rules] << "Top-level directories in Downloads may be cleanup candidates when they are older than the threshold and not protected."
      base[:candidate_rules] << "downloads.cleanup_plan must remain read-only and must not move or delete files."
      base[:candidate_rules] << "A move-to-trash skill must require explicit approval and consume a verified cleanup plan."

      base[:verification_summary] = {
        read_only: verification["read_only"],
        moved_files: verification["moved_files"],
        deleted_files: verification["deleted_files"],
        recursive_scan: verification["recursive_scan"],
        top_level_only: verification["top_level_only"],
        source_inspection_read_only: verification["source_inspection_read_only"],
        approval_required_before_execution: verification["approval_required_before_execution"]
      }
    end

    def reflect_downloads_inspect(base, payload)
      data = payload["json"] || payload
      summary = data["summary"] || {}
      verification = data["verification"] || {}

      base[:observations] << "downloads.inspect completed with status #{data['status']}."
      base[:observations] << "Inspected #{summary['total_entries_inspected'] || 0} top-level entries."
      base[:observations] << "Protected #{summary['protected_count'] || 0} entries."
      base[:observations] << "Marked #{summary['uncertain_count'] || 0} entries as uncertain."
      base[:observations] << "Found #{summary['cleanup_candidate_count'] || 0} cleanup candidates."
      base[:observations] << "Candidate directories: #{summary['cleanup_candidate_directory_count'] || 0}."

      base[:candidate_lessons] << "downloads.inspect provides a safe read-only file and top-level folder classification layer for later planning."
      base[:candidate_rules] << "downloads.inspect should never move, rename, or delete files."
      base[:candidate_rules] << "Protected project terms must be checked before any entry is considered a cleanup candidate."

      base[:verification_summary] = {
        read_only: verification["read_only"],
        moved_files: verification["moved_files"],
        deleted_files: verification["deleted_files"],
        recursive_scan: verification["recursive_scan"],
        top_level_only: verification["top_level_only"],
        protected_files_excluded_from_cleanup_candidates: verification["protected_files_excluded_from_cleanup_candidates"]
      }
    end

    def reflect_system_status(base, payload)
      data = payload["json"] || payload
      verification = data["verification"] || {}
      runtime = data["runtime"] || {}

      base[:observations] << "system.status completed with status #{data['status']}."
      base[:observations] << "Model endpoint: #{runtime['base_url']}." if runtime["base_url"]
      base[:observations] << "Endpoint healthy: #{verification['endpoint_healthy']}."
      base[:observations] << "Service active: #{verification['service_active']}."
      base[:observations] << "Model endpoint reachable: #{verification['model_endpoint_reachable']}."

      base[:candidate_lessons] << "system.status is a verified read-only baseline skill for checking Soul/ runtime health."
      base[:candidate_rules] << "Runtime status should distinguish host process memory from GPU VRAM usage in future output."

      base[:verification_summary] = verification
    end

    def reflect_ask(base, payload)
      content = payload["content"].to_s
      reasoning = payload["reasoning_content"].to_s

      base[:observations] << "LLM ask task completed."
      base[:observations] << "Final content was present: #{!content.strip.empty?}."
      base[:observations] << "Reasoning content was present: #{!reasoning.strip.empty?}."

      if base[:task_kind] == "ask.fast"
        base[:candidate_rules] << "FAST mode should continue using /no_think to avoid spending output budget on reasoning."
      elsif base[:task_kind] == "ask.think"
        base[:candidate_rules] << "THINK mode should be used deliberately for planning, reflection, and failure analysis."
      end

      base[:candidate_lessons] << "LLM responses should be logged with both content and reasoning_content fields when available."
    end

    def reflect_generic(base, payload)
      base[:observations] << "Generic task log reflected."
      base[:candidate_lessons] << "No specific reflection handler exists for this task kind yet."
      base[:candidate_skill_updates] << "Consider adding a specific reflection handler for #{base[:task_kind]} if this task becomes common."
      base[:verification_summary] = payload["verification"] || {}
    end

    def safe_slug(value)
      value.to_s.downcase.gsub(/[^a-z0-9_.-]+/, "_").gsub(/^_+|_+$/, "")
    end

    def render_markdown(candidate)
      lines = []
      lines << "# Soul/ Reflection Candidate"
      lines << ""
      lines << "- Type: `#{candidate[:type]}`"
      lines << "- Status: `#{candidate[:status]}`"
      lines << "- Generated: `#{candidate[:generated_at]}`"
      lines << "- Task kind: `#{candidate[:task_kind]}`"
      lines << "- Source log: `#{candidate[:source_log]}`"
      lines << "- Promote automatically: `#{candidate[:promote_automatically]}`"
      lines << ""

      markdown_section(lines, "Observations", candidate[:observations])
      markdown_section(lines, "Candidate Lessons", candidate[:candidate_lessons])
      markdown_section(lines, "Candidate Rules", candidate[:candidate_rules])
      markdown_section(lines, "Candidate Memory Updates", candidate[:candidate_memory_updates])
      markdown_section(lines, "Candidate Skill Updates", candidate[:candidate_skill_updates])

      lines << "## Verification Summary"
      lines << ""
      if candidate[:verification_summary].empty?
        lines << "- None captured."
      else
        candidate[:verification_summary].each do |key, value|
          lines << "- `#{key}`: `#{value}`"
        end
      end
      lines << ""

      markdown_section(lines, "Warnings", candidate[:warnings])
      lines.join("\n")
    end

    def markdown_section(lines, title, values)
      lines << "## #{title}"
      lines << ""
      if values.empty?
        lines << "- None."
      else
        values.each { |value| lines << "- #{value}" }
      end
      lines << ""
    end
  end
end
