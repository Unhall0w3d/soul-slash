# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "socket"
require "time"
require "uri"

module SoulCore
  class WazuhAlertEvidenceService
    SCHEMA_VERSION = "soul.security.wazuh-alerts.v1"
    CONFIG_SCHEMA = "soul.wazuh.alerts.integration.v1"
    MAX_CONFIG_BYTES = 64 * 1024
    MAX_CREDENTIAL_BYTES = 8 * 1024
    MAX_RESPONSE_BYTES = 1024 * 1024
    MAX_ALERTS = 256
    MAX_LOOKBACK_MINUTES = 24 * 60
    REQUEST_TIMEOUT_SECONDS = 10
    TUNNEL_START_TIMEOUT_SECONDS = 5
    SEARCH_PATH = "/wazuh-alerts-*/_search?filter_path=took,hits.total,hits.hits._id,hits.hits._source"
    SOURCE_FIELDS = %w[timestamp rule.level rule.id rule.description agent.id agent.name].freeze
    SSH_ALIAS_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/
    USERNAME_PATTERN = /\A[A-Za-z0-9_.@-]{1,128}\z/

    Response = Struct.new(:code, :body, keyword_init: true)

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      clock: -> { Time.now.utc },
      transport: nil,
      tunnel: nil,
      ssh_path: "/usr/bin/ssh",
      ssh_config_path: File.join(Dir.home, ".ssh", "config")
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
      @transport = transport || method(:perform_request)
      @tunnel = tunnel || method(:with_ssh_tunnel)
      @ssh_path = ssh_path
      @ssh_config_path = File.expand_path(ssh_config_path)
      @snapshot_path = File.join(@root, "Soul", "private", "security", "wazuh", "alerts.json")
    end

    def collect
      config = load_configuration
      return success(unavailable_data(config.fetch("reason"), configured: false)) unless config.fetch("enabled")

      credentials = load_credentials(config.fetch("credential_path"))
      payload = @tunnel.call(config) { search(config, credentials) }
      data = normalize(payload, config)
      persist(data)
      success(data, mutation: "alert_evidence_cache")
    rescue StandardError => error
      data = unavailable_data("Wazuh alert evidence unavailable: #{safe_reason(error)}", configured: true)
      persist(data)
      success(data, mutation: "alert_evidence_cache")
    end

    def snapshot
      return success(unavailable_data("Wazuh alert evidence has not been collected", configured: configured?)) unless File.exist?(@snapshot_path)

      parsed = read_private_json(@snapshot_path, MAX_RESPONSE_BYTES)
      raise "Wazuh alert snapshot schema is unsupported" unless parsed["schema_version"] == SCHEMA_VERSION

      success(parsed.merge("source" => "persisted_wazuh_alert_snapshot"))
    rescue StandardError => error
      success(unavailable_data("Wazuh alert snapshot unavailable: #{safe_reason(error)}", configured: configured?))
    end

    def notification_candidates
      config = load_configuration
      return success(unavailable_data(config.fetch("reason"), configured: false)) unless config.fetch("enabled")

      credentials = load_credentials(config.fetch("credential_path"))
      policy = config.fetch("voice_notifications")
      notification_config = config.merge(
        "minimum_level" => policy.fetch("minimum_level"),
        "maximum_alerts" => MAX_ALERTS,
        "lookback_minutes" => policy.fetch("lookback_minutes")
      )
      payload = @tunnel.call(notification_config) { search(notification_config, credentials) }
      data = normalize(payload, notification_config)
      success(data.merge("purpose" => "durable_notification_candidates"))
    rescue StandardError => error
      success(unavailable_data("Wazuh notification candidates unavailable: #{safe_reason(error)}", configured: true))
    end

    private

    def configured?
      !@process_env.fetch("SOUL_WAZUH_ALERTS_INTEGRATION_FILE", "").to_s.strip.empty?
    end

    def load_configuration
      raw_path = @process_env.fetch("SOUL_WAZUH_ALERTS_INTEGRATION_FILE", "").to_s.strip
      return {"enabled" => false, "reason" => "Wazuh alert integration is not configured"} if raw_path.empty?

      path = File.expand_path(raw_path)
      config = read_private_json(path, MAX_CONFIG_BYTES)
      raise "Wazuh alert integration manifest schema is unsupported" unless config["schema_version"] == CONFIG_SCHEMA
      return {"enabled" => false, "reason" => "Wazuh alert integration is disabled"} unless config["enabled"] == true

      indexer = validate_indexer_url(config.fetch("indexer_url"))
      dashboard = validate_dashboard_url(config.fetch("dashboard_url"))
      credential_path = validate_file_path(config.fetch("credential_path"), private: true, maximum: MAX_CREDENTIAL_BYTES, label: "indexer credential")
      ca_certificate_path = validate_file_path(config.fetch("ca_certificate_path"), private: false, maximum: 128 * 1024, label: "indexer CA certificate")
      ssh_alias = config.fetch("ssh_alias").to_s
      raise "Wazuh alert SSH alias is invalid" unless ssh_alias.match?(SSH_ALIAS_PATTERN)

      minimum_level = bounded_integer(config.fetch("minimum_level", 7), 0..15, "minimum alert level")
      maximum_alerts = bounded_integer(config.fetch("maximum_alerts", 100), 1..MAX_ALERTS, "maximum alert count")
      lookback_minutes = bounded_integer(config.fetch("lookback_minutes", 60), 1..MAX_LOOKBACK_MINUTES, "alert lookback")
      voice = config.fetch("voice_notifications", {})
      raise "Wazuh alert voice policy is invalid" unless voice.is_a?(Hash)
      voice_enabled = voice.fetch("enabled", false)
      raise "Wazuh alert voice policy enabled flag is invalid" unless [true, false].include?(voice_enabled)
      voice_level = bounded_integer(voice.fetch("minimum_level", 10), 1..15, "voice alert level")
      cooldown_seconds = bounded_integer(voice.fetch("cooldown_seconds", 900), 60..86_400, "voice alert cooldown")
      voice_lookback = bounded_integer(voice.fetch("lookback_minutes", 1440), 1..MAX_LOOKBACK_MINUTES, "voice alert lookback")

      {
        "enabled" => true,
        "indexer_url" => indexer.fetch("origin"),
        "local_port" => indexer.fetch("port"),
        "dashboard_url" => dashboard,
        "credential_path" => credential_path,
        "ca_certificate_path" => ca_certificate_path,
        "ssh_alias" => ssh_alias,
        "minimum_level" => minimum_level,
        "maximum_alerts" => maximum_alerts,
        "lookback_minutes" => lookback_minutes,
        "voice_notifications" => {
          "enabled" => voice_enabled,
          "minimum_level" => voice_level,
          "cooldown_seconds" => cooldown_seconds,
          "lookback_minutes" => voice_lookback
        }
      }
    end

    def validate_indexer_url(value)
      uri = URI.parse(value.to_s)
      valid_path = ["", "/"].include?(uri.path.to_s)
      raise "Wazuh indexer URL must be a loopback HTTPS origin" unless uri.is_a?(URI::HTTPS) && uri.host == "127.0.0.1" && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && valid_path
      raise "Wazuh indexer tunnel port must be unprivileged" unless uri.port.between?(1024, 65_535)

      {"origin" => "https://127.0.0.1:#{uri.port}", "port" => uri.port}
    rescue URI::InvalidURIError
      raise "Wazuh indexer URL is invalid"
    end

    def validate_dashboard_url(value)
      uri = URI.parse(value.to_s)
      valid_path = ["", "/"].include?(uri.path.to_s)
      raise "Wazuh dashboard URL must be an HTTPS origin" unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && valid_path

      "https://#{uri.host}:#{uri.port}"
    rescue URI::InvalidURIError
      raise "Wazuh dashboard URL is invalid"
    end

    def validate_file_path(value, private:, maximum:, label:)
      path = File.expand_path(value.to_s)
      raise "Wazuh #{label} path must be absolute" unless value.to_s.start_with?(File::SEPARATOR)
      raise "Wazuh #{label} file is unavailable" unless File.file?(path) && !File.symlink?(path)
      stat = File.stat(path)
      raise "Wazuh #{label} file exceeds its size bound" unless stat.size.between?(1, maximum)
      raise "Wazuh #{label} file must be owner-private" if private && (stat.mode & 0o077).positive?

      path
    end

    def bounded_integer(value, range, label)
      number = value.is_a?(Integer) ? value : Integer(value.to_s, 10)
      raise "Wazuh #{label} is outside its supported bound" unless range.cover?(number)

      number
    rescue ArgumentError, TypeError
      raise "Wazuh #{label} is invalid"
    end

    def load_credentials(path)
      parsed = read_private_json(path, MAX_CREDENTIAL_BYTES)
      username = parsed["username"].to_s
      password = parsed["password"].to_s
      raise "Wazuh indexer credential is invalid" unless username.match?(USERNAME_PATTERN) && password.bytesize.between?(16, 1024)

      {"username" => username, "password" => password}
    end

    def search(config, credentials)
      uri = URI.parse("#{config.fetch("indexer_url")}#{SEARCH_PATH}")
      request = Net::HTTP::Post.new(uri.request_uri)
      request.basic_auth(credentials.fetch("username"), credentials.fetch("password"))
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        "size" => config.fetch("maximum_alerts"),
        "track_total_hits" => true,
        "sort" => [{"timestamp" => {"order" => "desc", "unmapped_type" => "date"}}],
        "_source" => SOURCE_FIELDS,
        "query" => {"bool" => {"filter" => [
          {"range" => {"timestamp" => {"gte" => "now-#{config.fetch("lookback_minutes")}m", "lte" => "now"}}},
          {"range" => {"rule.level" => {"gte" => config.fetch("minimum_level")}}}
        ]}}
      )
      response = @transport.call(
        uri: uri,
        request: request,
        ca_certificate_path: config.fetch("ca_certificate_path"),
        timeout_seconds: REQUEST_TIMEOUT_SECONDS,
        max_response_bytes: MAX_RESPONSE_BYTES
      )
      raise "Wazuh indexer redirect is not allowed" if response.code.to_i.between?(300, 399)
      raise "Wazuh indexer returned HTTP #{response.code}" unless response.code.to_i == 200
      raise "Wazuh indexer response exceeds its size bound" if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

      parsed = JSON.parse(response.body.to_s)
      raise "Wazuh indexer search response is malformed" unless parsed.is_a?(Hash) && parsed["hits"].is_a?(Hash)
      parsed["hits"]["hits"] ||= []
      raise "Wazuh indexer search response is malformed" unless parsed.dig("hits", "hits").is_a?(Array)

      parsed
    end

    def perform_request(uri:, request:, ca_certificate_path:, timeout_seconds:, max_response_bytes:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ca_file = ca_certificate_path
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds
      http.write_timeout = timeout_seconds
      response = http.request(request)
      body = response.body.to_s
      raise "Wazuh indexer response exceeds its size bound" if body.bytesize > max_response_bytes

      Response.new(code: response.code.to_i, body: body)
    end

    def with_ssh_tunnel(config)
      raise "OpenSSH client is unavailable" unless File.file?(@ssh_path) && File.executable?(@ssh_path)
      raise "OpenSSH client configuration must be owner-private" unless private_regular_file?(@ssh_config_path, 128 * 1024)
      port = config.fetch("local_port")
      raise "Wazuh alert tunnel port is already in use" if tcp_open?(port)

      error_reader, error_writer = IO.pipe
      pid = Process.spawn(
        @ssh_path, "-F", @ssh_config_path, "-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=1",
        "-L", "127.0.0.1:#{port}:127.0.0.1:9200", config.fetch("ssh_alias"),
        in: :close, out: File::NULL, err: error_writer
      )
      error_writer.close
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TUNNEL_START_TIMEOUT_SECONDS
      until tcp_open?(port)
        waited = Process.waitpid(pid, Process::WNOHANG)
        raise "Wazuh alert SSH tunnel exited before opening: #{bounded(error_reader.read, 240)}" if waited
        raise "Wazuh alert SSH tunnel did not open in time" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep(0.05)
      end
      yield
    ensure
      error_writer&.close unless error_writer&.closed?
      error_reader&.close unless error_reader&.closed?
      terminate_child(pid) if defined?(pid) && pid
    end

    def tcp_open?(port)
      socket = Socket.tcp("127.0.0.1", port, connect_timeout: 0.15)
      socket.close
      true
    rescue SystemCallError, IOError
      false
    end

    def private_regular_file?(path, maximum)
      return false unless File.file?(path) && !File.symlink?(path)

      stat = File.stat(path)
      stat.size.between?(1, maximum) && (stat.mode & 0o077).zero?
    end

    def terminate_child(pid)
      Process.kill("TERM", pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        return if Process.waitpid(pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep(0.05)
      end
      Process.kill("KILL", pid)
      Process.waitpid(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def normalize(payload, config)
      hits = payload.dig("hits", "hits")
      raise "Wazuh indexer returned too many alerts" unless hits.length <= config.fetch("maximum_alerts")
      alerts = hits.filter_map { |hit| normalize_hit(hit) }
      total = payload.dig("hits", "total")
      total_value = total.is_a?(Hash) ? total["value"].to_i : total.to_i
      collected_at = @clock.call.iso8601
      counts = alerts.each_with_object(Hash.new(0)) { |alert, memo| memo[alert.fetch("severity")] += 1 }
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => true,
        "state" => alerts.any? { |alert| %w[high critical].include?(alert["severity"]) } ? "attention" : "healthy",
        "collected_at" => collected_at,
        "last_successful_at" => collected_at,
        "source" => "wazuh_indexer_read_only",
        "read_only" => true,
        "remote_mutation" => false,
        "dashboard_url" => config.fetch("dashboard_url"),
        "query" => {
          "index_pattern" => "wazuh-alerts-*",
          "minimum_level" => config.fetch("minimum_level"),
          "lookback_minutes" => config.fetch("lookback_minutes"),
          "maximum_alerts" => config.fetch("maximum_alerts"),
          "returned_alerts" => alerts.length,
          "matching_alerts" => total_value,
          "truncated" => total_value > alerts.length
        },
        "notification_policy" => config.fetch("voice_notifications"),
        "summary" => {
          "alert_count" => alerts.length,
          "elevated" => counts["elevated"],
          "high" => counts["high"],
          "critical" => counts["critical"],
          "latest_at" => alerts.first&.fetch("occurred_at", nil)
        },
        "alerts" => alerts,
        "verification" => {
          "loopback_tunnel" => true,
          "credentials_returned" => false,
          "raw_event_returned" => false,
          "active_response_available" => false,
          "write_operation_available" => false
        }
      }
    end

    def normalize_hit(hit)
      return nil unless hit.is_a?(Hash) && hit["_source"].is_a?(Hash) && !hit["_id"].to_s.empty?
      source = hit.fetch("_source")
      raw_level = source.dig("rule", "level")
      level = raw_level.is_a?(Integer) ? raw_level : Integer(raw_level.to_s, 10)
      return nil unless level.between?(0, 15)
      occurred_at = Time.iso8601(source.fetch("timestamp").to_s).utc.iso8601

      {
        "event_id" => Digest::SHA256.hexdigest(hit.fetch("_id").to_s),
        "occurred_at" => occurred_at,
        "level" => level,
        "severity" => severity(level),
        "rule_id" => bounded(source.dig("rule", "id"), 32),
        "description" => bounded(source.dig("rule", "description"), 240),
        "agent_id" => bounded(source.dig("agent", "id"), 16),
        "agent_name" => bounded(source.dig("agent", "name"), 128)
      }
    rescue ArgumentError, KeyError
      nil
    end

    def severity(level)
      return "critical" if level >= 13
      return "high" if level >= 10
      return "elevated" if level >= 7

      "informational"
    end

    def unavailable_data(reason, configured:)
      previous = read_previous
      {
        "schema_version" => SCHEMA_VERSION,
        "available" => false,
        "configured" => configured,
        "state" => "unavailable",
        "collected_at" => @clock.call.iso8601,
        "last_successful_at" => previous["last_successful_at"],
        "reason" => bounded(reason, 320),
        "source" => "wazuh_indexer_read_only",
        "read_only" => true,
        "remote_mutation" => false,
        "alerts" => [],
        "summary" => {"alert_count" => 0, "elevated" => 0, "high" => 0, "critical" => 0}
      }
    end

    def read_previous
      return {} unless File.exist?(@snapshot_path)
      read_private_json(@snapshot_path, MAX_RESPONSE_BYTES)
    rescue StandardError
      {}
    end

    def persist(data)
      directory = File.dirname(@snapshot_path)
      FileUtils.mkdir_p(directory, mode: 0o700)
      File.chmod(0o700, directory)
      raise "refusing symlink Wazuh alert destination" if File.symlink?(@snapshot_path)
      temporary = "#{@snapshot_path}.tmp-#{Process.pid}"
      File.binwrite(temporary, "#{JSON.pretty_generate(data)}\n", mode: "wx", perm: 0o600)
      File.rename(temporary, @snapshot_path)
      File.chmod(0o600, @snapshot_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end

    def read_private_json(path, maximum)
      raise "private JSON path is unsafe" if File.symlink?(path)
      stat = File.stat(path)
      raise "private JSON file is not owner-private" unless stat.file? && (stat.mode & 0o077).zero?
      raise "private JSON file exceeds its size bound" if stat.size > maximum
      JSON.parse(File.binread(path, maximum + 1))
    end

    def safe_reason(error)
      bounded(error.message.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]"), 320)
    end

    def bounded(value, maximum)
      value.to_s.byteslice(0, maximum).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
    end

    def success(data, mutation: "none")
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation}
    end
  end
end
