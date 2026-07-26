#!/usr/bin/env ruby
# frozen_string_literal: true

require "tmpdir"

require_relative "../lib/soul_core/chat_store"
require_relative "../lib/soul_core/conversation_creative_flow_store"
require_relative "../lib/soul_core/conversation_creative_workflow_service"

class PublicationPlannerFixture
  def cancel?(_message) = false
  def explicit_request?(_message) = false
end

class PublicationVisualFixture
  attr_reader :loop_executions, :final_executions

  def initialize
    @loop_executions = []
    @final_executions = []
  end

  def loop_preview(**_attributes)
    gate("RENDER_VISUAL_LOOP", "1", {
      "operation" => "encode_music_visual_static_presentation",
      "profile" => { "duration_seconds" => 12 },
      "external_publication" => false
    })
  end

  def loop_execute(**attributes)
    @loop_executions << attributes
    ok({ "visual" => base_visual.merge(
      "stage" => "loop_ready",
      "artifacts" => { "base" => { "sha256" => "a" * 64 }, "loop" => { "sha256" => "b" * 64 } }
    ) }, mutation: "music_visual_loop_created")
  end

  def final_preview(**_attributes)
    gate("RENDER_VISUAL_COMPANION", "2", {
      "operation" => "render_music_visual_companion",
      "output" => "H.264/AAC MP4",
      "external_publication" => false
    })
  end

  def final_execute(**attributes)
    @final_executions << attributes
    ok({ "visual" => base_visual.merge(
      "stage" => "preview_ready",
      "artifacts" => {
        "base" => { "sha256" => "a" * 64 },
        "loop" => { "sha256" => "b" * 64 },
        "preview" => { "sha256" => "c" * 64, "duration_seconds" => 180 }
      }
    ) }, mutation: "music_visual_preview_created")
  end

  private

  def base_visual
    {
      "visual_id" => "visual_3333333333333333",
      "stage" => "base_bound",
      "artifacts" => { "base" => { "sha256" => "a" * 64 } }
    }
  end

  def gate(confirmation, digit, scope)
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => {
        "confirmation_phrase" => confirmation,
        "expected_digest" => digit * 64,
        "preview_scope" => scope
      }
    }
  end

  def ok(data, mutation:)
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => data,
      "mutation" => mutation
    }
  end
end

class PublicationMusicDispositionFixture
  attr_reader :export_executions

  def initialize
    @exported = false
    @export_executions = []
  end

  def export_preview(**_attributes)
    if @exported
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "data" => { "export" => { "destination" => "/tmp/soul-music/Signal Loom" } }
      }
    else
      {
        "ok" => true,
        "lifecycle_state" => "blocked_for_human_review",
        "data" => {
          "confirmation_phrase" => "EXPORT_MUSIC_CANDIDATE",
          "expected_digest" => "4" * 64,
          "preview_scope" => {
            "destination" => "/tmp/soul-music/Signal Loom",
            "files" => %w[master.flac listening.mp3 song.json song-info.md],
            "overwrite" => false,
            "external_publication" => false
          }
        }
      }
    end
  end

  def export_execute(**attributes)
    @export_executions << attributes
    @exported = true
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => { "export" => { "destination" => "/tmp/soul-music/Signal Loom" } },
      "mutation" => "music_candidate_exported"
    }
  end
end

class PublicationPackageFixture
  attr_reader :executions

  def initialize = (@executions = [])

  def draft(**_attributes)
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "title" => "Signal Loom",
        "description" => "Progressive electronic rock | An intricate but coherent ascent.\n\nMusic, Visual, Composition created by Soul/"
      }
    }
  end

  def preview(**_attributes)
    {
      "ok" => true,
      "lifecycle_state" => "blocked_for_human_review",
      "data" => {
        "confirmation_phrase" => "EXPORT_YOUTUBE_PACKAGE",
        "expected_digest" => "5" * 64,
        "preview_scope" => {
          "destination" => "/tmp/soul-music/Signal Loom/youtube",
          "external_publication" => false
        }
      }
    }
  end

  def execute(**attributes)
    @executions << attributes
    {
      "ok" => true,
      "lifecycle_state" => "complete",
      "data" => {
        "package" => {
          "destination" => "/tmp/soul-music/Signal Loom/youtube",
          "external_publication" => false
        }
      },
      "mutation" => "youtube_upload_package_exported"
    }
  end
