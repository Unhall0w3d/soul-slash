#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"
require "time"
require "uri"
require "fileutils"

options = {
  latest: true,
  move_log: nil,
  workflow_state: nil,
  execute: false,
  confirm: nil,
  only: nil,
  exclude: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: restore_last_cleanup.rb [--latest|--move-log PATH|--workflow-state PATH] [--execute --confirm RESTORE_FROM_TRASH]"

  opts.on("--latest", "Use latest successful downloads.move_to_trash task log. Default.") do
    options[:latest] = true
  end

  opts.on("--move-log PATH", "Path to a downloads.move_to_trash task log JSON.") do |value|
    options[:move_log] = value
    options[:latest] = false
  end

  opts.on("--workflow-state PATH", "Use selected restore candidates from a workflow session JSON.") do |value|
    options[:workflow_state] = value
    options[:latest] = false
  end

  opts.on("--only IDS", "Comma-separated candidate IDs to restore, such as F1,D1.") do |value|
    options[:only] = value
  end

  opts.on("--exclude IDS", "Comma-separated candidate IDs to keep in Trash, such as F1,D1.") do |value|
    options[:exclude] = value
  end

  opts.on("--execute", "Actually restore selected candidates from Trash.") do
    options[:execute] = true
  end

  opts.on("--confirm TEXT", "Required exact confirmation for execution: RESTORE_FROM_TRASH") do |value|
    options[:confirm] = value
  end
end

begin
  parser.parse!(ARGV)
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  puts JSON.pretty_generate({
    skill: "downloads.restore_last_cleanup",
    status: "error",
    error: "#{e.class}: #{e.message}",
    usage: parser.to_s
  })
  exit 2
end

def load_json_file(path)
  JSON.parse(File.read(path))
end

def payload_json(wrapper_or_payload)
  if wrapper_or_payload.is_a?(Hash) && wrapper_or_payload["json"].is_a?(Hash)
    wrapper_or_payload["json"]
  else
    wrapper_or_payload
  end
end

def successful_move_log?(path)
  wrapper = load_json_file(path)
  payload = payload_json(wrapper)
  payload["skill"] == "downloads.move_to_trash" &&
    payload["status"] == "ok" &&
    payload["outcome"] == "complete" &&
    payload["moved"].is_a?(Array) &&
    !payload["moved"].empty?
rescue StandardError
  false
end

def latest_successful_move_log
  logs = Dir.glob(File.join("Soul", "logs", "tasks", "*-skill.downloads.move_to_trash.json")).sort.reverse
  logs.find { |path| successful_move_log?(path) }
end

def parse_id_list(value)
  value.to_s.split(/[ ,]+/).map(&:strip).reject(&:empty?).map(&:upcase)
end

def safe_child_path?(target_path, base_path)
  target = Pathname.new(target_path).expand_path
  base = Pathname.new(base_path).expand_path
  target.to_s.start_with?(base.to_s + File::SEPARATOR)
end

def parse_trashinfo(path)
  data = {}
  File.readlines(path).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("[")

    key, value = line.split("=", 2)
    next unless key && value

    data[key] = value
  end
  data
end

def decode_trash_path(value)
  URI.decode_www_form_component(value.to_s)
rescue StandardError
  value.to_s
end

def trash_roots
  data_home = ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share"))
  [File.join(data_home, "Trash")]
end

def find_trash_record(original_path)
  matches = []

  trash_roots.each do |root|
    info_dir = File.join(root, "info")
    files_dir = File.join(root, "files")
    next unless Dir.exist?(info_dir) && Dir.exist?(files_dir)

    Dir.glob(File.join(info_dir, "*.trashinfo")).each do |info_path|
      info = parse_trashinfo(info_path)
      decoded_path = decode_trash_path(info["Path"])
      next unless decoded_path == original_path

      trash_name = File.basename(info_path, ".trashinfo")
      trash_file_path = File.join(files_dir, trash_name)
      matches << {
        "trash_root" => root,
        "trash_info_path" => info_path,
        "trash_file_path" => trash_file_path,
        "deletion_date" => info["DeletionDate"],
        "trash_name" => trash_name,
        "trash_file_exists" => File.exist?(trash_file_path)
      }
    end
  end

  matches.sort_by { |record| record["deletion_date"].to_s }.last
end

def assign_ids(moved_items)
  file_index = 0
  dir_index = 0

  moved_items.map do |item|
    copy = item.dup
    if copy["id"].to_s.strip.empty?
      case copy["type"]
      when "directory"
        dir_index += 1
        copy["id"] = "D#{dir_index}"
      else
        file_index += 1
        copy["id"] = "F#{file_index}"
      end
    end
    copy["name"] ||= File.basename(copy["path"].to_s)
    copy
  end
end

workflow_state = nil
move_log_path = nil
selected_ids_from_workflow = nil

if options[:workflow_state]
  unless File.exist?(options[:workflow_state])
    puts JSON.pretty_generate({
      skill: "downloads.restore_last_cleanup",
      generated_at: Time.now.iso8601,
      status: "error",
      outcome: "not_complete",
      error: "workflow state not found: #{options[:workflow_state]}",
      verification: { job_complete: false, permanent_delete_supported: false }
    })
    exit 1
  end

  workflow_state = load_json_file(options[:workflow_state])
  move_log_path = workflow_state.dig("verification", "source_move_log")
  selected_ids_from_workflow = workflow_state.fetch("selected_candidates", []).map { |item| item["id"].to_s.upcase }
else
  move_log_path = options[:move_log] || latest_successful_move_log
end

unless move_log_path && File.exist?(move_log_path)
  puts JSON.pretty_generate({
    skill: "downloads.restore_last_cleanup",
    generated_at: Time.now.iso8601,
    status: "error",
    outcome: "not_complete",
    recommendation: "No successful downloads.move_to_trash log was found. Nothing can be restored automatically.",
    source_move_log: move_log_path,
    candidates: [],
    restored: [],
    failed: [],
    errors: ["missing successful downloads.move_to_trash task log"],
    warnings: [],
    verification: {
      latest_successful_move_log_found: false,
      approval_required: true,
      explicit_execute_flag: options[:execute],
      explicit_confirm_text_matched: options[:confirm] == "RESTORE_FROM_TRASH",
      restored_total: 0,
      deleted_files: 0,
      permanent_delete_supported: false,
      job_complete: false
    }
  })
  exit 1
end

move_wrapper = load_json_file(move_log_path)
move_payload = payload_json(move_wrapper)
target_path = move_payload["target_path"] || File.join(Dir.home, "Downloads")
moved_items = assign_ids(move_payload.fetch("moved", []))

only_ids = selected_ids_from_workflow || parse_id_list(options[:only])
exclude_ids = parse_id_list(options[:exclude])

if !only_ids.empty?
  moved_items = moved_items.select { |item| only_ids.include?(item["id"].to_s.upcase) }
end

if !exclude_ids.empty?
  moved_items = moved_items.reject { |item| exclude_ids.include?(item["id"].to_s.upcase) }
end

errors = []
warnings = []
errors << "execution requires --confirm RESTORE_FROM_TRASH" if options[:execute] && options[:confirm] != "RESTORE_FROM_TRASH"

if workflow_state
  errors << "workflow is not waiting_for_restore_final_confirmation" unless workflow_state["status"] == "waiting_for_restore_final_confirmation"
  errors << "workflow state has no selected candidates" if selected_ids_from_workflow.empty?
end

candidates = moved_items.map do |item|
  original_path = item["path"]
  trash_record = find_trash_record(original_path)
  item_errors = []

  item_errors << "original path missing from move log" if original_path.to_s.strip.empty?
  item_errors << "original path is outside target directory" if original_path && target_path && !safe_child_path?(original_path, target_path)
  item_errors << "original path already exists; refusing to overwrite" if original_path && File.exist?(original_path)
  item_errors << "matching Trash metadata not found" unless trash_record
  item_errors << "matching Trash file/folder not found" if trash_record && !trash_record["trash_file_exists"]

  {
    "id" => item["id"],
    "path" => original_path,
    "name" => item["name"] || File.basename(original_path.to_s),
    "type" => item["type"],
    "source_move_log" => move_log_path,
    "trash_info_path" => trash_record && trash_record["trash_info_path"],
    "trash_file_path" => trash_record && trash_record["trash_file_path"],
    "deletion_date" => trash_record && trash_record["deletion_date"],
    "valid" => item_errors.empty?,
    "errors" => item_errors
  }
end

errors.concat(candidates.flat_map { |item| item["errors"].map { |err| "#{item['id']} #{item['path']}: #{err}" } })
warnings << "no moved items from the selected cleanup log are available to restore" if candidates.empty?
warnings << "dry-run only; no files or folders were restored" if !options[:execute] && !candidates.empty?

restored = []
failed = []

if errors.empty? && options[:execute]
  candidates.each do |candidate|
    begin
      FileUtils.mkdir_p(File.dirname(candidate["path"]))
      FileUtils.mv(candidate["trash_file_path"], candidate["path"])
      FileUtils.rm_f(candidate["trash_info_path"])

      restored << candidate.merge(
        "restored" => true,
        "verified_original_path_exists" => File.exist?(candidate["path"])
      )
    rescue StandardError => e
      failed << candidate.merge(
        "restored" => false,
        "error" => "#{e.class}: #{e.message}"
      )
    end
  end
end

job_complete =
  options[:execute] &&
  errors.empty? &&
  failed.empty? &&
  restored.length == candidates.length &&
  !candidates.empty? &&
  restored.all? { |item| item["verified_original_path_exists"] == true }

outcome =
  if job_complete
    "complete"
  elsif options[:execute]
    "not_complete"
  else
    "dry_run"
  end

recommendation =
  if job_complete
    "Restore job complete. Selected items were restored from Trash to their original paths."
  elsif !options[:execute] && candidates.empty?
    "No restore candidates were found. Nothing to restore."
  elsif !options[:execute]
    "Dry run complete. Review the restore candidates, then rerun with --execute --confirm RESTORE_FROM_TRASH if approved."
  elsif !failed.empty?
    "Restore job not complete. Some selected items failed to restore."
  else
    "Restore job not complete. Resolve validation errors before execution."
  end

status =
  if !errors.empty?
    "error"
  elsif !failed.empty?
    "warning"
  else
    "ok"
  end

result = {
  skill: "downloads.restore_last_cleanup",
  generated_at: Time.now.iso8601,
  status: status,
  outcome: outcome,
  recommendation: recommendation,
  mode: options[:execute] ? "execute" : "dry_run",
  source_move_log: move_log_path,
  workflow_state: options[:workflow_state],
  target_path: target_path,
  candidate_count: candidates.length,
  candidates: candidates,
  restored: restored,
  failed: failed,
  errors: errors,
  warnings: warnings,
  verification: {
    latest_successful_move_log_found: true,
    approval_required: true,
    explicit_execute_flag: options[:execute],
    explicit_confirm_text_matched: options[:confirm] == "RESTORE_FROM_TRASH",
    consumed_workflow_state: !workflow_state.nil?,
    consumed_successful_move_log: move_payload["outcome"] == "complete",
    restored_files: restored.count { |item| item["type"] == "file" },
    restored_directories: restored.count { |item| item["type"] == "directory" },
    restored_total: restored.length,
    planned_total: candidates.length,
    deleted_files: 0,
    permanent_delete_supported: false,
    trash_emptying_supported: false,
    refused_outside_target: errors.any? { |error| error.include?("outside target directory") },
    refused_overwrite: errors.any? { |error| error.include?("already exists") },
    job_complete_when_all_selected_items_restored: true,
    job_complete: job_complete
  }
}

puts JSON.pretty_generate(result)

exit 1 if status == "error"
