#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"
require "time"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_creative_flow_store"
require_relative "../lib/soul_core/conversation_creative_workflow_service"
require_relative "../lib/soul_core/visual_motion_qualification_service"

class NativeMotionPlannerFixture
  def cancel?(_message) = false
  def explicit_request?(_message) = false
end

class NativeMotionCoreFixture
  def status
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => { "active_core_id" => "amd-free" }
    }
  end
end

class NativeMotionVisualFixture
  attr_reader :generation_executions, :revision_executions
  attr_accessor :review_disposition

  def initialize
    @generation_executions = []
    @revision_executions = []
    @review_disposition = nil
  end

  def native_motion_preview(project_id:, instruction:, seed:, duration_seconds:)
    gate(project_id, instruction, seed, duration_seconds, "motion_candidate_bbbbbbbbbbbbbbbb")
  end

  def native_motion_execute(**attributes)
    @generation_executions << attributes
    complete_motion(attributes, "text_to_video")
  end

  def native_motion_revision_preview(project_id:, source_motion_id:, instruction:, seed:, duration_seconds:)
    gate(project_id, instruction, seed, duration_seconds, "motion_candidate_cccccccccccccccc").tap do |result|
      result["data"]["source_motion_candidate_id"] = source_motion_id
      result["data"]["generation_kind"] = "text_to_video_revision"
    end
  end

  def native_motion_revision_execute(**attributes)
    @revision_executions << attributes
    complete_motion(attributes, "text_to_video_revision")
  end

  def inspect(project_id:)
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "project" => {
          "project_id" => project_id,
          "motions" => [
            {
              "motion_candidate_id" => "motion_candidate_bbbbbbbbbbbbbbbb",
              "duration_seconds" => 8.0,
              "review" => @review_disposition && {
                "disposition" => @review_disposition,
                "rating" => 3,
                "notes" => "Keep the silhouette stable."
              }
            }
          ]
        }
      }
    }
  end

  private

  def gate(project_id, instruction, seed, duration, motion_id)
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => {
        "project_id" => project_id,
        "motion_candidate_id" => motion_id,
        "instruction" => instruction,
        "seed" => seed,
        "profile_id" => "fastwan-8s",
        "generation_frames" => 193,
        "generation_fps" => 24,
        "frames" => 193,
        "fps" => 24,
        "delivery_method" => "native",
        "estimated_runtime_seconds" => 360,
        "duration_seconds" => duration,
        "confirmation_phrase" => "GENERATE_NATIVE_VIDEO",
        "expected_digest" => motion_id[-1] * 64
      }
    }
  end

  def complete_motion(attributes, kind)
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => {
        "motion" => {
          "project_id" => attributes.fetch(:project_id),
          "motion_candidate_id" => attributes.fetch(:motion_id),
          "generation_kind" => kind,
          "source_motion_candidate_id" => attributes[:source_motion_id],
          "instruction" => attributes.fetch(:instruction),
          "duration_seconds" => attributes.fetch(:duration_seconds).to_f,
          "fps" => 24,
          "elapsed_seconds" => 300.0,
          "created_at" => Time.now.utc.iso8601
        }
      },
      "mutation" => kind == "text_to_video_revision" ? "visual_native_motion_revision_generated" : "visual_native_motion_generated"
    }
  end
end

class QualificationVisualFixture
  def list(limit:)
    raise "unexpected limit" unless limit == 200
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => { "projects" => [{ "project_id" => "visual_project_aaaaaaaaaaaaaaaa" }] }
    }
  end

  def inspect(project_id:)
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "project" => {
          "project_id" => project_id,
          "title" => "Threshold Garden",
          "motions" => [
            motion("motion_candidate_1111111111111111", 4, 90, "keep", 4),
            motion("motion_candidate_2222222222222222", 8, 310, "revise", 3),
            motion("motion_candidate_3333333333333333", 12, 620, nil, nil)
          ]
        }
      }
    }
  end

  private

  def motion(id, duration, elapsed, disposition, rating)
    {
      "motion_candidate_id" => id,
      "generation_kind" => "text_to_video",
      "profile_id" => "fastwan-#{duration}s",
      "duration_seconds" => duration.to_f,
      "fps" => 24,
      "generation_fps" => duration == 12 ? 16 : 24,
      "delivery_method" => duration == 12 ? "optical_interpolation" : "native",
      "elapsed_seconds" => elapsed.to_f,
      "created_at" => "2026-07-26T00:00:0#{duration % 10}Z",
      "review" => disposition && {
        "disposition" => disposition,
        "rating" => rating,
        "notes" => "Human evidence",
        "reviewed_at" => "2026-07-26T01:00:00Z"
      }
    }
  end
