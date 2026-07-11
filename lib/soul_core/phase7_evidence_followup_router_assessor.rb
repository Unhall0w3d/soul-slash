# frozen_string_literal: true

require_relative "conversation_evidence_followup_router"

module SoulCore
  class Phase7EvidenceFollowupRouterAssessor
    def initialize(root: Dir.pwd)
      @root = File.expand_path(root)
    end

    def assess
      router = ConversationEvidenceFollowupRouter.new
      evidence = fixture_evidence

      disk_followup = router.route(
        message: "Which disks were you referring to?",
        evidence_records: evidence
      )
      files_followup = router.route(
        message: "Which files were flagged?",
        evidence_records: evidence
      )
      smart_followup = router.route(
        message: "What about SMART health?",
        evidence_records: evidence
      )
      skill_followup = router.route(
        message: "Tell me more about that skill catalog result.",
        evidence_records: evidence
      )
      unrelated = router.route(
        message: "Write a poem about the moon.",
        evidence_records: evidence
      )
      unrelated_followup = router.route(
        message: "What about dinner tonight?",
        evidence_records: evidence
      )
      rendered = router.render(selection: disk_followup)

      verification = {
        "plural_referential_followup_routes" => disk_followup.matched?,
        "relevant_evidence_record_is_selected" => disk_followup.record&.dig("tool_id") == "host.system_status",
        "claim_level_focus_is_generic" =>
          disk_followup.claims.all? { |claim| claim.include?("Block device") } &&
          disk_followup.claims.length == 2,
        "future_skill_evidence_routes_without_special_case" =>
          files_followup.record&.dig("tool_id") == "downloads.cleanup_plan" &&
          files_followup.claims.any? { |claim| claim.include?("Flagged") },
        "not_collected_focus_is_preserved" =>
          smart_followup.not_collected == ["SMART device health"],
        "explicit_profile_language_can_select_older_evidence" =>
          skill_followup.record&.dig("tool_id") == "assistant-skill-catalog",
        "unrelated_messages_do_not_hijack_recent_evidence" => !unrelated.matched?,
        "unmatched_followup_terms_do_not_hijack_recent_evidence" => !unrelated_followup.matched?,
        "deterministic_rendering_includes_evidence_identity" =>
          rendered.include?("Evidence ID: ev_host") &&
          rendered.include?("Block device nvme0n1"),
        "orchestrator_uses_followup_router" => file_contains?(
          "lib/soul_core/conversation_orchestrator.rb",
          "@followup_router.route"
        ),
        "runtime_uses_followup_router" => file_contains?(
          "lib/soul_core/conversation_runtime.rb",
          "@evidence_followup_router.render"
        ),
        "model_synthesis_is_not_part_of_followup_router" =>
          !File.read(File.join(@root, "lib/soul_core/conversation_evidence_followup_router.rb"), encoding: "UTF-8").match?(
            /provider|model_client|chat\(/
          )
      }

      blockers = verification.filter_map do |name, passed|
        name.tr("_", " ").capitalize unless passed
      end

      {
        "ok" => blockers.empty?,
        "assessment" => "phase7_evidence_followup_router",
        "milestone" => "conversational_soul",
        "phase" => 7,
        "status" => blockers.empty? ? "ready" : "blocked",
        "verification" => verification,
        "samples" => {
          "disk_followup" => disk_followup.to_h,
          "files_followup" => files_followup.to_h,
          "smart_followup" => smart_followup.to_h,
          "skill_followup" => skill_followup.to_h,
          "unrelated" => unrelated.to_h,
          "unrelated_followup" => unrelated_followup.to_h
        },
        "blockers" => blockers
      }
    end

    def render(report = assess)
      lines = [
        "Soul Phase 7 Evidence Follow-up Router Assessment",
        "Milestone: #{report['milestone']}",
        "Phase: #{report['phase']}",
        "Status: #{report['status']}",
        "",
        "Verification"
      ]

      report.fetch("verification").each do |name, passed|
        lines << "- #{name}: #{passed}"
      end

      lines << ""
      lines << "Blockers"
      blockers = Array(report["blockers"])
      if blockers.empty?
        lines << "- None"
      else
        blockers.each { |blocker| lines << "- #{blocker}" }
      end

      lines.join("\n")
    end

    private

    def file_contains?(relative_path, text)
      path = File.join(@root, relative_path)
      File.exist?(path) && File.read(path, encoding: "UTF-8").include?(text)
    end

    def fixture_evidence
      [
        {
          "evidence_id" => "ev_skills",
          "tool_id" => "assistant-skill-catalog",
          "label" => "Assistant skill catalog",
          "scope" => "Registered Soul assistant skills",
          "evidence_profile" => "skill_catalog",
          "status" => "ok",
          "claims" => [
            "Available skill: host.system_status.",
            "Available skill: downloads.cleanup_plan."
          ],
          "not_collected" => []
        },
        {
          "evidence_id" => "ev_downloads",
          "tool_id" => "downloads.cleanup_plan",
          "label" => "Downloads cleanup preview",
          "scope" => "Review-only cleanup candidates in Downloads",
          "evidence_profile" => "downloads_cleanup_preview",
          "status" => "ok",
          "claims" => [
            "Flagged report.iso as a cleanup candidate.",
            "Flagged old-build.zip as a cleanup candidate.",
            "No files were moved."
          ],
          "not_collected" => []
        },
        {
          "evidence_id" => "ev_host",
          "tool_id" => "host.system_status",
          "label" => "Host system status",
          "scope" => "Bounded read-only Linux host environment assessment",
          "evidence_profile" => "host_system_status",
          "status" => "ok",
          "claims" => [
            "Block device nvme0n1: disk, 1.82 TiB, Samsung SSD, nvme.",
            "Block device sdb: disk, 1.82 TiB, WDC external drive, usb.",
            "Filesystem /dev/nvme0n1p2: btrfs, mounted at / and /home.",
            "Memory: 10.00 GiB used of 64.00 GiB."
          ],
          "not_collected" => [
            "SMART device health",
            "storage-device temperatures"
          ],
          "collected" => {
            "block_devices" => [
              { "name" => "nvme0n1", "type" => "disk" },
              { "name" => "sdb", "type" => "disk" }
            ]
          }
        }
      ]
    end
  end
end
