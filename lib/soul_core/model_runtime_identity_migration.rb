# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "uri"
require_relative "bounded_command_runner"

module SoulCore
  class ModelRuntimeIdentityMigration
    OLD_ALIAS = "soul-qwen3-8b-q4"
    NEW_ALIAS = "soul-local-chat"
    CONFIRMATION = "MIGRATE_MODEL_ALIAS_TO_SOUL_LOCAL_CHAT"
    ACTIVE_SERVICES = %w[llama-server.service soul-model-amd.service].freeze
    DASHBOARD_SERVICE = "soul-dashboard.service"
    MAX_FILE_BYTES = 128 * 1024
    MAX_READY_ATTEMPTS = 12

    def initialize(root:, home:, runtime_control:, runner: BoundedCommandRunner.new, probe: nil, sleeper: ->(seconds) { sleep(seconds) })
      @root = File.expand_path(root)
      @home = File.expand_path(home)
      @runtime_control = runtime_control
      @runner = runner
      @probe = probe || method(:probe_models)
      @sleeper = sleeper
    end

    def plan
      records = build_records
      observation = runtime_observation
      blocker = runtime_blocker(observation)
      return blocked(blocker, data: public_plan(records, observation)) if blocker

      scope = digest_scope(records, observation)
      blocked("human review and exact confirmation are required", data: public_plan(records, observation).merge(
        "expected_digest" => digest(scope),
        "confirmation_phrase" => CONFIRMATION
      ))
    rescue StandardError => error
      blocked(error.message)
    end

    def execute(confirmation:, expected_digest:)
      return awaiting("confirmation and preview digest are required") if confirmation.to_s.empty? || expected_digest.to_s.empty?

      records = build_records
      observation = runtime_observation
      blocker = runtime_blocker(observation)
      return blocked(blocker, data: public_plan(records, observation)) if blocker
      return blocked("exact model alias migration confirmation did not match") unless confirmation == CONFIRMATION

      scope = digest_scope(records, observation)
      return blocked("model alias migration state changed; preview again") unless secure_compare(expected_digest, digest(scope))

      migrate(records, observation.fetch("active_profile_id"), observation.fetch("provider_endpoint"))
    rescue StandardError => error
      failed(error.message)
    end

    private

    def paths
      {
        "environment" => File.join(@root, ".env"),
        "amd_unit" => File.join(@home, ".config/systemd/user/soul-model-amd.service"),
        "nvidia_override" => File.join(@home, ".config/systemd/user/llama-server.service.d/override.conf")
      }
    end

    def build_records
      paths.map do |kind, path|
        validate_file!(path)
        content = File.binread(path, MAX_FILE_BYTES)
        candidate, replacements = candidate_for(kind, content)
        raise "#{kind} must contain exactly one reviewed old alias assignment" unless replacements == 1
        raise "#{kind} contains an unreviewed old alias occurrence" if candidate.include?(OLD_ALIAS)

        {
          "kind" => kind,
          "path" => path,
          "mode" => File.stat(path).mode & 0o777,
          "original" => content,
          "candidate" => candidate,
          "before_sha256" => Digest::SHA256.hexdigest(content),
          "after_sha256" => Digest::SHA256.hexdigest(candidate)
        }
      end
    end

    def validate_file!(path)
      stat = File.lstat(path)
      raise "migration target must be a regular non-symlink file: #{path}" unless stat.file? && !stat.symlink?
      raise "migration target exceeds #{MAX_FILE_BYTES} bytes: #{path}" if stat.size > MAX_FILE_BYTES
    rescue Errno::ENOENT
      raise "migration target does not exist: #{path}"
    end

    def candidate_for(kind, content)
      if kind == "environment"
        pattern = /^(SOUL_LOCAL_OPENAI_MODEL|SOUL_MODEL_ALIAS)=#{Regexp.escape(OLD_ALIAS)}$/
        count = content.scan(pattern).length
        [content.gsub(pattern) { "#{Regexp.last_match(1)}=#{NEW_ALIAS}" }, count]
      else
        pattern = /(?<!\S)(?:"(?:--alias|-a)"|(?:--alias|-a))\s+(?:"#{Regexp.escape(OLD_ALIAS)}"|#{Regexp.escape(OLD_ALIAS)})(?!\S)/
        count = content.scan(pattern).length
        [content.gsub(pattern) { Regexp.last_match(0).sub(OLD_ALIAS, NEW_ALIAS) }, count]
      end
    end

    def runtime_observation
      result = @runtime_control.status
      raise result.fetch("reason", "model runtime status unavailable") unless result["ok"]

      result.fetch("data")
    end

    def runtime_blocker(observation)
      return "exactly one model runtime profile must be active" unless observation["active_profile_count"] == 1
      return "active model work must complete or be canceled before alias migration" unless observation["active_work_count"] == 0
      return "safe idle model state cannot be established" unless observation["idle_certain"]
      return "model server must report ready before alias migration" unless observation.dig("server", "health") == "ready"
      return "active model runtime service is outside the approved set" unless ACTIVE_SERVICES.include?(observation["service"])

      nil
    end

    def public_plan(records, observation)
      {
        "old_api_alias" => OLD_ALIAS,
        "new_api_alias" => NEW_ALIAS,
        "files" => records.map { |record| record.slice("kind", "path", "before_sha256", "after_sha256") },
        "active_profile_id" => observation["active_profile_id"],
        "active_service" => observation["service"],
        "active_work_count" => observation["active_work_count"],
        "idle_certain" => observation["idle_certain"],
        "restart_scope" => [observation["service"], DASHBOARD_SERVICE],
        "reboot_required" => false,
        "automatic_switch_or_fallback" => false
      }
    end

    def digest_scope(records, observation)
      public_plan(records, observation).merge(
        "profile_states" => observation.fetch("profiles").map { |row| row.slice("id", "service", "service_state") }
      )
    end

    def migrate(records, active_profile_id, endpoint)
      active = runtime_service(active_profile_id)
      originals = records.to_h { |record| [record.fetch("path"), record] }
      mutation_began = false
      begin
        command!("stop", active)
        mutation_began = true
        records.each { |record| atomic_write(record.fetch("path"), record.fetch("candidate"), record.fetch("mode")) }
        daemon_reload!
        command!("start", active)
        raise "neutral API alias did not become ready within #{MAX_READY_ATTEMPTS} attempts" unless wait_for_alias(endpoint)
        command!("restart", DASHBOARD_SERVICE)

        complete(public_plan(records, runtime_observation).merge(
          "verified_api_alias" => NEW_ALIAS,
          "active_profile_id" => active_profile_id
        ))
      rescue StandardError => error
        rollback_complete = !mutation_began || rollback(originals, active)
        failed(
          "model alias migration failed: #{error.message}",
          data: { "rollback_complete" => rollback_complete }
        )
      end
    end

    def runtime_service(profile_id)
      case profile_id
      when "nvidia-fallback" then "llama-server.service"
      when "amd-quality" then "soul-model-amd.service"
      else raise "active profile is outside the approved migration set"
      end
    end

    def rollback(originals, active)
      @runner.run("systemctl", "--user", "stop", active, timeout_seconds: 12, max_output_bytes: 8192)
      originals.each_value { |record| atomic_write(record.fetch("path"), record.fetch("original"), record.fetch("mode")) }
      daemon_reload!
      command!("start", active)
      true
    rescue StandardError
      false
    end

    def atomic_write(path, content, mode)
      temporary = "#{path}.#{Process.pid}.tmp"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    def command!(action, service)
      result = @runner.run("systemctl", "--user", action, service, timeout_seconds: 12, max_output_bytes: 8192)
      raise "#{action} #{service} returned #{result.status}" unless result.success?
    end

    def daemon_reload!
      result = @runner.run("systemctl", "--user", "daemon-reload", timeout_seconds: 12, max_output_bytes: 8192)
      raise "systemd user manager reload returned #{result.status}" unless result.success?
    end

    def wait_for_alias(endpoint)
      MAX_READY_ATTEMPTS.times do |attempt|
        return true if @probe.call(endpoint, NEW_ALIAS)
        @sleeper.call(1) if attempt < MAX_READY_ATTEMPTS - 1
      end
      false
    end

    def probe_models(endpoint, expected_alias)
      uri = URI.parse(endpoint.to_s)
      return false unless uri.is_a?(URI::HTTP) && uri.scheme == "http" && %w[127.0.0.1 localhost ::1].include?(uri.host)

      uri.path = "#{uri.path.sub(%r{/+$}, "")}/models"
      uri.query = uri.fragment = nil
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) { |http| http.get(uri.request_uri) }
      return false unless response.code.to_i.between?(200, 299) && response.body.to_s.bytesize <= 128 * 1024

      ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
      ids == [expected_alias]
    rescue StandardError
      false
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(deep_sort(value)))
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end

    def secure_compare(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def complete(data) = { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "model_alias_migrated" }
    def awaiting(reason) = { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "data" => {}, "mutation" => "none" }
    def blocked(reason, data: {}) = { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "data" => data, "mutation" => "none" }
    def failed(reason, data: {}) = { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "data" => data, "mutation" => "partial_or_none" }
  end
end
