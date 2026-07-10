# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

module SoulCore
  class ApprovalTokenStore
    DEFAULT_PATH = File.join("Soul", "runtime", "approvals", "approval_tokens.json")

    def initialize(root: Dir.pwd, path: DEFAULT_PATH, clock: -> { Time.now })
      @root = File.expand_path(root)
      @path = File.expand_path(path, @root)
      @clock = clock
    end

    attr_reader :path

    def issue(skill_id:, scope:, ttl_seconds: 900)
      now = @clock.call
      record = {
        "token_id" => SecureRandom.hex(16),
        "skill_id" => skill_id.to_s,
        "scope_digest" => scope_digest(scope),
        "scope" => normalize_scope(scope),
        "issued_at" => now.iso8601,
        "expires_at" => (now + Integer(ttl_seconds)).iso8601,
        "used_at" => nil,
        "revoked_at" => nil,
        "status" => "pending"
      }

      records = read_all
      records << record
      write_all(records)
      record
    end

    def list(status: nil)
      rows = read_all.map { |row| refresh_status(row) }
      status ? rows.select { |row| row["status"] == status.to_s } : rows
    end

    def pending
      list(status: "pending")
    end

    def find(token_id)
      row = read_all.find { |record| record["token_id"] == token_id.to_s }
      row && refresh_status(row)
    end

    def validate(token_id:, skill_id:, scope:)
      row = find(token_id)
      return invalid("token_not_found") unless row
      return invalid("token_skill_mismatch", row) unless row["skill_id"] == skill_id.to_s
      return invalid("token_scope_mismatch", row) unless row["scope_digest"] == scope_digest(scope)
      return invalid("token_expired", row) if row["status"] == "expired"
      return invalid("token_revoked", row) if row["status"] == "revoked"
      return invalid("token_already_used", row) if row["status"] == "used"

      { "ok" => true, "status" => "valid", "token" => row }
    end

    def mark_used(token_id)
      update_record(token_id) do |row|
        row["used_at"] = @clock.call.iso8601
        row["status"] = "used"
      end
    end

    def revoke(token_id)
      update_record(token_id) do |row|
        row["revoked_at"] = @clock.call.iso8601
        row["status"] = "revoked"
      end
    end

    def clear(confirm: false)
      return { "ok" => false, "status" => "blocked", "message" => "Approval token clear requires confirm: true." } unless confirm

      existed = File.exist?(@path)
      FileUtils.rm_f(@path)
      { "ok" => true, "status" => "cleared", "deleted" => existed, "path" => relative_path(@path) }
    end

    def relative_path(target = @path)
      Pathname.new(target).relative_path_from(Pathname.new(@root)).to_s
    rescue StandardError
      target
    end

    private

    def invalid(reason, row = nil)
      { "ok" => false, "status" => "invalid", "reason" => reason, "token" => row }
    end

    def refresh_status(row)
      copy = row.dup
      return copy if %w[used revoked].include?(copy["status"])

      copy["status"] = "expired" if Time.parse(copy["expires_at"]) <= @clock.call
      copy
    rescue ArgumentError
      copy["status"] = "invalid"
      copy
    end

    def normalize_scope(scope)
      scope.each_with_object({}) { |(key, value), out| out[key.to_s] = value }.sort.to_h
    end

    def scope_digest(scope)
      Digest::SHA256.hexdigest(JSON.generate(normalize_scope(scope)))
    end

    def read_all
      return [] unless File.exist?(@path)

      Array(JSON.parse(File.read(@path))["tokens"])
    rescue JSON::ParserError
      []
    end

    def write_all(records)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate({ "updated_at" => @clock.call.iso8601, "tokens" => records }) + "\n")
    end

    def update_record(token_id)
      records = read_all
      row = records.find { |record| record["token_id"] == token_id.to_s }
      return { "ok" => false, "status" => "not_found", "token_id" => token_id.to_s } unless row
      return { "ok" => false, "status" => row["status"], "token" => refresh_status(row) } unless row["status"] == "pending"

      yield row
      write_all(records)
      { "ok" => true, "status" => row["status"], "token" => row }
    end
  end
end
