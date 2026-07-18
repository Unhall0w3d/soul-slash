# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "memory_paths"

module SoulCore
  class ReflectionReview
    def initialize(root: Dir.pwd,
                   pending_root: "Soul/reflection/pending",
                   approved_root: "Soul/reflection/approved",
                   rejected_root: "Soul/reflection/rejected",
                   approved_lessons_path: nil,
                   approved_rules_path: nil)
      paths = MemoryPaths.new(root: root)
      @pending_root = pending_root
      @approved_root = approved_root
      @rejected_root = rejected_root
      @approved_lessons_path = approved_lessons_path || paths.write_path("approved_lessons.md")
      @approved_rules_path = approved_rules_path || paths.write_path("approved_rules.md")

      [@pending_root, @approved_root, @rejected_root, File.dirname(@approved_lessons_path)].each do |path|
        FileUtils.mkdir_p(path)
      end
    end

    def list_pending
      Dir.glob(File.join(@pending_root, "*.json")).sort
    end

    def show(target = "latest")
      json_path = resolve_pending_json(target)
      md_path = sibling_markdown(json_path)

      if File.exist?(md_path)
        File.read(md_path)
      else
        JSON.pretty_generate(JSON.parse(File.read(json_path)))
      end
    end

    def approve(target = "latest", note: nil)
      json_path = resolve_pending_json(target)
      md_path = sibling_markdown(json_path)
      candidate = JSON.parse(File.read(json_path))

      reviewed_at = Time.now.iso8601
      candidate["review_status"] = "approved"
      candidate["reviewed_at"] = reviewed_at
      candidate["review_note"] = note if note && !note.strip.empty?
      candidate["promoted_by_command"] = "ruby bin/soul reflection approve"

      append_approved_items(
        candidate: candidate,
        lessons: Array(candidate["candidate_lessons"]),
        rules: Array(candidate["candidate_rules"])
      )

      approved_json_path = File.join(@approved_root, File.basename(json_path))
      approved_md_path = File.join(@approved_root, File.basename(md_path))

      File.write(json_path, JSON.pretty_generate(candidate))
      if File.exist?(md_path)
        File.write(md_path, render_reviewed_markdown(candidate, File.read(md_path)))
      end

      FileUtils.mv(json_path, approved_json_path)
      FileUtils.mv(md_path, approved_md_path) if File.exist?(md_path)

      {
        ok: true,
        action: "approved",
        reviewed_at: reviewed_at,
        approved_json_path: approved_json_path,
        approved_markdown_path: File.exist?(approved_md_path) ? approved_md_path : nil,
        lessons_appended_to: @approved_lessons_path,
        rules_appended_to: @approved_rules_path
      }
    end

    def reject(target = "latest", reason: nil)
      json_path = resolve_pending_json(target)
      md_path = sibling_markdown(json_path)
      candidate = JSON.parse(File.read(json_path))

      reviewed_at = Time.now.iso8601
      candidate["review_status"] = "rejected"
      candidate["reviewed_at"] = reviewed_at
      candidate["rejection_reason"] = reason.to_s.strip.empty? ? "No reason provided." : reason
      candidate["promoted_by_command"] = nil

      rejected_json_path = File.join(@rejected_root, File.basename(json_path))
      rejected_md_path = File.join(@rejected_root, File.basename(md_path))

      File.write(json_path, JSON.pretty_generate(candidate))
      if File.exist?(md_path)
        File.write(md_path, render_reviewed_markdown(candidate, File.read(md_path)))
      end

      FileUtils.mv(json_path, rejected_json_path)
      FileUtils.mv(md_path, rejected_md_path) if File.exist?(md_path)

      {
        ok: true,
        action: "rejected",
        reviewed_at: reviewed_at,
        rejected_json_path: rejected_json_path,
        rejected_markdown_path: File.exist?(rejected_md_path) ? rejected_md_path : nil
      }
    end

    private

    def resolve_pending_json(target)
      target ||= "latest"

      if target == "latest" || target == "last"
        path = list_pending.last
        raise "no pending reflection candidates found" unless path

        return path
      end

      if File.exist?(target)
        return target if File.extname(target) == ".json"

        raise "target exists but is not a JSON reflection candidate: #{target}"
      end

      matches = list_pending.select { |path| File.basename(path).include?(target) }
      raise "no pending reflection candidate matched: #{target}" if matches.empty?
      raise "multiple pending reflection candidates matched #{target}: #{matches.join(', ')}" if matches.length > 1

      matches.first
    end

    def sibling_markdown(json_path)
      json_path.sub(/\.json$/, ".md")
    end

    def append_approved_items(candidate:, lessons:, rules:)
      timestamp = Time.now.iso8601
      source = candidate["source_log"]
      task_kind = candidate["task_kind"]

      unless lessons.empty?
        File.open(@approved_lessons_path, "a") do |f|
          f.puts
          f.puts "## #{timestamp} - #{task_kind}"
          f.puts
          f.puts "Source: `#{source}`"
          f.puts
          f.puts
          lessons.each { |lesson| f.puts "- #{lesson}" }
        end
      end

      unless rules.empty?
        File.open(@approved_rules_path, "a") do |f|
          f.puts
          f.puts "## #{timestamp} - #{task_kind}"
          f.puts
          f.puts "Source: `#{source}`"
          f.puts
          f.puts
          rules.each { |rule| f.puts "- #{rule}" }
        end
      end
    end

    def render_reviewed_markdown(candidate, original_markdown)
      lines = []
      lines << original_markdown.rstrip
      lines << ""
      lines << "## Review"
      lines << ""
      lines << "- Review status: `#{candidate['review_status']}`"
      lines << "- Reviewed at: `#{candidate['reviewed_at']}`"
      lines << "- Review note: #{candidate['review_note']}" if candidate["review_note"]
      lines << "- Rejection reason: #{candidate['rejection_reason']}" if candidate["rejection_reason"]
      lines << ""
      lines.join("\n")
    end
  end
end