end

checks = {}

Dir.mktmpdir("soul-conversational-native-motion-") do |root|
  chat_store = SoulCore::ChatStore.new(root: root)
  chat_id = chat_store.create_chat(initial_title: "Native motion fixture").fetch("id")
  flow_store = SoulCore::ConversationCreativeFlowStore.new(root: root)
  visual = NativeMotionVisualFixture.new
  flow_store.write(
    "schema_version" => SoulCore::ConversationCreativeFlowStore::SCHEMA,
    "flow_id" => "creative_aaaaaaaaaaaaaaaa",
    "chat_id" => chat_id,
    "kind" => "visual",
    "stage" => "reviewed",
    "lifecycle_state" => "blocked_for_human_review",
    "plan" => {},
    "missing_required" => [],
    "pending_action" => nil,
    "review_draft" => { "visual_disposition" => "keep" },
    "generated" => {
      "visual" => {
        "project" => { "project_id" => "visual_project_aaaaaaaaaaaaaaaa", "title" => "Threshold Garden" },
        "candidate" => { "candidate_id" => "visual_candidate_dddddddddddddddd" }
      }
    },
    "created_at" => Time.now.utc.iso8601,
    "updated_at" => Time.now.utc.iso8601
  )
  service = SoulCore::ConversationCreativeWorkflowService.new(
    root: root,
    chat_store: chat_store,
    provider_client: Object.new,
    music_generation: Object.new,
    visual_studio: visual,
    core_orchestration: NativeMotionCoreFixture.new,
    flow_store: flow_store,
    planner: NativeMotionPlannerFixture.new
  )

  checks["discussion_does_not_invoke_native_motion"] =
    service.plan(chat_id: chat_id, message: "Native video could be useful later.", provider: nil).nil?

  missing = service.plan(
    chat_id: chat_id,
    message: "Create a native scene: a locked camera watches violet fog cross a dark geometric chamber.",
    provider: nil
  )
  checks["missing_duration_waits_without_preview"] =
    missing["mode"] == "creative_native_motion_awaiting_input" &&
    missing["content"].include?("4-, 8-, or 12-second") &&
    visual.generation_executions.empty?

  preview = service.plan(chat_id: chat_id, message: "8 seconds", provider: nil)
  action = preview.dig("metadata", "actions", 0)
  checks["followup_completes_exact_core_aware_preview"] =
    preview["mode"] == "creative_native_motion_ready" &&
    action["action_id"] == "creative_native_motion" &&
    action.dig("core_requirement", "required_core_id") == "amd-free" &&
    preview["content"].include?("External publication: not included")

  stale = service.execute(
    chat_id: chat_id,
    flow_id: action.fetch("flow_id"),
    action_id: action.fetch("action_id"),
    confirmation: action.fetch("confirmation_phrase"),
    expected_digest: "0" * 64
  )
  checks["stale_chat_digest_mutates_nothing"] = !stale["ok"] && visual.generation_executions.empty?

  generated = service.execute(
    chat_id: chat_id,
    flow_id: action.fetch("flow_id"),
    action_id: action.fetch("action_id"),
    confirmation: action.fetch("confirmation_phrase"),
    expected_digest: action.fetch("expected_digest")
  )
  checks["exact_generation_returns_authenticated_candidate_video"] =
    generated["ok"] &&
    generated.dig("data", "flow", "stage") == "motion_generated" &&
    generated.dig("data", "attachments", 0, "video_url").end_with?("/motion_candidate_bbbbbbbbbbbbbbbb") &&
    generated.dig("data", "assistant_message", "content").include?("nothing was bound, exported, uploaded, or published") &&
    visual.generation_executions.one?

  blocked_revision = service.plan(
    chat_id: chat_id,
    message: "Revise the native scene so that the silhouette remains stable while the fog moves.",
    provider: nil
  )
  checks["revision_requires_stored_revise_review"] =
    blocked_revision["mode"] == "creative_native_motion_review_required" &&
    visual.revision_executions.empty?

  visual.review_disposition = "revise"
  revision = service.plan(
    chat_id: chat_id,
    message: "Revise the native scene so that the silhouette remains stable while only the violet fog crosses the chamber.",
    provider: nil
  )
  revision_action = revision.dig("metadata", "actions", 0)
  checks["reviewed_revision_preserves_duration_and_source"] =
    revision["mode"] == "creative_native_motion_ready" &&
    revision_action["action_id"] == "creative_native_motion" &&
    revision["content"].include?("8 seconds")

  revised = service.execute(
    chat_id: chat_id,
    flow_id: revision_action.fetch("flow_id"),
    action_id: revision_action.fetch("action_id"),
    confirmation: revision_action.fetch("confirmation_phrase"),
    expected_digest: revision_action.fetch("expected_digest")
  )
  checks["exact_revision_returns_linked_candidate"] =
    revised["ok"] &&
    revised.dig("data", "motion", "generation_kind") == "text_to_video_revision" &&
    revised.dig("data", "motion", "source_motion_candidate_id") == "motion_candidate_bbbbbbbbbbbbbbbb" &&
    visual.revision_executions.one?

  replay = service.execute(
    chat_id: chat_id,
    flow_id: revision_action.fetch("flow_id"),
    action_id: revision_action.fetch("action_id"),
    confirmation: revision_action.fetch("confirmation_phrase"),
    expected_digest: revision_action.fetch("expected_digest")
  )
  checks["completed_native_action_is_idempotent"] =
    replay.dig("data", "idempotent_replay") == true && visual.revision_executions.one?
