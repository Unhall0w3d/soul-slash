# frozen_string_literal: true

require "fileutils"
require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "socket"
require "time"
require "uri"

module SoulCore
  class WazuhSecurityStatusService
    SCHEMA_VERSION = "soul.security.wazuh-status.v1"
    CONFIG_SCHEMA = "soul.wazuh.integration.v1"
    MAX_CONFIG_BYTES = 64 * 1024
    MAX_CREDENTIAL_BYTES = 8 * 1024
    MAX_RESPONSE_BYTES = 512 * 1024
    MAX_AGENTS = 256
    MAX_MAPPINGS = 64
    REQUEST_TIMEOUT_SECONDS = 8
    REQUIRED_MANAGER_DAEMONS = %w[
      wazuh-analysisd
      wazuh-authd
      wazuh-monitord
      wazuh-execd
      wazuh-logcollector
      wazuh-remoted
      wazuh-syscheckd
      wazuh-modulesd
      wazuh-db
      wazuh-apid
    ].freeze
    AGENT_ID_PATTERN = /\A\d{3,8}\z/
    DEVICE_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/

    Response = Struct.new(:code, :body, keyword_init: true)

    def initialize(
      root: Dir.pwd,
      process_env: ENV,
      clock: -> { Time.now.utc },
      transport: nil,
      resolver: nil
    )
      @root = File.expand_path(root)
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
      @transport = transport || method(:perform_request)
      @resolver = resolver || method(:resolve_addresses)
      @snapshot_path = File.join(@root, "Soul", "private", "security", "wazuh", "status.json")
    end

    def collect
      config = load_configuration
      return unavailable(config.fetch("reason"), configured: false) unless config.fetch("enabled")

      credentials = load_credentials(config.fetch("credential_path"))
      token = authenticate(config, credentials)
      info = api_json(config, token, "/")
      manager = api_json(config, token, "/manager/status")
      agents = api_json(
        config,
        token,
        "/agents?limit=#{MAX_AGENTS}&select=id,name,ip,status,lastKeepAlive,version,os.name&sort=%2Bid"
      )
      collected_at = @clock.call.iso8601
      normalized_agents = normalize_agents(agents)
      data = {
        "schema_version" => SCHEMA_VERSION,
        "available" => true,
        "state" => security_state(normalized_agents, normalize_manager(manager)),
        "collected_at" => collected_at,
        "last_successful_at" => collected_at,
        "source" => "wazuh_server_api",
        "read_only" => true,
        "remote_mutation" => false,
        "alert_query_available" => false,
        "alert_query_reason" => "Wazuh indexer access is not configured in A4a",
        "dashboard_url" => config.fetch("dashboard_url"),
        "api" => normalize_api_info(info),
        "manager" => normalize_manager(manager),
        "summary" => summarize_agents(normalized_agents),
        "agents" => normalized_agents,
        "devices" => associate_devices(config.fetch("device_mappings"), normalized_agents, config.fetch("dashboard_url")),
        "verification" => {
          "bounded_responses" => true,
          "redirects_followed" => false,
          "credentials_returned" => false,
          "indexer_queried" => false,
          "active_response_available" => false
        }
      }
      persist(data)
      success(data, mutation: "status_cache")
    rescue StandardError => error
      data = unavailable_data("Wazuh status unavailable: #{safe_reason(error)}", configured: true)
      persist(data)
      success(data, mutation: "status_cache")
    end

    def snapshot
      return success(unavailable_data("Wazuh status has not been collected", configured: configured?)) unless File.exist?(@snapshot_path)

      parsed = read_private_json(@snapshot_path, MAX_RESPONSE_BYTES)
      raise "Wazuh status snapshot schema is unsupported" unless parsed["schema_version"] == SCHEMA_VERSION

      success(parsed.merge("source" => "persisted_wazuh_snapshot"))
    rescue StandardError => error
      success(unavailable_data("Wazuh status snapshot unavailable: #{safe_reason(error)}", configured: configured?))
    end

    private

    def configured?
      !@process_env.fetch("SOUL_WAZUH_INTEGRATION_FILE", "").to_s.strip.empty?
    end

    def load_configuration
      raw_path = @process_env.fetch("SOUL_WAZUH_INTEGRATION_FILE", "").to_s.strip
      return {"enabled" => false, "reason" => "Wazuh integration is not configured"} if raw_path.empty?

      path = File.expand_path(raw_path)
      config = read_private_json(path, MAX_CONFIG_BYTES)
      raise "Wazuh integration manifest schema is unsupported" unless config["schema_version"] == CONFIG_SCHEMA
      return {"enabled" => false, "reason" => "Wazuh integration is disabled"} unless config["enabled"] == true

      server_api = validate_origin(config.fetch("server_api_url"), ports: [55_000], label: "server API")
      dashboard = validate_origin(config.fetch("dashboard_url"), ports: [443, 8_443], label: "dashboard")
      credential_path = validate_file_path(config.fetch("credential_path"), private: true, maximum: MAX_CREDENTIAL_BYTES, label: "credential")
      ca_certificate_path = validate_file_path(config.fetch("ca_certificate_path"), private: false, maximum: 128 * 1024, label: "CA certificate")
      mappings = normalize_mappings(config.fetch("device_mappings", []))
      {
        "enabled" => true,
        "server_api_url" => server_api.fetch("origin"),
        "server_api_address" => server_api.fetch("connect_address"),
        "dashboard_url" => dashboard.fetch("origin"),
        "credential_path" => credential_path,
        "ca_certificate_path" => ca_certificate_path,
        "device_mappings" => mappings
      }
    end

    def validate_origin(value, ports:, label:)
      uri = URI.parse(value.to_s)
      raise "Wazuh #{label} URL must be an HTTPS origin" unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ["", "/"].include?(uri.path.to_s)
      raise "Wazuh #{label} port is not allowed" unless ports.include?(uri.port)

      addresses = Array(@resolver.call(uri.host)).map { |address| IPAddr.new(address) }
      raise "Wazuh #{label} host did not resolve" if addresses.empty?
      raise "Wazuh #{label} must resolve only to private IPv4 addresses" unless addresses.all? { |address| address.ipv4? && address.private? }

      {"origin" => "https://#{uri.host}:#{uri.port}", "connect_address" => addresses.first.to_s}
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      raise "Wazuh #{label} URL is invalid"
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

    def normalize_mappings(records)
      raise "Wazuh device mappings must be an array" unless records.is_a?(Array) && records.length <= MAX_MAPPINGS

      normalized = records.map do |record|
        raise "Wazuh device mapping is invalid" unless record.is_a?(Hash)

        device_id = record["device_id"].to_s
        agent_id = record["agent_id"].to_s
        raise "Wazuh device mapping identity is invalid" unless device_id.match?(DEVICE_ID_PATTERN) && agent_id.match?(AGENT_ID_PATTERN) && agent_id != "000"

        {"device_id" => device_id, "agent_id" => agent_id}
      end
      raise "Wazuh device mappings must be unique" unless normalized.map { |record| record["device_id"] }.uniq.length == normalized.length && normalized.map { |record| record["agent_id"] }.uniq.length == normalized.length

      normalized
    end

    def load_credentials(path)
      parsed = read_private_json(path, MAX_CREDENTIAL_BYTES)
      username = parsed["username"].to_s
      password = parsed["password"].to_s
      raise "Wazuh API credential is invalid" unless username.match?(/\A[A-Za-z0-9_.@-]{1,128}\z/) && password.bytesize.between?(12, 1024)

      {"username" => username, "password" => password}
    end

    def authenticate(config, credentials)
      uri = endpoint_uri(config.fetch("server_api_url"), "/security/user/authenticate?raw=true")
      request = Net::HTTP::Post.new(uri.request_uri)
      request.basic_auth(credentials.fetch("username"), credentials.fetch("password"))
      request["Accept"] = "text/plain"
      response = perform_api_request(config, uri, request)
      raise "Wazuh API authentication returned HTTP #{response.code}" unless response.code == 200

      token = response.body.to_s.strip
      raise "Wazuh API token response is invalid" unless token.match?(/\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/) && token.bytesize <= 16 * 1024

      token
    end

    def api_json(config, token, path)
      uri = endpoint_uri(config.fetch("server_api_url"), path)
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      response = perform_api_request(config, uri, request)
      raise "Wazuh API returned HTTP #{response.code}" unless response.code == 200

      parsed = JSON.parse(response.body.to_s)
      raise "Wazuh API reported an error" unless parsed.is_a?(Hash) && parsed.fetch("error", 0).to_i.zero?

      parsed
    end

    def perform_api_request(config, uri, http_request)
      response = @transport.call(
        uri: uri,
        request: http_request,
        ca_certificate_path: config.fetch("ca_certificate_path"),
        connect_address: config.fetch("server_api_address"),
        timeout_seconds: REQUEST_TIMEOUT_SECONDS,
        max_response_bytes: MAX_RESPONSE_BYTES
      )
      raise "Wazuh API redirect is not allowed" if response.code.to_i.between?(300, 399)
      raise "Wazuh API response exceeds its size bound" if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

      Response.new(code: response.code.to_i, body: response.body.to_s)
    end

    def perform_request(uri:, request:, ca_certificate_path:, connect_address:, timeout_seconds:, max_response_bytes:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = connect_address
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ca_file = ca_certificate_path
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds
      http.write_timeout = timeout_seconds
      response = http.request(request)
      body = response.body.to_s
      raise "Wazuh API response exceeds its size bound" if body.bytesize > max_response_bytes

      Response.new(code: response.code.to_i, body: body)
    end

    def endpoint_uri(origin, path)
      uri = URI.parse("#{origin}#{path}")
      raise "Wazuh API request escaped its configured origin" unless uri.scheme == "https" && origin == "https://#{uri.host}:#{uri.port}"

      uri
    end

    def normalize_api_info(payload)
      data = payload["data"].is_a?(Hash) ? payload["data"] : payload
      {
        "title" => bounded(data["title"], 120),
        "version" => bounded(data["api_version"], 64),
        "hostname" => bounded(data["hostname"], 128)
      }
    end

    def normalize_manager(payload)
      items = payload.dig("data", "affected_items")
      record = items.is_a?(Array) ? items.first : items
      daemons = record.is_a?(Hash) ? record : {}
      normalized = daemons.first(64).to_h { |name, state| [bounded(name, 80), bounded(state, 40)] }
      required = REQUIRED_MANAGER_DAEMONS.to_h { |name| [name, normalized[name]] }
      active = required.values.count { |state| state == "running" }
      state = if normalized.empty?
                "unavailable"
              elsif active == REQUIRED_MANAGER_DAEMONS.length
                "healthy"
              else
                "attention"
              end
      {
        "state" => state,
        "active_daemons" => active,
        "daemon_count" => REQUIRED_MANAGER_DAEMONS.length,
        "optional_daemons" => normalized.keys.reject { |name| REQUIRED_MANAGER_DAEMONS.include?(name) }.length,
        "daemons" => normalized
      }
    end

    def normalize_agents(payload)
      items = payload.dig("data", "affected_items")
      raise "Wazuh agents response is malformed" unless items.is_a?(Array) && items.length <= MAX_AGENTS

      items.filter_map do |record|
        next unless record.is_a?(Hash) && record["id"].to_s.match?(AGENT_ID_PATTERN)
        next if record["id"].to_s == "000"

        {
          "id" => record["id"].to_s,
          "name" => bounded(record["name"], 128),
          "status" => normalize_agent_status(record["status"]),
          "last_seen_at" => bounded(record["lastKeepAlive"], 64),
          "version" => bounded(record["version"], 80),
          "os" => bounded(record.dig("os", "name"), 120)
        }
      end.sort_by { |agent| agent.fetch("id") }
    end

    def normalize_agent_status(value)
      status = value.to_s.downcase.tr(" ", "_")
      %w[active disconnected pending never_connected].include?(status) ? status : "unknown"
    end

    def security_state(agents, manager)
      return "attention" unless manager["state"] == "healthy"
      return "attention" if agents.empty? || agents.any? { |agent| agent["status"] != "active" }

      "healthy"
    end

    def summarize_agents(agents)
      counts = agents.each_with_object(Hash.new(0)) { |agent, result| result[agent.fetch("status")] += 1 }
      {
        "agent_count" => agents.length,
        "active" => counts["active"],
        "disconnected" => counts["disconnected"],
        "pending" => counts["pending"],
        "never_connected" => counts["never_connected"],
        "unknown" => counts["unknown"]
      }
    end

    def associate_devices(mappings, agents, dashboard_url)
      by_id = agents.to_h { |agent| [agent.fetch("id"), agent] }
      mappings.map do |mapping|
        agent = by_id[mapping.fetch("agent_id")]
        {
          "device_id" => mapping.fetch("device_id"),
          "agent_id" => mapping.fetch("agent_id"),
          "state" => agent ? (agent["status"] == "active" ? "monitored" : "attention") : "unavailable",
          "agent_status" => agent ? agent.fetch("status") : "not_returned",
          "agent_name" => agent ? agent.fetch("name") : "unavailable",
          "last_seen_at" => agent ? agent.fetch("last_seen_at") : "unavailable",
          "version" => agent ? agent.fetch("version") : "unavailable",
          "alert_evidence" => "not_integrated",
          "dashboard_url" => dashboard_url,
          "read_only" => true,
          "remediation_authority" => false
        }
      end
    end

    def unavailable(reason, configured:)
      success(unavailable_data(reason, configured: configured))
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
        "source" => "wazuh_server_api",
        "read_only" => true,
        "remote_mutation" => false,
        "alert_query_available" => false,
        "agents" => [],
        "devices" => [],
        "summary" => {"agent_count" => 0, "active" => 0, "disconnected" => 0, "pending" => 0, "never_connected" => 0, "unknown" => 0}
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
      raise "refusing symlink Wazuh status destination" if File.symlink?(@snapshot_path)

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

    def resolve_addresses(host)
      Addrinfo.getaddrinfo(host, nil, Socket::AF_INET, Socket::SOCK_STREAM).map(&:ip_address).uniq
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
