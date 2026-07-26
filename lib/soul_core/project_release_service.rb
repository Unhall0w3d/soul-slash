# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SoulCore
  class ProjectReleaseService
    SCHEMA_VERSION = "soul.project_release.v1"
    MARKER = ".release_state.json"
    MAX_BYTES = 4 * 1024
    KINDS = {
      "music" => { directory: File.join("Soul", "music", "projects"), pattern: /\Amusic_[a-f0-9]{16}\z/ },
      "visual" => { directory: File.join("Soul", "visual", "projects"), pattern: /\Avisual_project_[a-f0-9]{16}\z/ }
    }.freeze

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @clock = clock
    end

    def decorate_outcome(outcome, kind:)
      return outcome unless outcome.is_a?(Hash) && outcome["ok"]
      data = outcome["data"]
      return outcome unless data.is_a?(Hash)
      if data["projects"].is_a?(Array)
        data["projects"] = data["projects"].map { |project| decorate(project, kind: kind) }
      elsif data["project"].is_a?(Hash)
        data["project"] = decorate(data["project"], kind: kind)
      end
      outcome
    end

    def release(kind:, project_id:)
      kind, project_id, directory = validate_target!(kind, project_id)
      released_at = @clock.call.iso8601
      marker = { "schema_version" => SCHEMA_VERSION, "project_kind" => kind, "project_id" => project_id, "released_at" => released_at }
      atomic_json(File.join(directory, MARKER), marker)
      outcome("complete", true, "project moved to Released", {
        "project_kind" => kind, "project_id" => project_id, "release_state" => "released", "released_at" => released_at,
        "identity_preserved" => true, "bindings_preserved" => true
      }, "project_released")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    def restore(kind:, project_id:)
      kind, project_id, directory = validate_target!(kind, project_id)
      marker = File.join(directory, MARKER)
      assert_regular_marker!(marker) if File.exist?(marker) || File.symlink?(marker)
      FileUtils.rm_f(marker)
      outcome("complete", true, "project restored to Active", {
        "project_kind" => kind, "project_id" => project_id, "release_state" => "active",
        "identity_preserved" => true, "bindings_preserved" => true
      }, "project_restored")
    rescue ArgumentError => error
      outcome("awaiting_input", false, error.message)
    rescue StandardError => error
      outcome("blocked_for_human_review", false, error.message)
    end

    private

    def decorate(project, kind:)
      id = project.fetch("project_id")
      _kind, _id, directory = validate_target!(kind, id)
      marker = read_marker(File.join(directory, MARKER), kind: kind, project_id: id)
      project.merge(
        "release_state" => marker ? "released" : "active",
        "released_at" => marker&.fetch("released_at", nil)
      )
    rescue KeyError, ArgumentError
      project.merge("release_state" => "active", "released_at" => nil)
    end

    def validate_target!(kind, project_id)
      name = kind.to_s
      definition = KINDS[name]
      raise ArgumentError, "project kind is invalid" unless definition
      id = project_id.to_s
      raise ArgumentError, "project ID is invalid" unless id.match?(definition.fetch(:pattern))
      root = File.expand_path(definition.fetch(:directory), @root)
      directory = File.join(root, id)
      raise ArgumentError, "project does not exist" unless File.exist?(directory) || File.symlink?(directory)
      stat = File.lstat(directory)
      raise ArgumentError, "project directory must be regular" unless stat.directory? && !stat.symlink?
      [name, id, directory]
    end

    def read_marker(path, kind:, project_id:)
      return nil unless File.exist?(path) || File.symlink?(path)
      assert_regular_marker!(path)
      data = JSON.parse(File.binread(path, MAX_BYTES))
      valid = data.is_a?(Hash) && data.keys.sort == %w[project_id project_kind released_at schema_version].sort &&
        data["schema_version"] == SCHEMA_VERSION && data["project_kind"] == kind && data["project_id"] == project_id
      raise "project release marker is invalid" unless valid
      Time.iso8601(data.fetch("released_at"))
      data
    rescue JSON::ParserError, ArgumentError, KeyError
      raise "project release marker is invalid"
    end

    def assert_regular_marker!(path)
      stat = File.lstat(path)
      raise "project release marker must be a regular file" unless stat.file? && !stat.symlink?
      raise "project release marker exceeds size limit" if stat.size > MAX_BYTES
    end

    def atomic_json(path, value)
      body = JSON.pretty_generate(value) + "\n"
      raise "project release marker exceeds size limit" if body.bytesize > MAX_BYTES
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(body); file.flush; file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def outcome(state, ok, reason, data = {}, mutation = "none")
      { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
    end
  end
end