end

qualification = SoulCore::VisualMotionQualificationService.new(visual_studio: QualificationVisualFixture.new).snapshot
checks["qualification_is_read_only_and_never_auto_approves"] =
  qualification["ok"] &&
  qualification["mutation"] == "none" &&
  qualification.dig("data", "qualification_authority") == "human" &&
  qualification.dig("data", "automatic_qualification") == false
checks["qualification_exposes_cost_review_and_duration_gaps"] =
  qualification.dig("data", "sample_count") == 3 &&
  qualification.dig("data", "reviewed_count") == 2 &&
  qualification.dig("data", "evidence_state") == "unreviewed_samples" &&
  qualification.dig("data", "samples", 0, "runtime_per_output_second").is_a?(Numeric)

root = File.expand_path("..", __dir__)
contract = File.read(File.join(root, "lib", "soul_core", "application_contract.rb"))
facade = File.read(File.join(root, "lib", "soul_core", "application_facade.rb"))
html = File.read(File.join(root, "assets", "dashboard", "index.html"))
javascript = File.read(File.join(root, "assets", "dashboard", "dashboard.js"))
checks["application_and_dashboard_expose_read_only_qualification"] =
  contract.include?('"visual.motion.qualification" => []') &&
  facade.include?('when "visual.motion.qualification" then domain(visual_motion_qualification.snapshot)') &&
  html.include?('id="motion-qualification-summary"') &&
  javascript.include?('callSoul("visual.motion.qualification")') &&
  !javascript.match?(/setInterval\s*\([^)]*refreshMotionQualification/)

failed = checks.reject { |_name, passed| passed }
puts checks.map { |name, passed| "#{passed ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} conversational native-motion checks failed") unless failed.empty?
puts "PASS #{checks.length} conversational native-motion and qualification checks"
