#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "time"

options = {
  path: File.join(Dir.home, "Downloads"),
  older_than_days: 30,
  max_entries: 5000,
  include_directories: true
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: plan.rb [--path PATH] [--older-than-days N] [--max-entries N] [--exclude-directories]"

  opts.on("--path PATH", "Directory to inspect. Defaults to ~/Downloads.") do |value|
    options[:path] = value
  end

  opts.on("--older-than-days N", Integer, "Age threshold for cleanup candidates. Defaults to 30.") do |value|
    options[:older_than_days] = value
  end

  opts.on("--max-entries N", Integer, "Maximum top-level entries to inspect. Defaults to 5000.") do |value|
    options[:max_entries] = value
  end

  opts.on("--exclude-directories", "Do not classify top-level directories as cleanup candidates.") do
    options[:include_directories] = false
  end
end

begin
  parser.parse!(ARGV)
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  puts JSON.pretty_generate({
    skill: "downloads.cleanup_plan",
    status: "error",
    error: "#{e.class}: #{e.message}",
    usage: parser.to_s
  })
  exit 2
end

inspect_path = File.join("Soul", "skills", "downloads", "inspect.rb")

unless File.exist?(inspect_path)
  puts JSON.pretty_generate({
    skill: "downloads.cleanup_plan",
    status: "error",
    error: "required inspection skill missing",
    missing_path: inspect_path
  })
  exit 1
end

inspect_args = [
  "--path", options[:path],
  "--older-than-days", options[:older_than_days].to_s,
  "--max-entries", options[:max_entries].to_s
]
inspect_args << "--exclude-directories" unless options[:include_directories]

stdout, stderr, status = Open3.capture3("ruby", inspect_path, *inspect_args)

unless status.success?
  puts JSON.pretty_generate({
    skill: "downloads.cleanup_plan",
    generated_at: Time.now.iso8601,
    status: "error",
    error: "downloads.inspect failed",
    inspect_exit_status: status.exitstatus,
    inspect_stdout: stdout,
    inspect_stderr: stderr,
    verification: {
      read_only: true,
      moved_files: 0,
      deleted_files: 0
    }
  })
  exit 1
end

inspection = begin
  JSON.parse(stdout)
rescue JSON::ParserError => e
  puts JSON.pretty_generate({
    skill: "downloads.cleanup_plan",
    generated_at: Time.now.iso8601,
    status: "error",
    error: "downloads.inspect did not return valid JSON: #{e.message}",
    inspect_stdout_preview: stdout[0, 1000],
    inspect_stderr: stderr,
    verification: {
      read_only: true,
      moved_files: 0,
      deleted_files: 0
    }
  })
  exit 1
end

summary = inspection.fetch("summary", {})
cleanup_candidates = inspection.fetch("cleanup_candidates", [])
protected_files = inspection.fetch("protected_files", [])
uncertain = inspection.fetch("uncertain", [])
warnings = Array(inspection.fetch("warnings", []))

candidate_actions = cleanup_candidates.map do |item|
  {
    action: "would_move_to_trash_after_approval",
    path: item["path"],
    name: item["name"],
    type: item["type"],
    size_human: item["size_human"],
    age_days: item["age_days"],
    directory_summary: item["directory_summary"],
    reasons: item["reasons"]
  }
end

manual_review = uncertain.map do |item|
  {
    action: "manual_review_required",
    path: item["path"],
    name: item["name"],
    type: item["type"],
    reasons: item["reasons"]
  }
end

protected_summary = protected_files.map do |item|
  {
    action: "keep_protected",
    path: item["path"],
    name: item["name"],
    type: item["type"],
    matched_terms: item["matched_terms"],
    reasons: item["reasons"]
  }
end

recommendation =
  if cleanup_candidates.empty? && uncertain.empty?
    "No cleanup action recommended. No old cleanup candidates or uncertain entries were found."
  elsif cleanup_candidates.empty?
    "No files or folders are currently recommended for cleanup. Review uncertain entries manually before considering any action."
  else
    "Cleanup candidates exist. Review the plan before running downloads.move_to_trash with explicit approval."
  end

markdown_lines = []
markdown_lines << "# Downloads Cleanup Plan"
markdown_lines << ""
markdown_lines << "Target: `#{inspection['target_path']}`"
markdown_lines << "Threshold: top-level files/folders older than #{options[:older_than_days]} days"
markdown_lines << "Recursive scan: no"
markdown_lines << ""
markdown_lines << "## Summary"
markdown_lines << ""
markdown_lines << "- Entries inspected: #{summary['total_entries_inspected']}"
markdown_lines << "- Cleanup candidates: #{summary['cleanup_candidate_count']} (#{summary['cleanup_candidate_size_human']})"
markdown_lines << "- Candidate files: #{summary['cleanup_candidate_file_count'] || 0}"
markdown_lines << "- Candidate folders: #{summary['cleanup_candidate_directory_count'] || 0}"
markdown_lines << "- Protected entries: #{summary['protected_count']}"
markdown_lines << "- Uncertain entries: #{summary['uncertain_count']}"
markdown_lines << "- Read-only: yes"
markdown_lines << "- Files moved: 0"
markdown_lines << "- Files deleted: 0"
markdown_lines << ""
markdown_lines << "## Recommendation"
markdown_lines << ""
markdown_lines << recommendation
markdown_lines << ""

unless candidate_actions.empty?
  markdown_lines << "## Would Move to Trash After Approval"
  markdown_lines << ""
  candidate_actions.each do |item|
    label = item[:type] == "directory" ? "folder" : item[:type]
    extra = ""
    if item[:type] == "directory" && item[:directory_summary]
      ds = item[:directory_summary]
      extra = " - top-level contents: #{ds['top_level_entry_count']} entries"
    end
    markdown_lines << "- `#{item[:path]}` - #{label}, #{item[:size_human]}, #{item[:age_days]} days old#{extra}"
  end
  markdown_lines << ""
end

unless protected_summary.empty?
  markdown_lines << "## Protected"
  markdown_lines << ""
  protected_summary.each do |item|
    markdown_lines << "- `#{item[:path]}` - #{item[:type]} - matched #{Array(item[:matched_terms]).join(', ')}"
  end
  markdown_lines << ""
end

unless manual_review.empty?
  markdown_lines << "## Manual Review"
  markdown_lines << ""
  manual_review.each do |item|
    markdown_lines << "- `#{item[:path]}` - #{item[:type]} - #{Array(item[:reasons]).join('; ')}"
  end
  markdown_lines << ""
end

result = {
  skill: "downloads.cleanup_plan",
  generated_at: Time.now.iso8601,
  status: warnings.empty? ? "ok" : "warning",
  recommendation: recommendation,
  target_path: inspection["target_path"],
  options: {
    older_than_days: options[:older_than_days],
    max_entries: options[:max_entries],
    include_directories: options[:include_directories],
    recursive: false
  },
  summary: summary,
  proposed_actions: {
    would_move_to_trash_after_approval: candidate_actions,
    keep_protected: protected_summary,
    manual_review_required: manual_review
  },
  markdown_report: markdown_lines.join("\n"),
  source_inspection: inspection,
  verification: {
    read_only: true,
    moved_files: 0,
    deleted_files: 0,
    recursive_scan: false,
    top_level_only: true,
    source_inspection_read_only: inspection.dig("verification", "read_only") == true,
    protected_files_excluded_from_cleanup_candidates: inspection.dig("verification", "protected_files_excluded_from_cleanup_candidates") == true,
    approval_required_before_execution: true
  },
  warnings: warnings
}

puts JSON.pretty_generate(result)
