# frozen_string_literal: true

require "time"

module SoulCore
  class HostStewardshipCapabilityRegistry
    CONFIGURED_FILE_STEWARD_IDS = %w[file_steward.inventory file_steward.operation file_steward.quarantine_restore].freeze
    CAPABILITIES = [
      {
        "id" => "host.presence",
        "label" => "Host Presence",
        "maturity" => "A1",
        "evidence" => "current bounded host and Core evidence plus persisted security and backup-automation status",
        "freshness" => "foreground_on_request",
        "privacy" => "owner_private_summary",
        "mutation" => "none",
        "approval" => "none",
        "required_commands" => %w[uname findmnt lsblk ip systemctl]
      },
      {
        "id" => "files.inspect",
        "label" => "Approved file inspection",
        "maturity" => "production",
        "evidence" => "configured read-only roots",
        "freshness" => "foreground_on_request",
        "privacy" => "owner_private_metadata",
        "mutation" => "none",
        "approval" => "none",
        "required_commands" => []
      },
      {
        "id" => "file_steward.inventory",
        "label" => "File Steward inventory",
        "maturity" => "A0",
        "evidence" => "configured mutation roots with public root IDs",
        "freshness" => "foreground_on_request",
        "privacy" => "owner_private_metadata",
        "mutation" => "none",
        "approval" => "none",
        "required_commands" => []
      },
      {
        "id" => "file_steward.operation",
        "label" => "File Steward rename, move, and copy",
        "maturity" => "A1",
        "evidence" => "digest-bound exact source and destination fingerprints",
        "freshness" => "revalidated_at_execution",
        "privacy" => "owner_private_receipt",
        "mutation" => "reversible_or_nondestructive_local_file_change",
        "approval" => "preview_digest_and_exact_confirmation",
        "required_commands" => []
      },
      {
        "id" => "file_steward.quarantine_restore",
        "label" => "File Steward quarantine and restore",
        "maturity" => "A2",
        "evidence" => "owner-private checksum-bound quarantine ledger",
        "freshness" => "revalidated_at_execution",
        "privacy" => "owner_private_receipt",
        "mutation" => "reversible_local_file_change",
        "approval" => "separate_preview_digest_and_exact_confirmation_per_transition",
        "required_commands" => []
      },
      {
        "id" => "file_steward.permanent_delete",
        "label" => "Permanent file deletion",
        "maturity" => "unavailable",
        "evidence" => "none",
        "freshness" => "not_implemented",
        "privacy" => "not_applicable",
        "mutation" => "destructive",
        "approval" => "unavailable",
        "required_commands" => [],
        "unavailable_reason" => "Permanent deletion is outside Host Stewardship A0-A2."
      },
      {
        "id" => "host.storage_enrichment",
        "label" => "Storage health enrichment",
        "maturity" => "planned",
        "evidence" => "SMART, NVMe, and Btrfs compression evidence",
        "freshness" => "foreground_on_request",
        "privacy" => "owner_private_summary",
        "mutation" => "none",
        "approval" => "none",
        "required_commands" => %w[smartctl],
        "optional_commands" => %w[nvme compsize]
      },
      {
        "id" => "host.io_diagnostic",
        "label" => "Storage I/O diagnostic",
        "maturity" => "planned",
        "evidence" => "bounded point-in-time process I/O sample",
        "freshness" => "foreground_on_request",
        "privacy" => "owner_private_summary",
        "mutation" => "none",
        "approval" => "none",
        "required_commands" => %w[iotop]
      }
    ].freeze

    def initialize(process_env: ENV, clock: -> { Time.now.utc })
      @process_env = process_env.to_h.transform_keys(&:to_s)
      @clock = clock
    end

    def snapshot(file_steward_configured: false)
      records = CAPABILITIES.map do |record|
        enriched = record.dup
        required = Array(record["required_commands"])
        optional = Array(record["optional_commands"])
        required_status = command_status(required)
        optional_status = command_status(optional)
        configured = CONFIGURED_FILE_STEWARD_IDS.include?(record["id"]) ? file_steward_configured : true
        available = record["maturity"] != "unavailable" && required_status.values.all? && configured
        enriched["dependencies"] = {
          "required" => required_status,
          "optional" => optional_status
        }
        enriched["available"] = available
        if !configured && CONFIGURED_FILE_STEWARD_IDS.include?(record["id"])
          enriched["unavailable_reason"] = "No owner-local SOUL_FILE_STEWARD_ROOTS are configured."
        elsif required_status.value?(false)
          enriched["unavailable_reason"] = "Required local command is unavailable: #{required_status.select { |_key, value| !value }.keys.join(', ')}."
        end
        enriched
      end

      complete({
        "schema_version" => "soul.host-stewardship.capabilities.v1",
        "records" => records,
        "count" => records.length,
        "available_count" => records.count { |record| record["available"] },
        "background_behavior" => false,
        "permanent_delete_available" => false
      })
    end

    private

    def command_status(commands)
      search = @process_env.fetch("PATH", ENV.fetch("PATH", "")).split(File::PATH_SEPARATOR)
      commands.each_with_object({}) do |command, status|
        status[command] = search.any? { |directory| File.executable?(File.join(directory, command)) }
      end
    end

    def complete(data)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "message" => "Host Stewardship capabilities inspected.",
        "data" => data,
        "mutation" => "none",
        "retrieved_at" => @clock.call.iso8601(6)
      }
    end
  end
end
