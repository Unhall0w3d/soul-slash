# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require_relative "package_manager_assessor"

module SoulCore
  class HostImprovementPlanService
    SCHEMA = "soul.host_improvement.plan.v1"
    RECEIPT_SCHEMA = "soul.host_improvement.receipt.v1"
    ROOT = File.join("Soul", "host_improvement", "plans")
    CONFIRMATION = "CREATE_ARCH_FULL_UPGRADE_HANDOFF"
    MAX_RECORDS = 100
    MAX_FILE_BYTES = 512 * 1024

    def initialize(root: Dir.pwd, clock: -> { Time.now }, package_assessor: nil, pacman_log_path: "/var/log/pacman.log")
      @root = File.expand_path(root)
      @clock = clock
      @package_assessor = package_assessor
      @pacman_log_path = pacman_log_path
    end

    def preview_arch_upgrade
      assessment = package_assessor.assess(include_updates: true)
      updates = assessment.dig("managers", "pacman", "updates") || {}
      return blocked("Arch package assessment is unavailable") unless assessment.dig("managers", "pacman", "detected")
      return blocked("a fresh checkupdates result is required") unless updates["fresh"] == true && %w[complete no_updates].include?(updates["status"])
      return awaiting("Arch package databases report no available updates") if updates["status"] == "no_updates"

      plan = build_plan(updates)
      success({"plan"=>plan, "expected_digest"=>plan_digest(plan), "confirmation_phrase"=>CONFIRMATION, "read_only"=>true})
    end

    def create_arch_handoff(confirmation:, expected_digest:)
      return awaiting("preview digest is required") if expected_digest.to_s.empty?
      return blocked("exact confirmation is required") unless confirmation.to_s == CONFIRMATION
      current = preview_arch_upgrade
      return current unless current["ok"]
      plan = current.dig("data", "plan")
      return blocked("package evidence changed; preview again") unless secure_equal?(plan_digest(plan), expected_digest.to_s)

      directory = packet_directory(plan.fetch("plan_id"))
      return blocked("plan packet already exists") if File.exist?(directory) || File.symlink?(directory)
      ensure_storage_root!
      Dir.mkdir(directory, 0o700)
      atomic_write(File.join(directory, "plan.json"), JSON.pretty_generate(plan) + "\n")
      atomic_write(File.join(directory, "TERMINAL_HANDOFF.md"), terminal_handoff(plan))
      blocked("terminal execution remains an external human action", data: {"plan"=>plan, "packet"=>relative(directory), "host_command_executed"=>false}, mutation: "host_improvement_handoff_created")
    rescue Errno::EEXIST
      blocked("plan packet already exists")
    end

    def list(limit: MAX_RECORDS)
      ensure_storage_root!
      records = Dir.children(storage_root).sort.reverse.first([Integer(limit), MAX_RECORDS].min).filter_map do |id|
        read_plan(id)
      end
      success({"records"=>records, "count"=>records.length, "limit"=>[Integer(limit), MAX_RECORDS].min, "read_only"=>true})
    end

    def verify(plan_id:)
      plan = read_plan(validate_id!(plan_id))
      return awaiting("unknown host improvement plan") unless plan
      current = package_assessor.assess(include_updates: true).dig("managers", "pacman", "updates") || {}
      receipt = {
        "schema_version"=>RECEIPT_SCHEMA, "plan_id"=>plan.fetch("plan_id"), "verified_at"=>@clock.call.iso8601,
        "source_digest"=>plan.fetch("source_digest"), "check_status"=>current["status"], "fresh"=>current["fresh"] == true,
        "remaining_update_count"=>current.fetch("count", 0), "remaining_updates"=>current.fetch("items", []).first(2_000),
        "postcondition"=>current["fresh"] == true && current["status"] == "no_updates" ? "satisfied" : "not_satisfied",
        "pacman_log_evidence"=>pacman_log_evidence,
        "host_command_executed_by_soul"=>false, "receipt_persisted"=>true
      }
      receipt_id = "receipt_#{digest(receipt.reject { |key, _value| key == "verified_at" })[0,16]}"
      receipts = File.join(packet_directory(plan.fetch("plan_id")), "receipts")
      raise "receipt root must not be a symlink" if File.symlink?(receipts)
      FileUtils.mkdir_p(receipts, mode: 0o700)
      path = File.join(receipts, "#{receipt_id}.json")
      raise "receipt target must not be a symlink" if File.symlink?(path)
      created = !File.exist?(path)
      return blocked("receipt inventory limit reached") if created && Dir.children(receipts).length >= MAX_RECORDS
      atomic_write(path, JSON.pretty_generate(receipt.merge("receipt_id"=>receipt_id)) + "\n") if created
      success({"receipt"=>receipt.merge("receipt_id"=>receipt_id,"packet"=>relative(path)), "read_only_assessment"=>true}, mutation: created ? "host_improvement_receipt_created" : "none")
    end

    private

    def build_plan(updates)
      evidence = {"status"=>updates["status"], "count"=>updates["count"], "items"=>updates["items"], "command"=>updates["command"]}
      source_digest = digest(evidence)
      {
        "schema_version"=>SCHEMA, "plan_id"=>"hip_#{source_digest[0, 16]}", "created_at"=>@clock.call.iso8601,
        "adapter"=>"arch.system_upgrade", "risk_class"=>"class_5", "source_digest"=>source_digest,
        "pending_update_count"=>updates.fetch("count", 0), "pending_updates"=>updates.fetch("items", []).first(2_000),
        "preconditions"=>["Review the exact package list", "Ensure important work is saved", "Run from an interactive terminal"],
        "commands"=>[["sudo", "pacman", "-Syu"]], "possible_reboot"=>true,
        "execution_authorized"=>false, "execution_surface"=>"human_terminal_only", "human_review_required"=>true,
        "prohibited_flags"=>["--noconfirm", "--overwrite", "--nodeps"], "lifecycle_state"=>"blocked_for_human_review"
      }
    end

    def terminal_handoff(plan)
      <<~MD
        # Arch Full Upgrade — Terminal Handoff

        Plan: `#{plan.fetch("plan_id")}`
        Risk: Class 5 — privileged host mutation
        Pending packages at preview: #{plan.fetch("pending_update_count")}

        Soul did not execute this command. Review `plan.json`, then run manually in
        an interactive terminal only if you accept the current pacman transaction:

        ```sh
        sudo pacman -Syu
        ```

        Do not add `--noconfirm`, `--overwrite`, or `--nodeps`. After completion,
        return to Self Assessment and run the foreground postcondition check.
      MD
    end

    def package_assessor
      @package_assessor ||= PackageManagerAssessor.new
    end

    def pacman_log_evidence
      return {"status"=>"unavailable","path"=>"/var/log/pacman.log","entries"=>[],"entry_count"=>0,"truncated"=>false} unless File.file?(@pacman_log_path) && !File.symlink?(@pacman_log_path)
      size = File.size(@pacman_log_path)
      maximum = 512 * 1024
      content = File.open(@pacman_log_path, "rb") do |file|
        file.seek([size - maximum, 0].max)
        file.read(maximum).to_s
      end
      lines = content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").lines.select { |line| line.include?("[ALPM]") && line.match?(/\b(?:upgraded|installed|removed)\b/) }.last(200).map(&:strip)
      {"status"=>"complete","path"=>"/var/log/pacman.log","entries"=>lines,"entry_count"=>lines.length,"truncated"=>size > maximum}
    rescue Errno::EACCES, Errno::ENOENT, IOError
      {"status"=>"unavailable","path"=>"/var/log/pacman.log","entries"=>[],"entry_count"=>0,"truncated"=>false}
    end

    def storage_root
      File.join(@root, ROOT)
    end

    def ensure_storage_root!
      ensure_safe_directory!(ROOT)
    end

    def ensure_safe_directory!(relative_path)
      cursor = @root
      relative_path.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        raise "host plan path must not traverse a symlink" if File.symlink?(cursor)
        Dir.mkdir(cursor, 0o700) unless File.exist?(cursor)
        raise "host plan path component must be a directory" unless File.directory?(cursor)
      end
      cursor
    end

    def packet_directory(id)
      validate_id!(id)
      File.join(storage_root, id)
    end

    def validate_id!(id)
      value = id.to_s
      raise ArgumentError, "plan_id is invalid" unless value.match?(/\Ahip_[a-f0-9]{16}\z/)
      value
    end

    def read_plan(id)
      directory = packet_directory(id)
      return nil unless File.directory?(directory) && !File.symlink?(directory)
      path = File.join(directory, "plan.json")
      return nil unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_FILE_BYTES
      JSON.parse(File.binread(path, MAX_FILE_BYTES))
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def atomic_write(path, content)
      raise "packet target already exists" if File.exist?(path) || File.symlink?(path)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.file?(temporary)
    end

    def relative(path) = path.delete_prefix(@root + File::SEPARATOR)
    def digest(value) = Digest::SHA256.hexdigest(JSON.generate(value))
    def plan_digest(plan) = digest(plan.reject { |key, _value| key == "created_at" })
    def secure_equal?(left, right) = left.bytesize == right.bytesize && left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    def success(data, mutation: "none") = {"ok"=>true,"lifecycle_state"=>"complete","data"=>data,"mutation"=>mutation}
    def awaiting(reason) = {"ok"=>false,"lifecycle_state"=>"awaiting_input","reason"=>reason,"mutation"=>"none"}
    def blocked(reason, data: nil, mutation: "none")
      result = {"ok"=>false,"lifecycle_state"=>"blocked_for_human_review","reason"=>reason,"mutation"=>mutation}
      result["data"] = data if data
      result
    end
  end
end
