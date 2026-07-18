#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"
require "optparse"
require "pathname"
require "time"
require_relative "../../../lib/soul_core/memory_paths"

options = {
  path: File.join(Dir.home, "Downloads"),
  older_than_days: 30,
  max_entries: 5000,
  include_directories: true
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: inspect.rb [--path PATH] [--older-than-days N] [--max-entries N] [--exclude-directories]"

  opts.on("--path PATH", "Directory to inspect. Defaults to ~/Downloads.") do |value|
    options[:path] = value
  end

  opts.on("--older-than-days N", Integer, "Age threshold for cleanup candidates. Defaults to 30.") do |value|
    options[:older_than_days] = value
  end

  opts.on("--max-entries N", Integer, "Maximum top-level directory entries to inspect. Defaults to 5000.") do |value|
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
    skill: "downloads.inspect",
    status: "error",
    error: "#{e.class}: #{e.message}",
    usage: parser.to_s
  })
  exit 2
end

def expand_path(path)
  path = path.to_s
  if path == "~"
    Dir.home
  elsif path.start_with?("~/")
    File.join(Dir.home, path[2..])
  else
    path
  end
end

def load_project_terms
  paths = SoulCore::MemoryPaths.new(root: Dir.pwd)
  project_path = paths.read_path("projects.yaml")
  alias_path = paths.read_path("aliases.yaml")

  terms = []

  if File.exist?(project_path)
    data = YAML.load_file(project_path) || {}
    projects = data.fetch("projects", {})
    projects.each_value do |project|
      terms.concat(Array(project["aliases"]))
      terms.concat(Array(project["protected_terms"]))
      terms << project["display_name"] if project["display_name"]
    end
  end

  if File.exist?(alias_path)
    data = YAML.load_file(alias_path) || {}
    aliases = data.fetch("aliases", {})
    aliases.each do |alias_name, meta|
      terms << alias_name
      terms << meta["likely_means"] if meta.is_a?(Hash) && meta["likely_means"]
    end
  end

  terms.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
rescue StandardError
  []
end

def human_size(bytes)
  units = %w[B KiB MiB GiB TiB]
  size = bytes.to_f
  unit = units.shift
  while size >= 1024 && !units.empty?
    size /= 1024.0
    unit = units.shift
  end
  format("%.1f %s", size, unit)
end

def shallow_directory_summary(pathname)
  children = pathname.children
  {
    top_level_entry_count: children.length,
    top_level_file_count: children.count { |child| child.file? },
    top_level_directory_count: children.count { |child| child.directory? },
    note: "Shallow inspection only; nested contents were not recursively scanned."
  }
rescue StandardError => e
  {
    top_level_entry_count: nil,
    top_level_file_count: nil,
    top_level_directory_count: nil,
    note: "Could not inspect top-level directory contents: #{e.class}: #{e.message}"
  }
end

def entry_info(pathname, now:, threshold_time:, protected_terms:, include_directories:)
  stat = pathname.lstat
  real_path = pathname.to_s
  basename = pathname.basename.to_s
  lowercase_blob = real_path.downcase

  matched_terms = protected_terms.select do |term|
    lowercase_blob.include?(term.downcase)
  end

  age_days = ((now - stat.mtime) / 86_400.0).round(2)
  old = stat.mtime < threshold_time

  type =
    if stat.symlink?
      "symlink"
    elsif stat.directory?
      "directory"
    elsif stat.file?
      "file"
    else
      "other"
    end

  extension = pathname.extname.downcase
  top_level_directory_summary = type == "directory" ? shallow_directory_summary(pathname) : nil

  candidate_eligible =
    case type
    when "file"
      true
    when "directory"
      include_directories
    else
      false
    end

  classification =
    if !matched_terms.empty?
      "protected"
    elsif old && candidate_eligible
      "cleanup_candidate"
    elsif type == "directory" && !include_directories
      "uncertain"
    elsif %w[symlink other].include?(type)
      "uncertain"
    else
      "recent"
    end

  reasons = []
  reasons << "matched protected term(s): #{matched_terms.join(', ')}" unless matched_terms.empty?
  reasons << "older than threshold: #{age_days} days > #{((now - threshold_time) / 86_400.0).round} days" if old
  reasons << "top-level directory is eligible because include_directories=true" if type == "directory" && include_directories
  reasons << "directory excluded by option" if type == "directory" && !include_directories
  reasons << "not eligible cleanup type: #{type}" if %w[symlink other].include?(type)
  reasons << "recent entry" if classification == "recent"

  item = {
    path: real_path,
    name: basename,
    type: type,
    extension: extension,
    size_bytes: stat.size,
    size_human: human_size(stat.size),
    modified_at: stat.mtime.iso8601,
    age_days: age_days,
    old: old,
    cleanup_eligible_type: candidate_eligible,
    classification: classification,
    matched_terms: matched_terms,
    reasons: reasons
  }

  item[:directory_summary] = top_level_directory_summary if top_level_directory_summary
  item
