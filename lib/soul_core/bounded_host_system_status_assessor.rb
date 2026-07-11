# frozen_string_literal: true

require "json"
require_relative "conversation_evidence_contract"
require_relative "conversation_tool_catalog"
require_relative "host_system_status_collector"

module SoulCore
  class BoundedHostSystemStatusAssessor
    Contract = ConversationEvidenceContract

    class FixtureRunner
      def run(argv, timeout_seconds:)
        key = Array(argv).join(" ")
        stdout =
          case key
          when "uname -srmo"
            "Linux 6.15.9-arch1-1 x86_64 GNU/Linux\n"
          when "findmnt --json --bytes -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%"
            JSON.generate(
              {
                "filesystems" => [
                  {
                    "target" => "/",
                    "source" => "/dev/nvme0n1p2",
                    "fstype" => "btrfs",
                    "size" => 2_000_000_000_000,
                    "used" => 240_000_000_000,
                    "avail" => 1_760_000_000_000,
                    "use%" => "12%"
                  }
                ]
              }
            )
          when "lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,ROTA,TRAN"
            JSON.generate(
              {
                "blockdevices" => [
                  {
                    "name" => "nvme0n1",
                    "kname" => "nvme0n1",
                    "type" => "disk",
                    "size" => 2_000_000_000_000,
                    "model" => "Fixture NVMe",
                    "rota" => false,
                    "tran" => "nvme",
                    "children" => [
                      {
                        "name" => "nvme0n1p2",
                        "kname" => "nvme0n1p2",
                        "type" => "part",
                        "size" => 1_999_000_000_000,
                        "fstype" => "btrfs",
                        "mountpoints" => ["/"]
                      }
                    ]
                  }
                ]
              }
            )
          when "ip -j link show"
            JSON.generate(
              [
                {
                  "ifname" => "lo",
                  "operstate" => "UNKNOWN",
                  "mtu" => 65_536,
                  "link_type" => "loopback"
                },
                {
                  "ifname" => "enp5s0",
                  "operstate" => "UP",
                  "mtu" => 1500,
                  "link_type" => "ether"
                }
              ]
            )
          when "systemctl is-system-running"
            "running\n"
          when "systemctl --failed --no-legend --plain"
            ""
          else
            ""
          end

        status =
          if key.start_with?("df ")
            "failed"
          else
            "ok"
          end

        HostSystemStatusCollector::CommandResult.new(
          argv: Array(argv),
          stdout: stdout,
          stderr: "",
          exit_status: status == "ok" ? 0 : 1,
          status: status,
          elapsed_ms: 1.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      fixture_files = {
        "/etc/os-release" => <<~TEXT,
          NAME="CachyOS"
          PRETTY_NAME="CachyOS"
          ID=cachyos
        TEXT
        "/proc/uptime" => "90061.00 100.00\n",
        "/proc/loadavg" => "0.25 0.50 0.75 1/100 1234\n",
        "/proc/meminfo" => <<~TEXT,
          MemTotal:       33554432 kB
          MemAvailable:   25165824 kB
        TEXT
        "/proc/mdstat" => <<~TEXT
          Personalities :
          unused devices: <none>
        TEXT
      }

      fixture = HostSystemStatusCollector.new(
        runner: FixtureRunner.new,
        file_reader: ->(path) { fixture_files.fetch(path, "") },
        hostname_reader: -> { "fixture-host" },
        clock: -> { Time.at(0).utc }
      ).collect

      actual = HostSystemStatusCollector.new.collect
      tool = ConversationToolCatalog.new.find("host.system_status")
      evidence = Contract.build_structured(
        tool: tool,
        chat_id: "phase6-assessment",
        result: fixture
      ).to_h

      fixture_root = fixture.dig("collected", "filesystems").find do |filesystem|
        filesystem["target"] == "/"
      end

      fixture_ok =
        fixture["ok"] == true &&
        fixture_root["filesystem_type"] == "btrfs" &&
        fixture_root["used_percent"] == 12.0 &&
        fixture.dig("collected", "linux_mdraid", "active_array_count") == 0 &&
        fixture["claims"].any? { |claim| claim.include?("No active Linux MD RAID arrays") } &&
        fixture["not_collected"].include?("SMART device health")

      actual_shape_ok =
        actual["assessment"] == "host_system_status" &&
        actual["scope"] == HostSystemStatusCollector::SCOPE &&
        actual.dig("verification", "read_only") == true &&
        actual.dig("verification", "shell_interpolation_used") == false &&
        actual["collected"].is_a?(Hash) &&
        actual["claims"].is_a?(Array) &&
        actual["not_collected"].is_a?(Array)

      evidence_root = Array(evidence.dig("collected", "filesystems")).find do |filesystem|
        filesystem["target"] == "/"
      end

      evidence_ok =
        evidence["tool_id"] == "host.system_status" &&
        evidence["evidence_profile"] == "host_system_status" &&
        evidence_root.is_a?(Hash) &&
        evidence_root["source"] == "/dev/nvme0n1p2" &&
        evidence["claims"].any? do |claim|
          claim.include?("Filesystem /dev/nvme0n1p2:") &&
            claim.include?("mounted at /.")
        end

      blockers = []
      blockers << "Fixture parsing failed" unless fixture_ok
      blockers << "Actual collector shape failed" unless actual_shape_ok
      blockers << "Structured evidence conversion failed" unless evidence_ok
      blockers << "Host tool must remain read-only" unless tool&.risk_class == "read_only"
      blockers << "Host tool synthesis must remain disabled in Phase 6" unless tool&.synthesis_allowed == false

      {
        "ok" => blockers.empty?,
        "assessment" => "bounded_host_system_status",
        "milestone" => "conversational_soul",
        "phase" => 6,
        "status" => blockers.empty? ? "ready" : "blocked",
        "fixture" => fixture,
        "actual" => actual,
        "evidence" => evidence,
        "blockers" => blockers,
        "verification" => {
          "fixture_parsing_works" => fixture_ok,
          "actual_collector_shape_works" => actual_shape_ok,
          "structured_evidence_works" => evidence_ok,
          "read_only" => tool&.risk_class == "read_only",
          "model_synthesis_disabled" => tool&.synthesis_allowed == false,
          "btrfs_fixture_detected" => fixture_root["filesystem_type"] == "btrfs",
          "twelve_percent_fixture_detected" => fixture_root["used_percent"] == 12.0,
          "no_fake_raid_fixture" => fixture.dig("collected", "linux_mdraid", "active_array_count") == 0
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Bounded Host System Status Assessment"
      lines << "Milestone: #{report['milestone']}"
      lines << "Phase: #{report['phase']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines << ""
      lines << "Actual host claims"
      Array(report.dig("actual", "claims")).each do |claim|
        lines << "- #{claim}"
      end
      lines << ""
      lines << "Not collected"
      Array(report.dig("actual", "not_collected")).each do |item|
        lines << "- #{item}"
      end
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
