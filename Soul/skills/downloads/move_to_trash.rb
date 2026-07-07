#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "open3"
require "pathname"
require "time"

options = {
  plan_log: nil,
  latest_plan: false,
  workflow_state: nil,
  execute: false,
  confirm: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: move_to_trash.rb (--latest-plan|--plan-log PATH|--workflow-state PATH) [--execute --confirm MOVE_TO_TRASH]"

  opts.on("--plan-log PATH", "Path to a downloads.cleanup_plan task log JSON.") do |value|
    options[:plan_log] = value
  end

  opts.on("--latest-plan", "Use latest downloads.cleanup_plan task log.") do
    options[:latest_plan] = true
  end

  opts.on("--workflow-state PATH", "Use selected candidates from a workflow session JSON.") do |value|
    options[:workflow_state] = value
  end

  opts.on("--execute", "Actually move approved cleanup candidates to Trash.") do
    options[:execute] = true
  end

  opts.on("--confirm TEXT", "Required exact confirmation for execution: MOVE_TO_TRASH") do |value|
    options[:confirm] = value
  end
end

begin
  parser.parse!(ARGV)
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  puts JSON.pretty_generate({
    skill: "downloads.move_to_trash",
    generated_at: Time.now.iso8601,
    status: "error",
    outcome: "not_complete",
    error: "#{e.class}: #{e.message}",
    usage: parser.to_s,
    verification: {
      moved_files: 0,
      moved_directories: 0,
      deleted_files: 0,
      permanent_delete_supported: false,
      trash_is_terminal_cleanup_action: true,
      job_complete: false
    }
  })
  exit 2
end

def latest_plan_log
  logs = Dir.glob(File.join("Soul", "logs", "tasks", "*-skill.downloads.cleanup_plan.json")).sort
  logs.last
end

def load_json(path)
  JSON.parse(File.read(path))
end

def payload_json(wrapper_or_payload)
  if wrapper_or_payload.is_a?(Hash) && wrapper_or_payload["json"].is_a?(Hash)
    wrapper_or_payload["json"]
  else
    wrapper_or_payload
  end
end

def trash_command
  if system("command -v gio >/dev/null 2>&1")
    ["gio", "trash"]
  elsif system("command -v trash-put >/dev/null 2>&1")
    ["trash-put"]
  else
    nil
  end
end

def safe_child_path?(target_path, base_path)
  target = Pathname.new(target_path).expand_path
  base = Pathname.new(base_path).expand_path
  target.to_s.start_with?(base.to_s + File::SEPARATOR)
end

def run_cmd(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)

  {
    ok: status.success?,
    stdout: stdout.strip,
    stderr: stderr.strip,
    exit_status: status.exitstatus
  }
rescue StandardError => e
  {
    ok: false,
    stdout: "",
    stderr: "#{e.class}: #{e.message}",
    exit_status: nil
  }
end

workflow_state = nil

if options[:workflow_state]
  unless File.exist?(options[:workflow_state])
    puts JSON.pretty_generate({
      skill: "downloads.move_to_trash",
      generated_at: Time.now.iso8601,
      status: "error",
      outcome: "not_complete",
      error: "workflow state not found: #{options[:workflow_state]}",
      verification: {
        moved_files: 0,
        moved_directories: 0,
        deleted_files: 0,
        permanent_delete_supported: false,
        trash_is_terminal_cleanup_action: true,
        job_complete: false
      }
    })
    exit 1
  end

  workflow_state = load_json(options[:workflow_state])
  plan_log = workflow_state.dig("verification", "plan_log")
else
  plan_log =
    if options[:latest_plan]
      latest_plan_log
    else
      options[:plan_log]
    end
end

unless plan_log && File.exist?(plan_log)
  puts JSON.pretty_generate({
    skill: "downloads.move_to_trash",
    generated_at: Time.now.iso8601,
    status: "error",
    outcome: "not_complete",
    error: "missing cleanup plan log; provide --latest-plan, --plan-log PATH, or --workflow-state PATH",
    verification: {
      moved_files: 0,
      moved_directories: 0,
      deleted_files: 0,
      permanent_delete_supported: false,
      trash_is_terminal_cleanup_action: true,
      job_complete: false
    }
  })
  exit 1
end

plan = payload_json(load_json(plan_log))
target_path = plan["target_path"]
verification = plan["verification"] || {}
protected_paths = (plan.dig("proposed_actions", "keep_protected") || []).map { |item| item["path"] }

actions =
  if workflow_state
    workflow_state.fetch("selected_candidates", [])
  else
    plan.dig("proposed_actions", "would_move_to_trash_after_approval") || []
  end

errors = []
warnings = []
trash = trash_command

errors << "cleanup plan was not read-only" unless verification["read_only"] == true
errors << "cleanup plan does not require approval before execution" unless verification["approval_required_before_execution"] == true
errors << "cleanup plan target_path missing" if target_path.to_s.strip.empty?
errors << "no Trash command found; install gio/glib2 or trash-cli" unless trash
errors << "execution requires --confirm MOVE_TO_TRASH" if options[:execute] && options[:confirm] != "MOVE_TO_TRASH"

if workflow_state
  errors << "workflow is not waiting_for_final_confirmation" unless workflow_state["status"] == "waiting_for_final_confirmation"
  errors << "workflow state has no selected candidates" if actions.empty?
end

validated_actions = actions.map do |item|
  path = item["path"]
  type = item["type"]
  item_errors = []

  item_errors << "path missing" if path.to_s.strip.empty?
  item_errors << "path is protected" if protected_paths.include?(path)
  item_errors << "path is outside target directory" if target_path && path && !safe_child_path?(path, target_path)
  item_errors << "path does not exist" if path && !File.exist?(path)
  item_errors << "unsupported type #{type}" unless %w[file directory].include?(type)

  actual_type =
    if path && File.symlink?(path)
      "symlink"
    elsif path && File.directory?(path)
      "directory"
    elsif path && File.file?(path)
      "file"
    else
      "missing_or_other"
    end

  item_errors << "planned type #{type} does not match actual type #{actual_type}" if path && File.exist?(path) && type != actual_type

  {
    action: item,
    valid: item_errors.empty?,
    errors: item_errors,
    actual_type: actual_type
  }
end

errors.concat(validated_actions.flat_map { |item| item[:errors].map { |err| "#{item.dig(:action, 'path')}: #{err}" } })

moved = []
failed = []

if errors.empty? && options[:execute]
  validated_actions.each do |validated|
    path = validated.dig(:action, "path")
    result = run_cmd(trash + [path])

    if result[:ok]
      moved << {
        id: validated.dig(:action, "id"),
        path: path,
        type: validated.dig(:action, "type"),
        result: result
      }
    else
      failed << {
        id: validated.dig(:action, "id"),
        path: path,
        type: validated.dig(:action, "type"),
        result: result
      }
    end
  end
elsif !options[:execute]
  if actions.empty?
    warnings << "no cleanup candidates were selected"
  else
    warnings << "dry-run only; no files or folders were moved"
  end
end

job_complete =
  options[:execute] &&
  errors.empty? &&
  failed.empty? &&
  moved.length == actions.length &&
  !actions.empty?

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
    "Cleanup job complete. Approved items were moved to Trash. Trash emptying is left to the operating system or the user."
  elsif !options[:execute] && actions.empty?
    "No cleanup candidates are selected. Nothing to move."
  elsif !options[:execute]
    "Dry run complete. Review the listed actions, then rerun with --execute --confirm MOVE_TO_TRASH if approved."
  elsif !failed.empty?
    "Cleanup job not complete. Some planned items failed to move to Trash."
  else
    "Cleanup job not complete. Resolve validation errors before execution."
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
  skill: "downloads.move_to_trash",
  generated_at: Time.now.iso8601,
  status: status,
  outcome: outcome,
  recommendation: recommendation,
  mode: options[:execute] ? "execute" : "dry_run",
  plan_log: plan_log,
  workflow_state: options[:workflow_state],
  target_path: target_path,
  trash_command: trash,
  planned_candidate_count: actions.length,
  validated_candidate_count: validated_actions.count { |item| item[:valid] },
  dry_run_actions: options[:execute] ? [] : validated_actions.map { |item| item[:action] },
  moved: moved,
  failed: failed,
  errors: errors,
  warnings: warnings,
  verification: {
    approval_required: true,
    explicit_execute_flag: options[:execute],
    explicit_confirm_text_matched: options[:confirm] == "MOVE_TO_TRASH",
    consumed_plan_log: true,
    consumed_workflow_state: !workflow_state.nil?,
    consumed_verified_cleanup_plan: verification["read_only"] == true && verification["approval_required_before_execution"] == true,
    moved_files: moved.count { |item| item[:type] == "file" },
    moved_directories: moved.count { |item| item[:type] == "directory" },
    moved_total: moved.length,
    planned_total: actions.length,
    deleted_files: 0,
    permanent_delete_supported: false,
    trash_is_terminal_cleanup_action: true,
    trash_emptying_left_to_os_or_user: true,
    job_complete_when_all_planned_items_moved_to_trash: true,
    job_complete: job_complete,
    refused_outside_target: errors.any? { |error| error.include?("outside target directory") },
    refused_protected: errors.any? { |error| error.include?("protected") }
  }
}

puts JSON.pretty_generate(result)

exit 1 if status == "error"
