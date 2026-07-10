# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "time"
require "uri"
require_relative "approval_token_store"
require_relative "chat_execution_history"

module SoulCore
  class DownloadsMoveToTrashExecutor
    RULE = "files older than 30 days or larger than 100 MiB"
    Result = Struct.new(
      :ok,
      :status,
      :message,
      :skill_id,
      :risk,
      :confirmation_required,
      :executed,
      :stdout,
      :stderr,
      :exit_status,
      :blocked_by,
      :generated_at,
      :history_entry,
      keyword_init: true
    )

    def initialize(
      root: Dir.pwd,
      store: nil,
      history: nil,
      target_dir: File.join(Dir.home, "Downloads"),
      trash_root: default_trash_root,
      clock: -> { Time.now }
    )
      @root = File.expand_path(root)
      @store = store || ApprovalTokenStore.new(root: @root)
      @history = history || ChatExecutionHistory.new(root: @root)
      @target_dir = File.expand_path(target_dir)
      @trash_root = File.expand_path(trash_root)
      @clock = clock
    end

    def execute(token_id:, confirm: false, record_history: true)
      unless confirm
        return blocked_result(
          "Explicit confirmation is required.",
          ["explicit_confirmation_required"],
          token_id: token_id,
          record_history: record_history
        )
      end

      token = @store.find(token_id)
      return blocked_result("Approval token was not found.", ["token_not_found"], token_id: token_id, record_history: record_history) unless token

      scan = scan_candidates
      scope = build_scope(token, scan)
      validation = @store.validate(
        token_id: token_id,
        skill_id: "downloads.move_to_trash",
        scope: scope
      )

      unless validation["ok"]
        return blocked_result(
          "Approval token validation failed: #{validation['reason']}.",
          [validation["reason"]],
          token_id: token_id,
          record_history: record_history
        )
      end

      moved = []
      failed = []

      scan.fetch("candidates").each do |candidate|
        begin
          destination = move_to_trash(candidate.fetch("path"))
          moved << {
            "size_bytes" => candidate.fetch("size_bytes"),
            "extension" => candidate.fetch("extension"),
            "trash_name_digest" => Digest::SHA256.hexdigest(File.basename(destination))
          }
        rescue StandardError => error
          failed << {
            "size_bytes" => candidate.fetch("size_bytes"),
            "extension" => candidate.fetch("extension"),
            "error" => "#{error.class}: #{error.message}"
          }
        end
      end

      token_result = @store.mark_used(token_id)
      status = failed.empty? ? "executed" : "partial"
      ok = failed.empty?

      payload = {
        "ok" => ok,
        "status" => status,
        "skill_id" => "downloads.move_to_trash",
        "token_id" => token_id,
        "attempted_count" => scan.fetch("candidate_count"),
        "moved_count" => moved.length,
        "failed_count" => failed.length,
        "moved_bytes" => moved.sum { |entry| entry.fetch("size_bytes") },
        "failed_bytes" => failed.sum { |entry| entry.fetch("size_bytes") },
        "token_status" => token_result["status"],
        "trash_root" => relative_home_path(@trash_root),
        "permanent_delete" => false,
        "filenames_omitted" => true,
        "generated_at" => @clock.call.iso8601
      }

      result = Result.new(
        ok: ok,
        status: status,
        message: ok ? "Moved approved Downloads candidates to trash." : "Downloads trash move completed with failures.",
        skill_id: "downloads.move_to_trash",
        risk: "approval_required",
        confirmation_required: true,
        executed: true,
        stdout: JSON.pretty_generate(payload) + "\n",
        stderr: failed.empty? ? "" : JSON.generate(failed),
        exit_status: failed.empty? ? 0 : 1,
        blocked_by: [],
        generated_at: @clock.call.iso8601,
        history_entry: nil
      )

      record(result, "move approved downloads to trash", token_id) if record_history
      result
    end

    def preview_scope
      scan = scan_candidates
      {
        "target_path" => relative_home_path(@target_dir),
        "candidate_rule" => RULE,
        "candidate_count" => scan.fetch("candidate_count"),
        "candidate_bytes" => scan.fetch("candidate_bytes"),
        "manifest_digest" => scan.fetch("manifest_digest")
      }
    end

    private

    def scan_candidates
      candidates = []
      now = @clock.call

      if Dir.exist?(@target_dir)
        Dir.children(@target_dir).sort.each do |name|
          path = File.join(@target_dir, name)
          next unless File.file?(path)

          stat = File.stat(path)
          age_days = ((now - stat.mtime) / 86_400).floor
          next unless age_days > 30 || stat.size > (100 * 1024 * 1024)

          extension = File.extname(name).downcase
          extension = "[no extension]" if extension.empty?

          candidates << {
            "path" => path,
            "relative_name" => name,
            "size_bytes" => stat.size,
            "mtime_i" => stat.mtime.to_i,
            "extension" => extension
          }
        end
      end

      manifest = candidates.map do |entry|
        [entry.fetch("relative_name"), entry.fetch("size_bytes"), entry.fetch("mtime_i")].join("\0")
      end.join("\n")

      {
        "candidates" => candidates,
        "candidate_count" => candidates.length,
        "candidate_bytes" => candidates.sum { |entry| entry.fetch("size_bytes") },
        "manifest_digest" => Digest::SHA256.hexdigest(manifest)
      }
    end

    def build_scope(token, scan)
      stored = token.fetch("scope", {})
      scope = {
        "target_path" => relative_home_path(@target_dir),
        "candidate_rule" => RULE,
        "candidate_count" => scan.fetch("candidate_count"),
        "candidate_bytes" => scan.fetch("candidate_bytes"),
        "preview_timestamp" => stored["preview_timestamp"]
      }
      scope["manifest_digest"] = scan.fetch("manifest_digest") if stored.key?("manifest_digest")
      scope
    end

    def move_to_trash(source)
      files_dir = File.join(@trash_root, "files")
      info_dir = File.join(@trash_root, "info")
      FileUtils.mkdir_p(files_dir)
      FileUtils.mkdir_p(info_dir)

      basename = File.basename(source)
      trash_name = collision_safe_name(files_dir, basename)
      destination = File.join(files_dir, trash_name)
      info_path = File.join(info_dir, "#{trash_name}.trashinfo")

      FileUtils.mv(source, destination)
      File.write(
        info_path,
        [
          "[Trash Info]",
          "Path=#{URI.encode_www_form_component(File.expand_path(source)).gsub('+', '%20')}",
          "DeletionDate=#{@clock.call.strftime('%Y-%m-%dT%H:%M:%S')}",
          ""
        ].join("\n")
      )
      destination
    rescue StandardError
      if defined?(destination) && destination && File.exist?(destination) && !File.exist?(source)
        FileUtils.mv(destination, source)
      end
      FileUtils.rm_f(info_path) if defined?(info_path) && info_path
      raise
    end

    def collision_safe_name(files_dir, basename)
      return basename unless File.exist?(File.join(files_dir, basename))

      stem = File.basename(basename, File.extname(basename))
      ext = File.extname(basename)
      index = 1
      loop do
        candidate = "#{stem}.#{index}#{ext}"
        return candidate unless File.exist?(File.join(files_dir, candidate))
        index += 1
      end
    end

    def blocked_result(message, blocked_by, token_id:, record_history:)
      result = Result.new(
        ok: false,
        status: "blocked",
        message: message,
        skill_id: "downloads.move_to_trash",
        risk: "approval_required",
        confirmation_required: true,
        executed: false,
        stdout: "",
        stderr: "",
        exit_status: nil,
        blocked_by: blocked_by,
        generated_at: @clock.call.iso8601,
        history_entry: nil
      )
      record(result, "move approved downloads to trash", token_id) if record_history
      result
    end

    def record(result, message, token_id)
      result.history_entry = @history.record(
        result,
        message: "#{message} token=#{token_id}",
        source: "chat"
      )
    end

    def relative_home_path(path)
      home = File.expand_path(Dir.home)
      expanded = File.expand_path(path)
      return "~#{expanded.delete_prefix(home)}" if expanded == home || expanded.start_with?("#{home}/")

      expanded
    end

    def self.default_trash_root
      data_home = ENV["XDG_DATA_HOME"]
      base = data_home && !data_home.empty? ? data_home : File.join(Dir.home, ".local", "share")
      File.join(base, "Trash")
    end

    def default_trash_root
      self.class.default_trash_root
    end
  end
end
