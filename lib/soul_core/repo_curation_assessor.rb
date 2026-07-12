
# frozen_string_literal: true

require "json"
require "open3"
require "time"

module SoulCore
  class RepoCurationAssessor
    TRACKED_OVERLAY_NOTE = %r{\Adocs/overlays/README_.*(PHASE|REPAIR).*\.md\z}.freeze
    TRACKED_OVERLAY_DIRECTORY = %r{(?:\A|/)[^/]+_overlay/}.freeze
    UNTRACKED_REVIEW_CANDIDATE = %r{\A(\?\? )?(docs/(overlays|workflows)/.*|scripts/verify-.*\.rb)}.freeze
    GENERATED_LOCAL = %r{\A(\?\? )?(overlay_files/|Soul/improvement/proposals/|Soul/runtime/|README_.*(PHASE|REPAIR).*\.md)}.freeze

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      tracked = git_lines("ls-files")
      status = git_lines("status", "--porcelain")

      tracked_overlay_notes = tracked.grep(TRACKED_OVERLAY_NOTE)
      tracked_overlay_directories = tracked.grep(TRACKED_OVERLAY_DIRECTORY).map { |path| path.split('/').first + '/' }.uniq
      untracked = status.select { |line| line.start_with?("??") }.map { |line| line.sub(/\A\?\?\s*/, "") }
      untracked_review_candidates = untracked.select { |path| path.match?(UNTRACKED_REVIEW_CANDIDATE) }
      untracked_generated_local = untracked.select { |path| path.match?(GENERATED_LOCAL) }

      recommendations = []
      recommendations << recommendation("tracked_overlay_notes", "Review tracked overlay notes and either rewrite into stable docs or remove them from tracking.", tracked_overlay_notes) unless tracked_overlay_notes.empty?
      recommendations << recommendation("tracked_overlay_directories", "Remove tracked extracted overlay directories after confirming durable files exist at canonical paths.", tracked_overlay_directories) unless tracked_overlay_directories.empty?
      recommendations << recommendation("untracked_review_candidates", "Review untracked docs/verifiers and decide commit, rewrite, or delete.", untracked_review_candidates) unless untracked_review_candidates.empty?
      recommendations << recommendation("untracked_generated_local", "Remove generated local leftovers after verification, or keep them untracked while actively inspecting them.", untracked_generated_local) unless untracked_generated_local.empty?

      {
        "ok" => true,
        "assessment" => "repo_curation",
        "generated_at" => Time.now.iso8601,
        "root" => @root,
        "tracked_overlay_notes" => tracked_overlay_notes,
        "tracked_overlay_directories" => tracked_overlay_directories,
        "untracked_review_candidates" => untracked_review_candidates,
        "untracked_generated_local" => untracked_generated_local,
        "counts" => {
          "tracked_overlay_notes" => tracked_overlay_notes.length,
          "tracked_overlay_directories" => tracked_overlay_directories.length,
          "untracked_review_candidates" => untracked_review_candidates.length,
          "untracked_generated_local" => untracked_generated_local.length
        },
        "recommendations" => recommendations,
        "proposed_actions" => proposed_actions(tracked_overlay_notes, tracked_overlay_directories, untracked_review_candidates, untracked_generated_local),
        "verification" => {
          "read_only" => true,
          "no_files_modified" => true,
          "no_git_changes_performed" => true,
          "curation_only" => true
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Repo Curation Assessment"
      lines << "Generated: #{report['generated_at']}"
      lines << "Root: #{report['root']}"
      lines << ""
      lines << "Counts"
      report.fetch("counts").each { |key, value| lines << "- #{key}: #{value}" }
      lines << ""
      lines << "Tracked overlay notes"
      append_items(lines, report.fetch("tracked_overlay_notes"))
      lines << ""
      lines << "Tracked extracted overlay directories"
      append_items(lines, report.fetch("tracked_overlay_directories"))
      lines << ""
      lines << "Untracked review candidates"
      append_items(lines, report.fetch("untracked_review_candidates"))
      lines << ""
      lines << "Untracked generated/local leftovers"
      append_items(lines, report.fetch("untracked_generated_local"))
      lines << ""
      lines << "Recommendations"
      append_items(lines, report.fetch("recommendations").map { |item| "#{item['category']}: #{item['summary']} (#{item['items'].length} item(s))" })
      lines << ""
      lines << "Proposed actions"
      append_items(lines, report.fetch("proposed_actions"))
      lines.join("\n")
    end

    private

    def git_lines(*args)
      stdout, stderr, status = Open3.capture3("git", *args, chdir: @root)
      raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

      stdout.lines.map(&:chomp).reject(&:empty?)
    end

    def recommendation(category, summary, items)
      {"category" => category, "summary" => summary, "items" => items}
    end

    def proposed_actions(tracked_overlay_notes, tracked_overlay_directories, untracked_review_candidates, untracked_generated_local)
      actions = []
      unless tracked_overlay_notes.empty?
        actions << "Inspect tracked overlay notes and decide whether each should be rewritten as stable documentation or removed from tracking."
      end
      unless tracked_overlay_directories.empty?
        actions << "Remove tracked extracted overlay directories after verifying canonical copies."
      end
      unless untracked_review_candidates.empty?
        actions << "Classify each untracked review candidate as commit, rewrite, or delete."
      end
      unless untracked_generated_local.empty?
        actions << "Clean generated local leftovers after any needed inspection."
      end
      actions << "Do not run git add . during curation."
      actions << "Commit curation decisions in small, explainable groups."
      actions
    end

    def append_items(lines, items)
      if items.empty?
        lines << "- None"
      else
        items.each { |item| lines << "- #{item}" }
      end
    end
  end
end
