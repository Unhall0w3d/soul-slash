# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "timeout"
require "time"
require "uri"

module SoulCore
  class FleetObservabilitySummaryService
    SCHEMA_VERSION = "soul.fleet-observability.summary.a3.v1"
    MAX_RESULTS_PER_QUERY = 32
    MAX_OUTPUT_BYTES = 256 * 1024
    QUERY_TIMEOUT_SECONDS = 5
    TOTAL_TIMEOUT_SECONDS = 30
    IDENTIFIER = /\A[a-zA-Z0-9_.-]{1,80}\z/
    QUERIES = {
      "endpoint_age" => 'max by (device_id, role) (time() - timestamp(node_uname_info))',
      "cpu_pressure" => '100 - avg by (device_id, role) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100',
      "memory_pressure" => '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)',
      "root_pressure" => '100 * (1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"})',
      "host_network_errors" => 'sum by (device_id, role) (rate(node_network_receive_errs_total{device!~"lo|veth.*|docker.*|br-.*|virbr.*|tailscale.*"}[5m]) + rate(node_network_transmit_errs_total{device!~"lo|veth.*|docker.*|br-.*|virbr.*|tailscale.*"}[5m]))',
      "switch_up" => 'up{job="switch_interfaces"}',
      "switch_errors" => 'sum by (device_id, ifName) (rate(ifInErrors[5m]) + rate(ifOutErrors[5m]))',
      "alerts" => 'ALERTS{alertstate="firing",scope=~"fleet|network"}',
      "boot_age" => 'max by (device_id, role) (time() - node_boot_time_seconds)'
    }.freeze

    class SshPrometheusClient
      def initialize(alias_name:, ssh_config_path: nil, ssh_path: "/usr/bin/ssh")
        raise ArgumentError, "observatory SSH alias is invalid" unless alias_name.to_s.match?(IDENTIFIER)

        @alias_name = alias_name.to_s
        @ssh_config_path = ssh_config_path.to_s
        @ssh_path = ssh_path
      end

      def query(promql)
        encoded = URI.encode_www_form_component(promql)
        remote = "/usr/bin/curl --fail --silent --show-error --max-time 4 " \
          "#{Shellwords.escape("http://127.0.0.1:9090/api/v1/query?query=#{encoded}")}"
        stdout, stderr, status = Timeout.timeout(QUERY_TIMEOUT_SECONDS) do
          argv = [@ssh_path]
          argv.concat(["-F", @ssh_config_path]) unless @ssh_config_path.empty?
          argv.concat(["-o", "BatchMode=yes", "-o", "ConnectTimeout=4", "--", @alias_name, remote])
          Open3.capture3(*argv)
        end
        raise "observatory query failed: #{safe_error(stderr)}" unless status.success?
        raise "observatory response exceeded the bounded limit" if stdout.bytesize > MAX_OUTPUT_BYTES

        JSON.parse(stdout)
      rescue Timeout::Error
        raise "observatory query timed out"
      rescue JSON::ParserError
        raise "observatory returned invalid JSON"
      end

      private

      def safe_error(value)
        value.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]").byteslice(0, 160).to_s
      end
    end

    def initialize(query_client: nil, process_env: ENV, clock: -> { Time.now.utc })
      @process_env = process_env.to_h
      @clock = clock
      @query_client = query_client || SshPrometheusClient.new(
        alias_name: @process_env.fetch("SOUL_OBSERVABILITY_SSH_ALIAS", "observatory"),
        ssh_config_path: @process_env.fetch("SOUL_OBSERVABILITY_SSH_CONFIG", File.join(@process_env.fetch("HOME", Dir.home), ".ssh", "config"))
      )
    end

    def summary
      query_results = {}
      Timeout.timeout(TOTAL_TIMEOUT_SECONDS) do
        QUERIES.each { |query_id, promql| query_results[query_id] = read_query(promql) }
      end
      report = normalize(query_results)
      complete(report)
    rescue StandardError => error
      failed("fleet observability summary failed safely: #{safe_text(error.message, 180)}")
    end

    private

    def read_query(promql)
      payload = @query_client.query(promql)
      raise "Prometheus query was unsuccessful" unless payload.is_a?(Hash) && payload["status"] == "success"

      Array(payload.dig("data", "result")).first(MAX_RESULTS_PER_QUERY).filter_map do |row|
        next unless row.is_a?(Hash)
        labels = row["metric"].is_a?(Hash) ? row.fetch("metric") : {}
        value = Array(row["value"])[1]
        {
          "device_id" => identifier(labels["device_id"] || labels["instance"]),
          "role" => identifier(labels["role"]),
          "interface" => identifier(labels["ifName"]),
          "alert" => identifier(labels["alertname"]),
          "severity" => identifier(labels["severity"]),
          "value" => numeric(value)
        }.compact
      end
    rescue StandardError => error
      {"unavailable" => true, "reason" => safe_text(error.message, 160)}
    end

    def normalize(results)
      gaps = results.filter_map do |query_id, rows|
        next unless rows.is_a?(Hash) && rows["unavailable"]
        {"source_id" => query_id, "reason" => rows["reason"]}
      end
      rows = ->(query_id) { results[query_id].is_a?(Array) ? results.fetch(query_id) : [] }
      endpoint_age = rows.call("endpoint_age")
      switches = rows.call("switch_up")
      alerts = rows.call("alerts")
      if switches.empty? && !(results["switch_up"].is_a?(Hash) && results["switch_up"]["unavailable"])
        gaps << {"source_id" => "switch_up", "reason" => "No reviewed SNMP switch target is currently reporting."}
      end
      switches.select { |row| row["value"].to_f != 1.0 }.each do |row|
        gaps << {"source_id" => "switch_up", "device_id" => row["device_id"], "reason" => "The reviewed switch target is not currently reporting."}
      end
      {
        "schema_version" => SCHEMA_VERSION,
        "state" => state_for(endpoint_age, switches, alerts, gaps),
        "collected_at" => @clock.call.utc.iso8601,
        "endpoints" => {
          "reporting" => endpoint_age.count { |row| row["value"].to_f <= 180 },
          "stale" => endpoint_age.count { |row| row["value"].to_f > 180 },
          "records" => endpoint_age
        },
        "pressure" => {
          "cpu" => rows.call("cpu_pressure"),
          "memory" => rows.call("memory_pressure"),
          "root_filesystem" => rows.call("root_pressure")
        },
        "network" => {
          "host_errors" => rows.call("host_network_errors").select { |row| row["value"].to_f.positive? },
          "switches_reporting" => switches.count { |row| row["value"].to_f == 1.0 },
          "switches_unavailable" => switches.count { |row| row["value"].to_f != 1.0 },
          "switch_records" => switches,
          "switch_interface_errors" => rows.call("switch_errors").select { |row| row["value"].to_f.positive? }
        },
        "alerts" => alerts,
        "boot_age" => rows.call("boot_age"),
        "gaps" => gaps,
        "grafana_url" => grafana_url,
        "query_ids" => QUERIES.keys,
        "raw_promql_exposed" => false,
        "raw_journal_returned" => false,
        "automatic_refresh" => false,
        "background_polling" => false,
        "mutation_authority" => "none"
      }
    end

    def state_for(endpoint_age, switches, alerts, gaps)
      return "unavailable" if endpoint_age.empty? && gaps.length == QUERIES.length
      return "attention" if endpoint_age.any? { |row| row["value"].to_f > 180 } || switches.any? { |row| row["value"].to_f != 1.0 } || alerts.any?
      return "partial" unless gaps.empty?

      "healthy"
    end

    def grafana_url
      value = @process_env["SOUL_OBSERVABILITY_GRAFANA_URL"].to_s
      return nil if value.empty?
      uri = URI.parse(value)
      return nil unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?

      value.byteslice(0, 240)
    rescue URI::InvalidURIError
      nil
    end

    def identifier(value)
      text = value.to_s
      text.match?(IDENTIFIER) ? text : nil
    end

    def numeric(value)
      number = Float(value)
      return nil unless number.finite?

      number.round(4)
    rescue ArgumentError, TypeError
      nil
    end

    def complete(data)
      {"ok" => true, "lifecycle_state" => "complete", "message" => "Fleet observability summary collected.", "data" => data, "mutation" => "none"}
    end

    def failed(message)
      {"ok" => false, "lifecycle_state" => "failed", "message" => message, "data" => {"mutation_authority" => "none"}, "mutation" => "none"}
    end

    def safe_text(value, maximum)
      value.to_s.gsub(%r{/(?:home|run|etc)/[^\s]+}, "[private path]").byteslice(0, maximum).to_s
    end
  end
end
