# frozen_string_literal: true

require "json"
require "time"
require_relative "approval_token_store"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class DownloadsMoveDryRunExecutor
    def initialize(root: Dir.pwd, gate: nil, store: nil)
      @root = File.expand_path(root)
      @store = store || ApprovalTokenStore.new(root: @root)
      @gate = gate || ReadOnlySkillExecutionGate.new(root: @root)
    end

    def execute(token_id:)
      token = @store.find(token_id)
      return failure("token_not_found") unless token

      preview = @gate.evaluate("clean up downloads", execute: true, record_history: true)
      return failure("preview_failed", preview.message) unless preview.ok && preview.executed

      payload = JSON.parse(preview.stdout)
      scope = build_scope(token, payload)

      validation = @store.validate(
        token_id: token_id,
        skill_id: "downloads.move_to_trash",
        scope: scope
      )

      return failure(validation["reason"], nil, validation["token"]) unless validation["ok"]

      {
        "ok" => true,
        "status" => "dry_run_ready",
        "skill_id" => "downloads.move_to_trash",
        "token_id" => token_id,
        "target_path" => payload["path"],
        "candidate_rule" => payload["candidate_rule"],
        "would_move_count" => payload["candidate_count"],
        "would_move_bytes" => payload["candidate_bytes"],
        "candidate_extensions" => payload["candidate_extensions"] || {},
        "candidate_age_buckets" => payload["candidate_age_buckets"] || {},
        "candidate_size_buckets" => payload["candidate_size_buckets"] || {},
        "mutation" => "none",
        "token_consumed" => false,
        "generated_at" => Time.now.iso8601
      }
    rescue JSON::ParserError => error
      failure("preview_parse_failed", error.message)
    end

    private

    def build_scope(token, payload)
      stored = token.fetch("scope", {})
      {
        "target_path" => payload["path"],
        "candidate_rule" => payload["candidate_rule"],
        "candidate_count" => payload["candidate_count"],
        "candidate_bytes" => payload["candidate_bytes"],
        "preview_timestamp" => stored["preview_timestamp"]
      }
    end

    def failure(reason, message = nil, token = nil)
      {
        "ok" => false,
        "status" => "blocked",
        "reason" => reason,
        "message" => message,
        "token" => token,
        "mutation" => "none",
        "token_consumed" => false
      }
    end
  end
end