end

checks = {}

Dir.mktmpdir("soul-conversational-publication-") do |root|
  chat_store = SoulCore::ChatStore.new(root: root)
  chat_id = chat_store.create_chat(initial_title: "Publication fixture").fetch("id")
  flow_store = SoulCore::ConversationCreativeFlowStore.new(root: root)
  visual = PublicationVisualFixture.new
  disposition = PublicationMusicDispositionFixture.new
  publication = PublicationPackageFixture.new
  flow = {
    "schema_version" => SoulCore::ConversationCreativeFlowStore::SCHEMA,
    "flow_id" => "creative_aaaaaaaaaaaaaaaa",
    "chat_id" => chat_id,
    "kind" => "combined",
    "stage" => "bound",
    "lifecycle_state" => "blocked_for_human_review",
    "plan" => {},
    "missing_required" => [],
    "pending_action" => nil,
    "generated" => {
      "music" => {
        "project" => { "project_id" => "music_1111111111111111", "title" => "Signal Loom" },
        "candidate" => { "candidate_id" => "candidate_2222222222222222" }
      },
      "visual" => {
        "project" => { "project_id" => "visual_project_4444444444444444", "title" => "Signal Loom Cover" },
        "candidate" => { "candidate_id" => "visual_candidate_5555555555555555" }
      },
      "companion" => {
        "visual_id" => "visual_3333333333333333",
        "stage" => "base_bound",
        "artifacts" => { "base" => { "sha256" => "a" * 64 } }
      }
    },
    "created_at" => Time.now.utc.iso8601,
    "updated_at" => Time.now.utc.iso8601
  }
  flow_store.write(flow)
  service = SoulCore::ConversationCreativeWorkflowService.new(
    root: root,
    chat_store: chat_store,
    provider_client: Object.new,
    music_generation: Object.new,
    visual_studio: Object.new,
    core_orchestration: Object.new,
    music_disposition: disposition,
    music_visual_companion: visual,
    publication_package: publication,
    flow_store: flow_store,
    planner: PublicationPlannerFixture.new
  )

  checks["publication_discussion_is_not_invocation"] =
    service.plan(chat_id: chat_id, message: "Publication packages are useful later.", provider: nil).nil?

  presentation = service.plan(chat_id: chat_id, message: "Prepare a YouTube upload package.", provider: nil)
  presentation_action = presentation.dig("metadata", "actions", 0)
  checks["package_request_starts_with_exact_static_presentation"] =
    presentation["mode"] == "creative_companion_presentation_ready" &&
    presentation_action["action_id"] == "creative_companion_presentation" &&
    presentation["content"].include?("Motion synthesis: none") &&
    visual.loop_executions.empty?

  stale_presentation = service.execute(
    chat_id: chat_id,
    flow_id: presentation_action.fetch("flow_id"),
    action_id: presentation_action.fetch("action_id"),
    confirmation: presentation_action.fetch("confirmation_phrase"),
    expected_digest: "0" * 64
  )
  checks["stale_presentation_mutates_nothing"] = !stale_presentation["ok"] && visual.loop_executions.empty?

  presented = service.execute(
    chat_id: chat_id,
    flow_id: presentation_action.fetch("flow_id"),
    action_id: presentation_action.fetch("action_id"),
    confirmation: presentation_action.fetch("confirmation_phrase"),
    expected_digest: presentation_action.fetch("expected_digest")
  )
  checks["exact_presentation_returns_review_loop"] =
    presented["ok"] &&
    presented.dig("data", "flow", "stage") == "presented" &&
    presented.dig("data", "attachments", 0, "video_url").end_with?("/loop") &&
    visual.loop_executions.one?

  final = service.plan(chat_id: chat_id, message: "Continue the publication workflow.", provider: nil)
  final_action = final.dig("metadata", "actions", 0)
  checks["publication_continuation_prepares_full_render"] =
    final["mode"] == "creative_companion_final_ready" &&
    final_action["action_id"] == "creative_companion_final" &&
    visual.final_executions.empty?

  rendered = service.execute(
    chat_id: chat_id,
    flow_id: final_action.fetch("flow_id"),
    action_id: final_action.fetch("action_id"),
    confirmation: final_action.fetch("confirmation_phrase"),
    expected_digest: final_action.fetch("expected_digest")
  )
  checks["full_render_returns_authenticated_video"] =
    rendered["ok"] &&
    rendered.dig("data", "flow", "stage") == "rendered" &&
    rendered.dig("data", "attachments", 0, "video_url").end_with?("/preview") &&
    rendered.dig("data", "attachments", 0, "note").include?("not uploaded") &&
    visual.final_executions.one?

  export = service.plan(chat_id: chat_id, message: "Continue the publication workflow.", provider: nil)
  export_action = export.dig("metadata", "actions", 0)
  checks["unfinished_music_export_remains_separate_gate"] =
    export["mode"] == "creative_music_export_ready" &&
    export_action["action_id"] == "creative_music_export" &&
    export["content"].include?("separate exact step")

  exported = service.execute(
    chat_id: chat_id,
    flow_id: export_action.fetch("flow_id"),
    action_id: export_action.fetch("action_id"),
    confirmation: export_action.fetch("confirmation_phrase"),
    expected_digest: export_action.fetch("expected_digest")
  )
  checks["finished_song_export_keeps_publication_flow_resumable"] =
    exported["ok"] &&
    exported["lifecycle_state"] == "blocked_for_human_review" &&
    exported.dig("data", "flow", "stage") == "rendered" &&
    disposition.export_executions.one?

  package = service.plan(chat_id: chat_id, message: "Continue the publication workflow.", provider: nil)
  package_action = package.dig("metadata", "actions", 0)
  checks["package_preview_exposes_description_and_no_upload"] =
    package["mode"] == "creative_publication_ready" &&
    package_action["action_id"] == "creative_publication_package" &&
    package["content"].include?("Progressive electronic rock") &&
    package["content"].include?("Upload performed: no") &&
    publication.executions.empty?

  stale_package = service.execute(
    chat_id: chat_id,
    flow_id: package_action.fetch("flow_id"),
    action_id: package_action.fetch("action_id"),
    confirmation: package_action.fetch("confirmation_phrase"),
    expected_digest: "0" * 64
  )
  checks["stale_package_mutates_nothing"] = !stale_package["ok"] && publication.executions.empty?

  completed = service.execute(
    chat_id: chat_id,
    flow_id: package_action.fetch("flow_id"),
    action_id: package_action.fetch("action_id"),
    confirmation: package_action.fetch("confirmation_phrase"),
    expected_digest: package_action.fetch("expected_digest")
  )
  checks["exact_package_completes_locally_without_publication"] =
    completed["ok"] &&
    completed["lifecycle_state"] == "complete" &&
    completed.dig("data", "flow", "stage") == "packaged" &&
    completed.dig("data", "assistant_message", "content").include?("Nothing was uploaded or published") &&
    publication.executions.one?

  replay = service.execute(
    chat_id: chat_id,
    flow_id: package_action.fetch("flow_id"),
    action_id: package_action.fetch("action_id"),
    confirmation: package_action.fetch("confirmation_phrase"),
    expected_digest: package_action.fetch("expected_digest")
  )
  checks["package_action_is_idempotent"] =
    replay.dig("data", "idempotent_replay") == true && publication.executions.one?
end

failed = checks.reject { |_name, passed| passed }
puts checks.map { |name, passed| "#{passed ? 'PASS' : 'FAIL'} #{name}" }
abort("#{failed.length} conversational publication checks failed") unless failed.empty?
puts "PASS #{checks.length} conversational publication checks"
