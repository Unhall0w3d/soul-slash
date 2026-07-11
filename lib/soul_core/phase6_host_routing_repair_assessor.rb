# frozen_string_literal: true

require "json"
require_relative "conversation_grounding_policy"
require_relative "conversation_tool_catalog"
require_relative "host_system_status_collector"

module SoulCore
  class Phase6HostRoutingRepairAssessor
    class FixtureRunner
      def run(argv, timeout_seconds:)
        key = Array(argv).join(" ")
        stdout =
          case key
          when "uname -srmo"
            "Linux 7.1.3-test x86_64 GNU/Linux\n"
          when "findmnt --json --bytes -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%"
            JSON.generate(
              {
                "filesystems" => [
                  {
                    "target" => "/",
                    "source" => "/dev/nvme0n1p2[/@]",
                    "fstype" => "btrfs",
                    "size" => 2_000_000_000_000,
                    "used" => 240_000_000_000,
                    "avail" => 1_760_000_000_000,
                    "use%" => "12%"
                  },
                  {
                    "target" => "/home",
                    "source" => "/dev/nvme0n1p2[/@home]",
                    "fstype" => "btrfs",
                    "size" => 2_000_000_000_000,
                    "used" => 240_000_000_000,
                    "avail" => 1_760_000_000_000,
                    "use%" => "12%"
                  },
                  {
                    "target" => "/run/user/1000/doc",
                    "source" => "portal",
                    "fstype" => "fuse.portal"
                  },
                  {
                    "target" => "/proc/sys/fs/binfmt_misc",
                    "source" => "binfmt_misc",
                    "fstype" => "binfmt_misc"
                  }
                ]
              }
            )
          when "lsblk --json --bytes -o NAME,KNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,ROTA,TRAN"
            JSON.generate(
              {
                "blockdevices" => [
                  {
                    "name" => "zram0",
                    "kname" => "zram0",
                    "type" => "disk",
                    "size" => 67_000_000_000,
                    "rota" => false
                  },
                  {
                    "name" => "nvme0n1",
                    "kname" => "nvme0n1",
                    "type" => "disk",
                    "size" => 2_000_000_000_000,
                    "model" => "Fixture NVMe",
                    "rota" => false,
                    "tran" => "nvme"
                  }
                ]
              }
            )
          when "ip -j link show"
            "[]"
          when "systemctl is-system-running"
            "running\n"
          when "systemctl --failed --no-legend --plain"
            ""
          else
            ""
          end

        HostSystemStatusCollector::CommandResult.new(
          argv: Array(argv),
          stdout: stdout,
          stderr: "",
          exit_status: 0,
          status: "ok",
          elapsed_ms: 1.0
        )
      end
    end

    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      catalog = ConversationToolCatalog.new
      grounding = ConversationGroundingPolicy.new

      direct_ids = catalog.match(
        "what filesystems and disks do i have?"
      ).map(&:id)

      followup = grounding.followup?(
        "which disks were you referring to?"
      )

      evidence = {
        "evidence_id" => "ev_fixture",
        "tool_id" => "host.system_status",
        "label" => "Host system status",
        "scope" => "Bounded read-only Linux host environment assessment",
        "evidence_profile" => "host_system_status",
        "status" => "ok",
        "claims" => [
          "Hostname: fixture-host.",
          "Memory: 8 GiB used of 64 GiB.",
          "Filesystem /dev/nvme0n1p2: btrfs, 1.82 TiB total, 12.0% used; mounted at /, /home.",
          "Block device nvme0n1: disk, 1.82 TiB, Fixture NVMe, nvme.",
          "Network interface eno1: state UP, MTU 1500."
        ],
        "not_collected" => [
          "SMART device health",
          "firewall policy"
        ]
      }

      focused = grounding.render_followup(
        message: "which disks were you referring to?",
        evidence_records: [evidence],
        heading: "Focused details"
      )

      fixture_files = {
        "/etc/os-release" => "NAME=CachyOS\nPRETTY_NAME=CachyOS\n",
        "/proc/uptime" => "3600.00 10.00\n",
        "/proc/loadavg" => "0.10 0.20 0.30 1/100 123\n",
        "/proc/meminfo" => "MemTotal: 65536000 kB\nMemAvailable: 57344000 kB\n",
        "/proc/mdstat" => "Personalities :\nunused devices: <none>\n"
      }

      collected = HostSystemStatusCollector.new(
        runner: FixtureRunner.new,
        file_reader: ->(path) { fixture_files.fetch(path, "") },
        hostname_reader: -> { "fixture-host" },
        clock: -> { Time.at(0).utc }
      ).collect

      claims = collected["claims"]

      routing_ok = direct_ids == ["host.system_status"]
      followup_ok = followup
      focused_ok =
        focused.include?("Filesystem /dev/nvme0n1p2") &&
        focused.include?("Block device nvme0n1") &&
        !focused.include?("Memory:") &&
        !focused.include?("Network interface")
      filtered_ok =
        claims.none? { |claim| claim.match?(/fuse\.portal|binfmt_misc|zram0/i) }
      grouped_ok =
        claims.count { |claim| claim.start_with?("Filesystem /dev/nvme0n1p2:") } == 1 &&
        claims.any? { |claim| claim.include?("mounted at /, /home") }

      blockers = []
      blockers << "Compound plural storage request did not route to host.system_status" unless routing_ok
      blockers << "Plural referential follow-up was not recognized" unless followup_ok
      blockers << "Storage follow-up was not focused" unless focused_ok
      blockers << "Pseudo storage claims were not filtered" unless filtered_ok
      blockers << "Btrfs subvolume claims were not grouped" unless grouped_ok

      {
        "ok" => blockers.empty?,
        "assessment" => "phase6_host_routing_repair",
        "milestone" => "conversational_soul",
        "phase" => 6,
        "status" => blockers.empty? ? "ready" : "blocked",
        "direct_tool_ids" => direct_ids,
        "focused_rendering" => focused,
        "fixture_claims" => claims,
        "blockers" => blockers,
        "verification" => {
          "compound_plural_storage_route_works" => routing_ok,
          "plural_referential_followup_works" => followup_ok,
          "focused_storage_followup_works" => focused_ok,
          "pseudo_filesystems_are_filtered" => filtered_ok,
          "zram_is_not_presented_as_a_disk" => filtered_ok,
          "btrfs_subvolume_claims_are_grouped" => grouped_ok
        }
      }
    end

    def render(report)
      lines = []
      lines << "Soul Phase 6 Host Routing Repair Assessment"
      lines << "Milestone: #{report['milestone']}"
      lines << "Phase: #{report['phase']}"
      lines << "Status: #{report['status']}"
      lines << ""
      lines << "Verification"
      report.fetch("verification").each do |key, value|
        lines << "- #{key}: #{value}"
      end
      lines << ""
      lines << "Blockers"
      report.fetch("blockers").empty? ? lines << "- None" : report.fetch("blockers").each { |blocker| lines << "- #{blocker}" }
      lines.join("\n")
    end
  end
end