rescue StandardError => e
  {
    path: pathname.to_s,
    classification: "uncertain",
    error: "#{e.class}: #{e.message}",
    reasons: ["could not inspect entry"]
  }
end

target = Pathname.new(expand_path(options[:path])).expand_path
now = Time.now
threshold_time = now - (options[:older_than_days] * 86_400)
protected_terms = load_project_terms

warnings = []

unless target.exist?
  puts JSON.pretty_generate({
    skill: "downloads.inspect",
    generated_at: now.iso8601,
    status: "error",
    error: "target path does not exist",
    target_path: target.to_s,
    verification: {
      target_exists: false,
      read_only: true
    }
  })
  exit 1
end

unless target.directory?
  puts JSON.pretty_generate({
    skill: "downloads.inspect",
    generated_at: now.iso8601,
    status: "error",
    error: "target path is not a directory",
    target_path: target.to_s,
    verification: {
      target_exists: true,
      target_is_directory: false,
      read_only: true
    }
  })
  exit 1
end

entries = target.children.sort_by { |p| p.basename.to_s.downcase }
if entries.length > options[:max_entries]
  warnings << "entry count exceeds max_entries; results truncated to #{options[:max_entries]}"
  entries = entries.first(options[:max_entries])
end

items = entries.map do |entry|
  entry_info(entry, now: now, threshold_time: threshold_time, protected_terms: protected_terms, include_directories: options[:include_directories])
end

protected_files = items.select { |item| item[:classification] == "protected" }
cleanup_candidates = items.select { |item| item[:classification] == "cleanup_candidate" }
uncertain = items.select { |item| item[:classification] == "uncertain" }
recent = items.select { |item| item[:classification] == "recent" }

total_size = items.sum { |item| item[:size_bytes].to_i }
candidate_size = cleanup_candidates.sum { |item| item[:size_bytes].to_i }

result = {
  skill: "downloads.inspect",
  generated_at: now.iso8601,
  status: warnings.empty? ? "ok" : "warning",
  target_path: target.to_s,
  options: {
    older_than_days: options[:older_than_days],
    max_entries: options[:max_entries],
    include_directories: options[:include_directories],
    recursive: false
  },
  protected_terms: protected_terms.sort,
  summary: {
    total_entries_inspected: items.length,
    protected_count: protected_files.length,
    cleanup_candidate_count: cleanup_candidates.length,
    cleanup_candidate_file_count: cleanup_candidates.count { |item| item[:type] == "file" },
    cleanup_candidate_directory_count: cleanup_candidates.count { |item| item[:type] == "directory" },
    uncertain_count: uncertain.length,
    recent_count: recent.length,
    total_size_bytes: total_size,
    total_size_human: human_size(total_size),
    cleanup_candidate_size_bytes: candidate_size,
    cleanup_candidate_size_human: human_size(candidate_size)
  },
  protected_files: protected_files,
  cleanup_candidates: cleanup_candidates,
  uncertain: uncertain,
  recent_sample: recent.first(25),
  verification: {
    target_exists: true,
    target_is_directory: true,
    read_only: true,
    moved_files: 0,
    deleted_files: 0,
    recursive_scan: false,
    top_level_only: true,
    cleanup_candidates_are_allowed_types: cleanup_candidates.all? { |item| %w[file directory].include?(item[:type]) },
    protected_files_excluded_from_cleanup_candidates: (protected_files.map { |i| i[:path] } & cleanup_candidates.map { |i| i[:path] }).empty?
  },
  warnings: warnings
}

puts JSON.pretty_generate(result)
