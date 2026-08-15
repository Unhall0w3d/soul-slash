# frozen_string_literal: true

require "time"

module SoulCore
  # Read-only normalization over the already-retained fleet snapshot and
  # device-operation receipts. It deliberately does not collect or persist.
  class FleetOperationsEvidenceService
    SCHEMA_VERSION = "soul.maintenance.fleet_evidence.a0.v1"
    MAX_DEVICES = 64
    MAX_TRANSACTIONS = 64
    FRESH_SECONDS = 24 * 60 * 60
    AGING_SECONDS = 72 * 60 * 60
    FAILURE_STATES = %w[failed blocked blocked_for_human_review canceled unavailable invalid].freeze
    UNASSESSED_UPDATE_FRESHNESS = %w[not_queried provider_managed firmware_inventory unavailable].freeze

    def initialize(fleet_snapshot_source:, device_receipt_source:, clock: -> { Time.now.utc })
      @fleet_snapshot_source = fleet_snapshot_source
      @device_receipt_source = device_receipt_source
      @clock = clock
    end

    def compose
      fleet = read_source("fleet_snapshot", @fleet_snapshot_source)
      receipts = read_source("device_receipts", @device_receipt_source)
      devices = fleet.fetch("available") ? normalize_devices(fleet.fetch("payload")) : []
      transactions = receipts.fetch("available") ? normalize_transactions(receipts.fetch("payload"), devices) : []
      latest_by_device = transactions.group_by { |row| row.fetch("device_id") }
        .transform_values { |rows| rows.max_by { |row| [row.fetch("finished_at", ""), row.fetch("receipt_id")] } }
      devices.each { |device| device["latest_transaction"] = latest_by_device[device.fetch("device_id")] }

      complete(
        "schema_version" => SCHEMA_VERSION,
        "generated_at" => iso8601(@clock.call),
        "devices" => devices,
        "transactions" => transactions,
        "summary" => summarize(devices, transactions),
        "sources" => [fleet, receipts].map { |result| result.fetch("source") },
        "limits" => {"devices" => MAX_DEVICES, "transactions" => MAX_TRANSACTIONS},
        "contract" => {
          "execution_and_reconciliation_are_separate" => true,
          "automatic_refresh" => false,
          "background_polling" => false,
          "mutation_authority" => "none",
          "fleet_wide_action" => false
        }
      )
    rescue StandardError
      failed("fleet operations evidence failed safely")
    end

    private

    def read_source(source_id, callable)
      return unavailable_source(source_id, "source callable is unavailable") unless callable.respond_to?(:call)

      raw = callable.call
      return unavailable_source(source_id, "retained source is unavailable") unless raw.is_a?(Hash)
      return unavailable_source(source_id, "retained source is unavailable") if raw["ok"] == false || raw["available"] == false

      payload = raw["data"].is_a?(Hash) ? raw.fetch("data") : raw
      return unavailable_source(source_id, "retained source is unavailable") if payload["available"] == false

      count = source_id == "fleet_snapshot" ? Array(payload["devices"]).length : Array(payload["receipts"]).length
      {
        "available" => true,
        "payload" => payload,
        "source" => {
          "source_id" => source_id,
          "available" => true,
          "record_count" => count,
          "observed_at" => normalized_time(payload["collected_at"])
        }.compact
      }
    rescue StandardError
      unavailable_source(source_id, "retained source could not be read")
    end

    def unavailable_source(source_id, reason)
      {
        "available" => false,
        "payload" => {},
        "source" => {"source_id" => source_id, "available" => false, "record_count" => 0, "reason" => reason}
      }
    end

    def normalize_devices(payload)
      Array(payload["devices"]).filter_map.with_index do |device, index|
        next unless device.is_a?(Hash)

        updates = device["updates"].is_a?(Hash) ? device.fetch("updates") : {}
        reboot = device["reboot"].is_a?(Hash) ? device.fetch("reboot") : {}
        facts = device["facts"].is_a?(Hash) ? device.fetch("facts") : {}
        inventory_id = safe_identifier(device["id"], "device-#{index + 1}")
        device_id = safe_identifier(facts["control_target_id"], inventory_id)
        observed_at = normalized_time(device["observed_at"] || payload["collected_at"])
        assessed = updates_assessed?(updates)
        {
          "device_id" => device_id,
          "inventory_id" => inventory_id,
          "label" => safe_text(device["label"], 80, fallback: device_id),
          "role" => safe_text(device["role"], 120, fallback: "unspecified"),
          "reachable" => device["reachable"] == true,
          "status" => safe_identifier(device["status"], "unknown"),
          "observed_at" => observed_at,
          "observation_freshness" => observation_freshness(observed_at),
          "control" => safe_identifier(device["control"], "status_only"),
          "management_channel" => safe_identifier(facts["management_channel"], "unavailable"),
          "maintenance_adapter" => safe_identifier(facts["maintenance_adapter"], "none"),
          "updates" => {
            "assessed" => assessed,
            "total" => assessed ? nonnegative_integer(updates["total"]) : nil,
            "freshness" => safe_identifier(updates["freshness"], "unknown")
          },
          "reboot" => {"required" => reboot["required"] == true}
        }
      end.sort_by { |device| [device.fetch("label").downcase, device.fetch("device_id")] }.first(MAX_DEVICES)
    end

    def normalize_transactions(payload, devices)
      device_index = devices.to_h { |device| [device.fetch("device_id"), device] }
      rows = Array(payload["receipts"]).filter_map.with_index do |receipt, index|
        next unless receipt.is_a?(Hash)

        device_id = safe_identifier(receipt["device_id"], "unknown-device")
        lifecycle = safe_identifier(receipt["lifecycle_state"], "unknown")
        finished_at = normalized_time(receipt["finished_at"])
        transaction = {
          "receipt_id" => safe_identifier(receipt["receipt_id"], "receipt-#{index + 1}"),
          "device_id" => device_id,
          "action" => safe_identifier(receipt["action"], "unknown"),
          "execution_state" => lifecycle,
          "started_at" => normalized_time(receipt["started_at"]),
          "finished_at" => finished_at,
          "maintenance_adapter" => safe_identifier(receipt["maintenance_adapter"], "unknown")
        }.compact
        transaction["device_label"] = device_index[device_id]&.fetch("label", nil) || device_id
        transaction["reconciliation"] = reconciliation(transaction, device_index[device_id])
        transaction
      end.sort_by { |row| [row.fetch("finished_at", ""), row.fetch("receipt_id")] }.reverse
      rows.each_with_object({}) { |row, latest| latest[row.fetch("device_id")] ||= row }.values.first(MAX_TRANSACTIONS)
    end

    def reconciliation(transaction, device)
      lifecycle = transaction.fetch("execution_state")
      unless lifecycle == "complete"
        return {
          "state" => FAILURE_STATES.include?(lifecycle) ? "not_applicable" : "unknown",
          "reason" => FAILURE_STATES.include?(lifecycle) ? "execution did not complete successfully" : "execution state is not terminally understood"
        }
      end
      return {"state" => "unknown", "reason" => "device is absent from retained fleet evidence"} unless device

      finished_at = parsed_time(transaction["finished_at"])
      observed_at = parsed_time(device["observed_at"])
      unless finished_at && observed_at && observed_at > finished_at
        return {"state" => "awaiting_fresh_evidence", "reason" => "no newer device observation is retained"}
      end
      return reconciliation_result("attention", "newer evidence reports the device unreachable", device) unless device["reachable"]

      case transaction.fetch("action")
      when "maintenance"
        return reconciliation_result("unknown", "newer package evidence is not assessed", device) unless device.dig("updates", "assessed")
        return reconciliation_result("attention", "newer evidence still reports available updates", device) if device.dig("updates", "total").to_i.positive?

        reconciliation_result("verified", "newer reachable evidence reports no available updates", device)
      when "reboot"
        return reconciliation_result("attention", "newer evidence still reports reboot required", device) if device.dig("reboot", "required")

        reconciliation_result("verified", "newer reachable evidence no longer reports reboot required", device)
      else
        reconciliation_result("unknown", "operation has no A0 reconciliation rule", device)
      end
    end

    def reconciliation_result(state, reason, device)
      {"state" => state, "reason" => reason, "observed_at" => device["observed_at"]}.compact
    end

    def summarize(devices, transactions)
      states = transactions.each_with_object(Hash.new(0)) { |row, counts| counts[row.dig("reconciliation", "state")] += 1 }
      {
        "device_count" => devices.length,
        "transaction_count" => transactions.length,
        "verified_count" => states["verified"],
        "attention_count" => states["attention"],
        "awaiting_fresh_evidence_count" => states["awaiting_fresh_evidence"],
        "not_applicable_count" => states["not_applicable"],
        "unknown_count" => states["unknown"]
      }
    end

    def updates_assessed?(updates)
      freshness = updates["freshness"].to_s
      updates.key?("total") && !UNASSESSED_UPDATE_FRESHNESS.include?(freshness)
    end

    def observation_freshness(value)
      observed = parsed_time(value)
      now = @clock.call
      return "unknown" unless observed && now.respond_to?(:to_time)

      age = [now.to_time.utc - observed, 0].max
      return "fresh" if age <= FRESH_SECONDS
      return "aging" if age <= AGING_SECONDS

      "stale"
    end

    def parsed_time(value)
      return value.to_time.utc if value.respond_to?(:to_time)
      return nil if value.to_s.empty?

      Time.iso8601(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def normalized_time(value)
      parsed_time(value)&.iso8601
    end

    def iso8601(value)
      value.to_time.utc.iso8601
    end

    def nonnegative_integer(value)
      [Integer(value), 0].max
    rescue ArgumentError, TypeError
      0
    end

    def safe_identifier(value, fallback)
      text = value.to_s.strip
      text.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/) ? text : fallback
    end

    def safe_text(value, maximum_bytes, fallback: "")
      text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub(/[[:cntrl:]]+/, " ").gsub(/\s+/, " ").strip
      text = fallback if text.empty?
      text.bytesize <= maximum_bytes ? text : text.byteslice(0, maximum_bytes).to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").rstrip
    end

    def complete(data)
      {"ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => "none"}
    end

    def failed(reason)
      {
        "ok" => false,
        "lifecycle_state" => "failed",
        "reason" => reason,
        "data" => {"schema_version" => SCHEMA_VERSION},
        "mutation" => "none"
      }
    end
  end
end
