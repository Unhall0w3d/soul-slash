# frozen_string_literal: true

require "securerandom"
require "time"

module SoulCore
  class ConversationEvidenceContract
    RUNTIME_NOT_COLLECTED = [
      "host CPU usage or load",
      "host memory usage",
      "disk capacity or utilization",
      "filesystem types",
      "block devices",
      "RAID state",
      "SMART health",
      "temperatures",
      "network latency or packet loss",
      "firewall policy",
      "host service state",
      "authentication logs",
      "scheduled jobs"
    ].freeze

    Evidence = Struct.new(
      :evidence_id,
      :chat_id,
      :tool_id,
      :label,
      :scope,
      :evidence_profile,
      :risk_class,
      :status,
      :collected,
      :claims,
      :not_collected,
      :source,
      :created_at,
      keyword_init: true
    ) do
      def to_h
        {
          "evidence_id" => evidence_id,
          "chat_id" => chat_id,
          "tool_id" => tool_id,
          "label" => label,
          "scope" => scope,
          "evidence_profile" => evidence_profile,
          "risk_class" => risk_class,
          "status" => status,
          "collected" => collected || {},
          "claims" => claims || [],
          "not_collected" => not_collected || [],
          "source" => source || {},
          "created_at" => created_at
        }
      end
    end

    def self.build(tool:, chat_id:, output:, status: "ok", error: nil)
      output_text = output.to_s
      not_collected =
        tool.evidence_profile.to_s == "soul_runtime_status" ? RUNTIME_NOT_COLLECTED : []

      source = {
        "kind" => "deterministic_chat_route",
        "canonical_message" => tool.canonical_message.to_s
      }
      source["error"] = error if error

      Evidence.new(
        evidence_id: evidence_id,
        chat_id: chat_id.to_s,
        tool_id: tool.id.to_s,
        label: tool.label.to_s,
        scope: tool.scope.to_s,
        evidence_profile: tool.evidence_profile.to_s,
        risk_class: tool.risk_class.to_s,
        status: status.to_s,
        collected: status == "ok" ? { "deterministic_output" => output_text } : {},
        claims: status == "ok" ? output_text.lines.map(&:strip).reject(&:empty?).first(100) : [],
        not_collected: not_collected,
        source: source,
        created_at: Time.now.iso8601
      )
    end

    def self.build_structured(tool:, chat_id:, result:)
      data = stringify_keys(result)
      status =
        if data["ok"] == true
          "ok"
        elsif Array(data["claims"]).empty?
          "failed"
        else
          "partial"
        end

      Evidence.new(
        evidence_id: evidence_id,
        chat_id: chat_id.to_s,
        tool_id: tool.id.to_s,
        label: tool.label.to_s,
        scope: data["scope"].to_s.empty? ? tool.scope.to_s : data["scope"].to_s,
        evidence_profile: tool.evidence_profile.to_s,
        risk_class: tool.risk_class.to_s,
        status: status,
        collected: data["collected"] || {},
        claims: Array(data["claims"]),
        not_collected: Array(data["not_collected"]),
        source: {
          "kind" => "bounded_host_collector",
          "assessment" => data["assessment"],
          "commands" => Array(data["commands"]),
          "verification" => data["verification"] || {}
        },
        created_at: data["collected_at"] || Time.now.iso8601
      )
    end

    def self.evidence_id
      "ev_#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4)}"
    end

    def self.stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), output|
          output[key.to_s] = stringify_keys(nested)
        end
      when Array
        value.map { |nested| stringify_keys(nested) }
      else
        value
      end
    end
  end
end
