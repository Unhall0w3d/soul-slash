# frozen_string_literal: true

require "json"
require "time"
require_relative "approval_token_store"
require_relative "read_only_skill_execution_gate"

module SoulCore
  class ApprovalTokenChatControls
    def initialize(root: Dir.pwd, gate: nil, store: nil)
      @root = File.expand_path(root)
      @store = store || ApprovalTokenStore.new(root: @root)
      @gate = gate || ReadOnlySkillExecutionGate.new(root: @root)
    end

    attr_reader :store

    def approve_downloads_cleanup_preview(ttl_seconds: 900)
      preview = @gate.evaluate("clean up downloads", execute: true, record_history: true)
      return failure("preview_failed", preview.message) unless preview.ok && preview.executed

      payload = JSON.parse(preview.stdout)
      scope = {
        "target_path" => payload["path"],
        "candidate_rule" => payload["candidate_rule"],
        "candidate_count" => payload["candidate_count"],
        "candidate_bytes" => payload["candidate_bytes"],
        "preview_timestamp" => Time.now.iso8601
      }

      token = @store.issue(
        skill_id: "downloads.move_to_trash",
        scope: scope,
        ttl_seconds: ttl_seconds
      )

      {
        "ok" => true,
        "status" => "approved",
        "token" => token,
        "preview" => {
          "candidate_count" => payload["candidate_count"],
          "candidate_bytes" => payload["candidate_bytes"],
          "candidate_rule" => payload["candidate_rule"],
          "target_path" => payload["path"],
          "mutation" => payload["mutation"]
        },
        "mutation_enabled" => false
      }
    rescue JSON::ParserError => error
      failure("preview_parse_failed", error.message)
    end

    def pending
      {
        "ok" => true,
        "status" => "listed",
        "tokens" => @store.pending,
        "count" => @store.pending.length,
        "mutation_enabled" => false
      }
    end

    def revoke(token_id)
      result = @store.revoke(token_id)
      result.merge("mutation_enabled" => false)
    end

    private

    def failure(reason, message)
      {
        "ok" => false,
        "status" => "failed",
        "reason" => reason,
        "message" => message,
        "mutation_enabled" => false
      }
    end
  end
end
