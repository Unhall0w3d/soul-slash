# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"
require_relative "conversation_creative_flow_store"
require_relative "conversation_creative_planner"
require_relative "conversation_creative_review_planner"
require_relative "conversation_visual_revision_planner"
require_relative "music_revision_draft_service"

module SoulCore
  class ConversationCreativeWorkflowService
    EXECUTE_CONFIRMATION = "START_CREATIVE_WORKFLOW"

    def initialize(root:, chat_store:, provider_client:, music_generation:, visual_studio:, core_orchestration:, music_disposition: nil, flow_store: nil, planner: nil, review_planner: nil, revision_drafter: nil, visual_revision_drafter: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @chat_store = chat_store
      @music_generation = music_generation
      @music_disposition = music_disposition
      @visual_studio = visual_studio
      @core_orchestration = core_orchestration
      @flow_store = flow_store || ConversationCreativeFlowStore.new(root: @root, clock: clock)
      @planner = planner || ConversationCreativePlanner.new(provider_client: provider_client)
      @review_planner = review_planner || ConversationCreativeReviewPlanner.new(provider_client: provider_client)
      @revision_drafter = revision_drafter || MusicRevisionDraftService.new(provider_client: provider_client)
      @visual_revision_drafter = visual_revision_drafter || ConversationVisualRevisionPlanner.new(provider_client: provider_client)
      @clock = clock
    end

    def candidate_message?(chat_id:, message:)
      @planner.cancel?(message) || @planner.explicit_request?(message) || !@flow_store.active(chat_id).nil?
    end

    def plan(chat_id:, message:, provider:, progress: nil)
      if @planner.cancel?(message)
        canceled = @flow_store.cancel(chat_id)
        return nil unless canceled
        return result("Creative workflow canceled. No generation, binding, export, or Core transition was started.", "creative_canceled", canceled)
      end

      prior = @flow_store.active(chat_id)
      return nil unless prior || @planner.explicit_request?(message)
      if prior && prior["stage"] == "generated"
        binding = plan_companion_binding(prior, message)
        return binding if binding
        return plan_review(prior, message, provider, progress)
      end
      if prior && prior["stage"] == "reviewed"
        followup = plan_music_post_review(prior, message, provider, progress)
        return followup if followup
        followup = plan_visual_revision(prior, message, provider, progress)
        return followup if followup
        followup = plan_companion_binding(prior, message)
        return followup if followup
        return nil unless @planner.explicit_request?(message)

        supersede(prior)
        prior = nil
      end
      if prior && prior["stage"] == "bound"
        return nil unless @planner.explicit_request?(message)
        supersede(prior)
        prior = nil
      end
      progress&.call({ "state" => "planning", "summary" => "Shaping the creative brief without inventing required choices." })
      messages = @chat_store.messages(chat_id, limit: 12, scan_limit: 10_000)
      messages << { "role" => "user", "content" => message.to_s } unless messages.last&.dig("content") == message.to_s
      drafted = @planner.draft(provider: provider, chat_id: chat_id, messages: messages, prior: prior)
      return failure_result(drafted.fetch("reason"), prior) unless drafted.fetch("ok")
      plan = drafted.fetch("plan")
      return nil unless plan.fetch("related")

      flow = prior || new_flow(chat_id, plan.fetch("kind"))
      flow["kind"] = plan.fetch("kind")
      flow["plan"] = plan
      missing = @planner.missing_required(plan)
      if missing.any?
        flow["lifecycle_state"] = "awaiting_input"
        flow["stage"] = "brief"
        flow["missing_required"] = missing
        flow["pending_action"] = nil
        @flow_store.write(flow)
        question = plan["next_question"].to_s.strip
        question = "I still need your #{missing.first}." if question.empty?
        return result(render_brief(flow, question: question), "creative_awaiting_input", flow)
      end

      validate_ready_plan!(plan)
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "ready"
      flow["missing_required"] = []
      flow["pending_action"] = build_action(flow)
      @flow_store.write(flow)
      result(render_brief(flow), "creative_ready", flow, actions: [flow.fetch("pending_action")])
    rescue ArgumentError => error
      failure_result(error.message, prior)
    rescue StandardError => error
      failure_result("creative workflow planning failed safely: #{error.class}", prior)
    end

    def execute(chat_id:, flow_id:, action_id: nil, confirmation:, expected_digest:, progress: nil)
      flow = @flow_store.read(flow_id: flow_id, chat_id: chat_id)
      return domain("awaiting_input", false, "creative workflow was not found") unless flow
      if flow["pending_action"].nil? && flow["last_action_id"] == action_id.to_s && flow["result_message_id"]
        message = @chat_store.message(chat_id, flow.fetch("result_message_id"))
        return domain(flow.fetch("lifecycle_state"), true, "creative workflow action already completed", data: { "flow" => public_flow(flow), "assistant_message" => message, "idempotent_replay" => true })
      end
      if flow["stage"] == "generated" && flow["result_message_id"] && flow["pending_action"].nil?
        message = @chat_store.message(chat_id, flow.fetch("result_message_id"))
        return domain("blocked_for_human_review", true, "creative workflow result already exists", data: { "flow" => public_flow(flow), "assistant_message" => message, "idempotent_replay" => true })
      end
      action = flow["pending_action"]
      return domain("blocked_for_human_review", false, "creative workflow has no executable action") unless action
      return domain("blocked_for_human_review", false, "exact creative workflow confirmation did not match") unless confirmation == EXECUTE_CONFIRMATION
      return domain("blocked_for_human_review", false, "creative workflow changed; review it again") unless secure_compare(expected_digest, action.fetch("expected_digest")) && secure_compare(expected_digest, action_digest(flow))
      return domain("blocked_for_human_review", false, "creative workflow action changed; review it again") unless action_id.to_s.empty? || action_id.to_s == action.fetch("action_id")

      return execute_review(flow) if action.fetch("action_id") == "creative_review"
      return execute_music_revision(flow, progress) if action.fetch("action_id") == "creative_music_revision"
      return execute_visual_revision(flow, progress) if action.fetch("action_id") == "creative_visual_revision"
      return execute_companion_binding(flow) if action.fetch("action_id") == "creative_companion_bind"
      return execute_music_disposition(flow) if %w[creative_music_export creative_music_reject].include?(action.fetch("action_id"))

      progress&.call({ "stage" => "core", "message" => "Verifying the exact creative Core transition." })
      core = ensure_creative_core(flow)
      return append_terminal(flow, core, "Core transition did not complete; no creative generation was started") unless core.fetch("ok")

      attachments = []
      generated = {}
      if new_music?(flow)
        progress&.call({ "stage" => "music_project", "message" => "Creating the reviewed music brief." })
        music = generate_music(flow, progress)
        return append_terminal(flow, music, "Music generation stopped safely", attachments: attachments, generated: generated) unless music.fetch("ok")
        generated["music"] = music.fetch("data")
        attachments << music_attachment(music.fetch("data"))
      elsif needs_music?(flow)
        resolved = resolve_existing_music(flow.dig("plan", "existing_music_title"))
        return append_terminal(flow, resolved, "The existing music source could not be resolved", attachments: attachments, generated: generated) unless resolved.fetch("ok")
        generated["music"] = resolved.fetch("data")
        attachments << music_attachment(resolved.fetch("data"))
      end

      if new_visual?(flow)
        progress&.call({ "stage" => "visual_project", "message" => "Creating the reviewed visual brief." })
        visual = generate_visual(flow, progress)
        return append_terminal(flow, visual, "Visual generation stopped safely", attachments: attachments, generated: generated) unless visual.fetch("ok")
        generated["visual"] = visual.fetch("data")
        attachments << visual_attachment(visual.fetch("data"))
      elsif needs_visual?(flow)
        resolved = resolve_existing_visual(flow.dig("plan", "existing_visual_title"))
        return append_terminal(flow, resolved, "The existing visual source could not be resolved", attachments: attachments, generated: generated) unless resolved.fetch("ok")
        generated["visual"] = resolved.fetch("data")
        attachments << visual_attachment(resolved.fetch("data"))
      end

      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "generated"
      flow["pending_action"] = nil
      flow["generated"] = generated
      content = generated_content(flow, generated)
      message = append_assistant(chat_id, content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_generate"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "creative candidates generated; human review required", data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments }, mutation: "creative_candidates_generated")
    rescue ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "creative workflow execution failed safely: #{error.class}")
    end

    private

    def plan_music_post_review(flow, message, provider, progress)
      revision = plan_music_revision(flow, message, provider, progress)
      return revision if revision
      return nil unless flow.dig("generated", "music") && !flow.dig("generated", "music", "existing")

      disposition = flow.dig("review_draft", "music_disposition")
      return plan_music_export(flow) if disposition == "keep" && explicit_export_request?(message)
      return plan_music_rejection(flow) if disposition == "reject" && explicit_rejection_request?(message)
      return result("That candidate is recorded as kept, so rejection is unavailable until its review changes.", "creative_music_disposition_mismatch", flow) if disposition == "keep" && explicit_rejection_request?(message)
      return result("That candidate is recorded as rejected, so export is unavailable until its review changes.", "creative_music_disposition_mismatch", flow) if disposition == "reject" && explicit_export_request?(message)

      nil
    end

    def plan_companion_binding(flow, message)
      return nil unless companion_binding_eligible?(flow) && explicit_binding_request?(message)

      music = flow.dig("generated", "music")
      visual = flow.dig("generated", "visual")
      preview = @visual_studio.promotion_preview(
        project_id: visual.dig("project", "project_id"), candidate_id: visual.dig("candidate", "candidate_id"),
        music_project_id: music.dig("project", "project_id"), music_candidate_id: music.dig("candidate", "candidate_id")
      )
      return failure_result(preview.fetch("reason", "companion binding preview did not complete"), flow) unless preview.fetch("ok")
      if preview.fetch("lifecycle_state") == "complete"
        flow["generated"]["companion"] = preview.dig("data", "visual")
        flow["stage"] = "bound"
        flow["lifecycle_state"] = "blocked_for_human_review"
        flow["pending_action"] = nil
        @flow_store.write(flow)
        return result("That exact image is already bound to the selected song. No duplicate copy was created; static presentation remains a separate step.", "creative_companion_bound", flow)
      end

      gate = preview.fetch("data")
      flow["companion_action"] = {
        "confirmation_phrase" => gate.fetch("confirmation_phrase"), "downstream_digest" => gate.fetch("expected_digest"),
        "preview_scope" => gate.fetch("preview_scope")
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_companion_binding_action(flow)
      @flow_store.write(flow)
      result(render_companion_binding(flow), "creative_companion_binding_ready", flow, actions: [flow.fetch("pending_action")])
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("companion binding planning failed safely: #{error.class}", flow)
    end

    def companion_binding_eligible?(flow)
      music = flow.dig("generated", "music")
      visual = flow.dig("generated", "visual")
      return false unless music && visual
      music_kept = music["existing"] || flow.dig("review_draft", "music_disposition") == "keep"
      visual_kept = visual["existing"] || flow.dig("review_draft", "visual_disposition") == "keep"
      music_kept && visual_kept
    end

    def explicit_binding_request?(message)
      text = message.to_s.strip
      text.match?(/\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:bind|attach|connect|link|pair|use)\b.*\b(?:them|together|music|song|track|visual|image|picture|art|artwork|companion|candidate)\b/i)
    end

    def build_companion_binding_action(flow)
      { "action_id" => "creative_companion_bind", "operation" => "chats.creative.execute", "label" => "Bind exact reviewed visual to song",
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => "copy_reviewed_visual_into_music_lineage" }
    end

    def render_companion_binding(flow)
      scope = flow.dig("companion_action", "preview_scope")
      [
        "The reviewed song and image are ready for one exact lineage binding.", "",
        "Music: #{flow.dig('generated', 'music', 'project', 'title')}",
        "Music candidate: #{scope['candidate_id']}",
        "Visual: #{flow.dig('generated', 'visual', 'project', 'title')}",
        "Visual candidate: #{scope['source_visual_candidate_id']}",
        "Bound visual identity: #{scope['visual_id']}",
        "External publication: #{scope['external_publication'] ? 'included' : 'not included'}", "",
        "Clicking the action authorizes only this exact source-preserving copy into the music candidate's visual lineage. It does not render or export a video."
      ].join("\n")
    end

    def execute_companion_binding(flow)
      stored = flow.fetch("companion_action")
      music = flow.dig("generated", "music")
      visual = flow.dig("generated", "visual")
      outcome = @visual_studio.promotion_execute(
        project_id: visual.dig("project", "project_id"), candidate_id: visual.dig("candidate", "candidate_id"),
        music_project_id: music.dig("project", "project_id"), music_candidate_id: music.dig("candidate", "candidate_id"),
        confirmation: stored.fetch("confirmation_phrase"), expected_digest: stored.fetch("downstream_digest")
      )
      return outcome unless outcome.fetch("ok")

      flow["generated"]["companion"] = outcome.dig("data", "visual")
      flow.delete("companion_action")
      flow["pending_action"] = nil
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "bound"
      attachments = current_attachments(flow)
      message = append_assistant(flow.fetch("chat_id"), "The exact reviewed image is now bound to the song's visual lineage. No video was rendered or exported; static presentation remains a separate reviewed step.", flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_companion_bind"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "reviewed visual bound to music candidate; presentation review remains",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, "companion" => outcome.dig("data", "visual") }, mutation: "music_visual_bound")
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "companion binding failed safely: #{error.class}")
    end

    def plan_music_export(flow)
      return failure_result("music disposition service is unavailable", flow) unless @music_disposition
      music = flow.dig("generated", "music")
      preview = @music_disposition.export_preview(project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"))
      if preview.fetch("ok") && preview.fetch("lifecycle_state") == "complete"
        flow["lifecycle_state"] = "complete"
        flow["stage"] = "exported"
        @flow_store.write(flow)
        destination = preview.dig("data", "export", "destination")
        return result("The kept song is already exported#{destination ? " to #{destination}" : ''}. No duplicate files were created.", "creative_music_export_complete", flow)
      end
      return failure_result(preview.fetch("reason", "music export preview did not complete"), flow) unless preview.fetch("ok")
      prepare_music_disposition_action(flow, "export", preview.fetch("data"))
    end

    def plan_music_rejection(flow)
      return failure_result("music disposition service is unavailable", flow) unless @music_disposition
      music = flow.dig("generated", "music")
      preview = @music_disposition.reject_preview(project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"))
      return failure_result(preview.fetch("reason", "music rejection preview did not complete"), flow) unless preview.fetch("ok")
      prepare_music_disposition_action(flow, "reject", preview.fetch("data"))
    end

    def prepare_music_disposition_action(flow, kind, preview)
      flow["disposition_action"] = {
        "kind" => kind, "confirmation_phrase" => preview.fetch("confirmation_phrase"),
        "downstream_digest" => preview.fetch("expected_digest"), "preview_scope" => preview.fetch("preview_scope")
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_music_disposition_action(flow, kind)
      @flow_store.write(flow)
      result(render_music_disposition(flow), "creative_music_#{kind}_ready", flow, actions: [flow.fetch("pending_action")])
    end

    def build_music_disposition_action(flow, kind)
      { "action_id" => "creative_music_#{kind}", "operation" => "chats.creative.execute",
        "label" => kind == "export" ? "Export exact finished song" : "Permanently remove rejected candidate",
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => kind == "export" ? "write_finished_song_export" : "permanent_candidate_delete" }
    end

    def render_music_disposition(flow)
      action = flow.fetch("disposition_action")
      scope = action.fetch("preview_scope")
      if action.fetch("kind") == "export"
        ["The kept candidate is ready for its exact local export gate.", "Destination: #{scope['destination']}",
          "Files: #{Array(scope['files']).join(', ')}", "Overwrite: #{scope['overwrite'] ? 'allowed' : 'forbidden'}",
          "External publication: #{scope['external_publication'] ? 'included' : 'not included'}", "",
          "Clicking the action authorizes only this exact finished-song export."].join("\n")
      else
        ["The rejected candidate is ready for its separate permanent-deletion gate.",
          "Deletes: #{Array(scope['deletes']).join(', ')}", "Retains: #{Array(scope['retains']).join(', ')}",
          "Descendant candidates: #{Array(scope['descendant_candidate_ids']).join(', ').then { |value| value.empty? ? 'none' : value }}",
          "External export deleted: #{scope['external_export_deleted'] ? 'yes' : 'no'}", "",
          "Clicking the action authorizes only this exact candidate-owned deletion."].join("\n")
      end
    end

    def execute_music_disposition(flow)
      return domain("blocked_for_human_review", false, "music disposition service is unavailable") unless @music_disposition
      stored = flow.fetch("disposition_action")
      music = flow.dig("generated", "music")
      attributes = {
        project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"),
        confirmation: stored.fetch("confirmation_phrase"), expected_digest: stored.fetch("downstream_digest")
      }
      outcome = if stored.fetch("kind") == "export"
        @music_disposition.export_execute(**attributes)
      else
        @music_disposition.reject_execute(**attributes)
      end
      return outcome unless outcome.fetch("ok")

      kind = stored.fetch("kind")
      flow.delete("disposition_action")
      flow["pending_action"] = nil
      flow["lifecycle_state"] = "complete"
      flow["stage"] = kind == "export" ? "exported" : "rejected"
      flow["generated"].delete("music") if kind == "reject"
      attachments = kind == "export" ? [music_attachment(music)] : []
      content = if kind == "export"
        "The kept song is exported locally to #{outcome.dig('data', 'export', 'destination')}. Nothing was uploaded or published."
      else
        "The rejected music candidate and its owned audio, input, analysis, and current review were deleted. Its small rejection receipt remains."
      end
      message = append_assistant(flow.fetch("chat_id"), content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_music_#{kind}"
      @flow_store.write(flow)
      domain("complete", true, "music #{kind} completed", data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, kind => outcome.fetch("data") }, mutation: outcome.fetch("mutation", "none"))
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "music disposition execution failed safely: #{error.class}")
    end

    def explicit_export_request?(message)
      message.to_s.strip.match?(/\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:export|finish|finalize|save)\b.*\b(?:song|track|candidate|music|it)\b/i)
    end

    def explicit_rejection_request?(message)
      message.to_s.strip.match?(/\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:delete|discard|purge|reject|remove)\b.*\b(?:song|track|candidate|music|it)\b/i)
    end

    def plan_music_revision(flow, message, provider, progress)
      return nil unless music_revision_eligible?(flow) && explicit_music_revision_request?(flow, message)

      progress&.call({ "state" => "planning", "summary" => "Translating the recorded review into one bounded music revision." })
      music = flow.dig("generated", "music")
      inspected = @music_generation.inspect_project(project_id: music.dig("project", "project_id"))
      return failure_result(inspected.fetch("reason", "music project could not be inspected"), flow) unless inspected.fetch("ok")
      candidate = Array(inspected.dig("data", "generations")).find { |item| item["candidate_id"] == music.dig("candidate", "candidate_id") }
      return failure_result("the reviewed music candidate no longer exists", flow) unless candidate

      drafted = @revision_drafter.draft(
        project: inspected.dig("data", "project"), candidate: candidate,
        analysis: candidate["analysis"], provider: provider
      )
      return failure_result(drafted.fetch("reason", "music revision drafting did not complete"), flow) unless drafted.fetch("ok")

      data = drafted.fetch("data")
      flow["revision_draft"] = {
        "source_candidate_id" => candidate.fetch("candidate_id"),
        "revision" => data.fetch("revision"),
        "rationale" => data.fetch("rationale"),
        "changes" => data.fetch("changes"),
        "packet_digest" => data["packet_digest"]
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_music_revision_action(flow)
      @flow_store.write(flow)
      result(render_music_revision(flow), "creative_music_revision_ready", flow, actions: [flow.fetch("pending_action")])
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("music revision planning failed safely: #{error.class}", flow)
    end

    def music_revision_eligible?(flow)
      flow.dig("review_draft", "music_disposition") == "revise" &&
        flow.dig("generated", "music") && !flow.dig("generated", "music", "existing")
    end

    def explicit_revision_request?(message)
      text = message.to_s.strip
      text.match?(/\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:draft|edit|generate|make|produce|retry|revise|start|try)\b.*\b(?:revision|revised|candidate|song|track|visual|image|picture|artwork|it|again)\b/i) ||
        text.match?(/\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?let(?:'s| us)\s+(?:revise|retry|try\s+again|generate\s+(?:the\s+)?revision)\b/i)
    end

    def explicit_music_revision_request?(flow, message)
      return false unless explicit_revision_request?(message)
      text = message.to_s
      return true if text.match?(/\b(?:music|song|track|audio)\b/i)
      !visual_revision_eligible?(flow)
    end

    def build_music_revision_action(flow)
      { "action_id" => "creative_music_revision", "operation" => "chats.creative.execute", "label" => "Generate exact revised candidate",
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => "bounded_music_revision_generation" }
    end

    def render_music_revision(flow)
      draft = flow.fetch("revision_draft")
      revision = draft.fetch("revision")
      plan = flow.fetch("plan")
      [
        "I shaped the recorded evidence into this proposed revision.", "",
        "Song: #{plan['title']}",
        "Intent: #{plan['music_intent']}",
        "Duration / Mode / Rights: #{plan['duration_seconds']} seconds / #{plan['vocal_mode']} / #{plan['rights_status']}",
        "BPM / Key / Time: #{revision['bpm']} / #{revision['keyscale']} / #{revision['timesignature']}",
        "Sound and Structure: #{revision['caption']}", "",
        "Lyrics and section markers (preserved):", revision['lyrics'].to_s, "",
        "Why this revision: #{draft['rationale']}",
        "Changes: #{Array(draft['changes']).join(' ')}", "",
        "Review the complete input. Clicking the action revalidates Music Core and authorizes only this exact linked revision candidate."
      ].join("\n")
    end

    def execute_music_revision(flow, progress)
      draft = flow.fetch("revision_draft")
      music = flow.dig("generated", "music")
      progress&.call({ "stage" => "core", "message" => "Revalidating Music Core for the exact revision." })
      core = ensure_creative_core(flow)
      return core unless core.fetch("ok")

      project_id = music.dig("project", "project_id")
      source_candidate_id = draft.fetch("source_candidate_id")
      revision = draft.fetch("revision")
      preview = @music_generation.revision_preview(project_id: project_id, source_candidate_id: source_candidate_id, revision: revision)
      return preview unless preview.fetch("ok")
      gate = preview.fetch("data")
      progress&.call({ "stage" => "music_revision", "message" => "Generating the exact linked revision candidate." })
      generated = @music_generation.revision_execute(
        project_id: project_id, source_candidate_id: source_candidate_id,
        candidate_id: gate.fetch("candidate_id"), revision: revision,
        confirmation: gate.fetch("confirmation_phrase"), expected_digest: gate.fetch("expected_digest"), progress: progress
      )
      return generated unless generated.fetch("ok")

      flow["generated"]["music"]["candidate"] = generated.dig("data", "candidate")
      flow.delete("revision_draft")
      flow.delete("review_draft")
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "generated"
      flow["pending_action"] = nil
      attachments = [music_attachment(flow.dig("generated", "music"))]
      message = append_assistant(flow.fetch("chat_id"), "The revised music candidate is ready. Listen here, then give me the next keep, revise, or reject review.", flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_music_revision"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "revised music candidate generated; human review required",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments }, mutation: "music_revision_candidate_generated")
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "music revision execution failed safely: #{error.class}")
    end

    def plan_visual_revision(flow, message, provider, progress)
      return nil unless visual_revision_eligible?(flow) && explicit_visual_revision_request?(flow, message)

      progress&.call({ "state" => "planning", "summary" => "Translating the recorded visual review into one bounded guided edit." })
      visual = flow.dig("generated", "visual")
      inspected = @visual_studio.inspect(project_id: visual.dig("project", "project_id"))
      return failure_result(inspected.fetch("reason", "visual project could not be inspected"), flow) unless inspected.fetch("ok")
      project = inspected.dig("data", "project")
      candidate = Array(project["candidates"]).find { |item| item["candidate_id"] == visual.dig("candidate", "candidate_id") }
      return failure_result("the reviewed visual candidate no longer exists", flow) unless candidate

      drafted = @visual_revision_drafter.draft(project: project, candidate: candidate, provider: provider)
      return failure_result(drafted.fetch("reason", "visual revision drafting did not complete"), flow) unless drafted.fetch("ok")
      data = drafted.fetch("data")
      flow["visual_revision_draft"] = {
        "source_candidate_id" => candidate.fetch("candidate_id"), "instruction" => data.fetch("instruction"),
        "seed" => data.fetch("seed"), "rationale" => data.fetch("rationale"), "packet_digest" => data["packet_digest"]
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_visual_revision_action(flow)
      @flow_store.write(flow)
      result(render_visual_revision(flow), "creative_visual_revision_ready", flow, actions: [flow.fetch("pending_action")])
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("visual revision planning failed safely: #{error.class}", flow)
    end

    def visual_revision_eligible?(flow)
      flow.dig("review_draft", "visual_disposition") == "revise" &&
        flow.dig("generated", "visual") && !flow.dig("generated", "visual", "existing")
    end

    def explicit_visual_revision_request?(flow, message)
      return false unless explicit_revision_request?(message)
      text = message.to_s
      return true if text.match?(/\b(?:visual|image|picture|art|artwork)\b/i)
      !music_revision_eligible?(flow)
    end

    def build_visual_revision_action(flow)
      { "action_id" => "creative_visual_revision", "operation" => "chats.creative.execute", "label" => "Generate exact guided visual revision",
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => "bounded_visual_revision_generation" }
    end

    def render_visual_revision(flow)
      draft = flow.fetch("visual_revision_draft")
      visual = flow.dig("generated", "visual")
      [
        "I shaped the recorded visual evidence into this proposed guided edit.", "",
        "Visual: #{visual.dig('project', 'title')}", "Source candidate: #{draft['source_candidate_id']}",
        "Edit instruction: #{draft['instruction']}", "Seed: #{draft['seed']}",
        "Why this revision: #{draft['rationale']}", "",
        "Review the complete edit. Clicking the action revalidates the creative Core and authorizes only this exact linked image-guided revision."
      ].join("\n")
    end

    def execute_visual_revision(flow, progress)
      draft = flow.fetch("visual_revision_draft")
      visual = flow.dig("generated", "visual")
      progress&.call({ "stage" => "core", "message" => "Revalidating the creative Core for the exact visual revision." })
      core = ensure_creative_core(flow)
      return core unless core.fetch("ok")

      project_id = visual.dig("project", "project_id")
      source_candidate_id = draft.fetch("source_candidate_id")
      preview = @visual_studio.edit_preview(project_id: project_id, source_candidate_id: source_candidate_id,
        instruction: draft.fetch("instruction"), seed: draft.fetch("seed"))
      return preview unless preview.fetch("ok")
      gate = preview.fetch("data")
      progress&.call({ "stage" => "visual_revision", "message" => "Generating the exact linked guided visual revision." })
      generated = @visual_studio.edit_execute(
        project_id: project_id, source_candidate_id: source_candidate_id, candidate_id: gate.fetch("candidate_id"),
        instruction: draft.fetch("instruction"), seed: draft.fetch("seed"), confirmation: gate.fetch("confirmation_phrase"),
        expected_digest: gate.fetch("expected_digest"), progress: progress
      )
      return generated unless generated.fetch("ok")

      flow["generated"]["visual"]["candidate"] = generated.dig("data", "candidate")
      flow.delete("visual_revision_draft")
      flow.delete("review_draft")
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "generated"
      flow["pending_action"] = nil
      attachments = [visual_attachment(flow.dig("generated", "visual"))]
      message = append_assistant(flow.fetch("chat_id"), "The guided visual revision is ready. Inspect it here, then give me the next keep or revise review.", flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_visual_revision"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "revised visual candidate generated; human review required",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments }, mutation: "visual_revision_candidate_generated")
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "visual revision execution failed safely: #{error.class}")
    end

    def plan_review(flow, message, provider, progress)
      progress&.call({ "state" => "reviewing", "summary" => "Translating your listening and visual evidence into the exact review fields." })
      drafted = @review_planner.draft(provider: provider, chat_id: flow.fetch("chat_id"), message: message, flow: public_flow(flow))
      return failure_result(drafted.fetch("reason"), flow) unless drafted.fetch("ok")
      review = drafted.fetch("review")
      return nil unless review.fetch("related")
      missing = review_missing(flow, review)
      flow["review_draft"] = review
      if missing.any?
        flow["lifecycle_state"] = "awaiting_input"
        flow["pending_action"] = nil
        @flow_store.write(flow)
        question = review["next_question"].to_s.strip
        question = "I still need #{missing.first} for the exact review." if question.empty?
        return result("I have the review direction, but #{missing.join(', ')} is still missing.\n\n#{question}", "creative_review_awaiting_input", flow)
      end
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_review_action(flow)
      @flow_store.write(flow)
      result(render_review(flow), "creative_review_ready", flow, actions: [flow.fetch("pending_action")])
    end

    def review_missing(flow, review)
      missing = []
      music = flow.dig("generated", "music")
      visual = flow.dig("generated", "visual")
      if music && !music["existing"]
        missing << "music disposition" if review["music_disposition"].empty?
        missing << "music rating" unless review["music_rating"].between?(1, 5)
        %w[musical_quality prompt_adherence vocal_adherence lyric_adherence].each { |key| missing << key.tr("_", " ") if review[key].empty? }
      end
      if visual && !visual["existing"]
        missing << "visual disposition" if review["visual_disposition"].empty?
        missing << "visual rating" unless review["visual_rating"].between?(1, 5)
      end
      missing
    end

    def build_review_action(flow)
      { "action_id" => "creative_review", "operation" => "chats.creative.execute", "label" => "Record exact candidate review",
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => "write_local_review_state" }
    end

    def render_review(flow)
      review = flow.fetch("review_draft")
      lines = ["I translated your evidence into this review."]
      if flow.dig("generated", "music") && !flow.dig("generated", "music", "existing")
        lines.concat(["", "Music: #{review['music_disposition']} · #{review['music_rating']}/5",
          "Quality / prompt / vocals / lyrics: #{review['musical_quality']} / #{review['prompt_adherence']} / #{review['vocal_adherence']} / #{review['lyric_adherence']}",
          "Notes: #{review['music_notes']}"])
      end
      if flow.dig("generated", "visual") && !flow.dig("generated", "visual", "existing")
        lines.concat(["", "Visual: #{review['visual_disposition']} · #{review['visual_rating']}/5", "Notes: #{review['visual_notes']}"])
      end
      lines << "\nClicking the action records exactly this review. It does not bind, render, export, or publish."
      lines.join("\n")
    end

    def execute_review(flow)
      review = flow.fetch("review_draft")
      mutations = []
      music = flow.dig("generated", "music")
      if music && !music["existing"]
        recorded = @music_generation.record_review(project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"), review: {
          "rating" => review.fetch("music_rating"), "disposition" => review.fetch("music_disposition"),
          "musical_quality" => review.fetch("musical_quality"), "prompt_adherence" => review.fetch("prompt_adherence"),
          "vocal_adherence" => review.fetch("vocal_adherence"), "lyric_adherence" => review.fetch("lyric_adherence"), "notes" => review.fetch("music_notes")
        })
        return append_terminal(flow, recorded, "Music review could not be recorded") unless recorded.fetch("ok")
        mutations << "music review"
      end
      visual = flow.dig("generated", "visual")
      if visual && !visual["existing"]
        recorded = @visual_studio.record_review(project_id: visual.dig("project", "project_id"), candidate_id: visual.dig("candidate", "candidate_id"), review: {
          "rating" => review.fetch("visual_rating"), "disposition" => review.fetch("visual_disposition"), "notes" => review.fetch("visual_notes")
        })
        return append_terminal(flow, recorded, "Visual review could not be recorded") unless recorded.fetch("ok")
        mutations << "visual review"
      end
      music_followup = music && !music["existing"] && %w[keep revise reject].include?(review["music_disposition"])
      visual_followup = visual && !visual["existing"] && review["visual_disposition"] == "revise"
      companion_followup = companion_binding_eligible?(flow)
      flow["lifecycle_state"] = music_followup || visual_followup || companion_followup ? "blocked_for_human_review" : "complete"
      flow["stage"] = "reviewed"
      flow["pending_action"] = nil
      followup = case review["music_disposition"]
      when "keep" then " Export remains a separate exact next step."
      when "reject" then " Permanent removal remains a separate exact next step."
      when "revise" then " Revision remains a separate, review-bounded next step."
      else flow["lifecycle_state"] == "complete" ? "" : " A separate review-bounded next step remains."
      end
      followup += " Exact companion binding remains a separate next step." if companion_followup
      message = append_assistant(flow.fetch("chat_id"), "Recorded #{mutations.join(' and ')}. The candidates remain in their studio lineage.#{followup}", flow, current_attachments(flow))
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_review"
      @flow_store.write(flow)
      domain(flow.fetch("lifecycle_state"), true, "creative review recorded", data: { "flow" => public_flow(flow), "assistant_message" => message }, mutation: "creative_reviews_recorded")
    end

    def new_flow(chat_id, kind)
      now = @clock.call.iso8601
      { "schema_version" => ConversationCreativeFlowStore::SCHEMA, "flow_id" => "creative_#{SecureRandom.hex(8)}", "chat_id" => chat_id,
        "kind" => kind, "stage" => "brief", "lifecycle_state" => "awaiting_input", "plan" => {}, "missing_required" => [],
        "pending_action" => nil, "generated" => {}, "created_at" => now, "updated_at" => now }
    end

    def supersede(flow)
      flow["lifecycle_state"] = "complete"
      flow["stage"] = "superseded"
      flow["pending_action"] = nil
      @flow_store.write(flow)
    end

    def build_action(flow)
      { "action_id" => "creative_generate", "operation" => "chats.creative.execute", "label" => action_label(flow),
        "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"), "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow), "risk" => "write_local_state_and_bounded_generation" }
    end

    def action_digest(flow)
      scope = { "operation" => "conversation_creative_generate", "flow_id" => flow.fetch("flow_id"), "chat_id" => flow.fetch("chat_id"),
        "kind" => flow.fetch("kind"), "plan" => flow.fetch("plan"), "flow_digest" => @flow_store.digest(flow) }
      Digest::SHA256.hexdigest(JSON.generate(scope))
    end

    def action_label(flow)
      case flow.fetch("kind")
      when "music" then "Create project and generate song"
      when "visual" then "Create project and generate image"
      else "Create projects and generate candidates"
      end
    end

    def render_brief(flow, question: nil)
      plan = flow.fetch("plan")
      lines = ["I have the creative thread."]
      if %w[music combined].include?(flow.fetch("kind"))
        lines.concat(["", "Song", "Title: #{value(plan['title'])}", "Intent: #{value(plan['music_intent'])}",
          "Duration: #{plan['duration_seconds'].to_i.positive? ? "#{plan['duration_seconds']} seconds" : 'needed'}",
          "Mode: #{value(plan['vocal_mode'])}", "Rights: #{value(plan['rights_status'])}",
          "BPM / Key / Time: #{plan['bpm'].to_i.positive? ? plan['bpm'] : 'draft pending'} / #{value(plan['keyscale'])} / #{value(plan['timesignature'])}",
          "Sound and Structure: #{value(plan['caption'])}"])
      end
      if %w[visual combined].include?(flow.fetch("kind"))
        lines.concat(["", "Visual", "Title: #{value(plan['visual_title'])}", "Intent: #{value(plan['visual_intent'])}",
          "Frame: #{value(plan['aspect_ratio'])}", "Scene and aesthetic: #{value(plan['visual_prompt'])}"])
      end
      lines << "\n#{question}" if question
      lines << "\nReview the visible brief. The action below authorizes the exact Core-aware local generation; model text alone cannot start it." unless question
      lines.join("\n")
    end

    def validate_ready_plan!(plan)
      if %w[music combined].include?(plan.fetch("kind")) && plan["existing_music_title"].to_s.empty?
        raise ArgumentError, "creative music title is incomplete" if plan["title"].to_s.strip.empty?
        raise ArgumentError, "creative Sound and Structure is incomplete" unless plan["caption"].to_s.length.between?(20, 512)
        raise ArgumentError, "creative BPM is incomplete" unless plan["bpm"].between?(30, 300)
        raise ArgumentError, "creative key is incomplete" if plan["keyscale"].to_s.strip.empty?
        raise ArgumentError, "creative time is incomplete" unless %w[2 3 4 5 6 7 9 12].include?(plan["timesignature"])
      end
      if %w[visual combined].include?(plan.fetch("kind")) && plan["existing_visual_title"].to_s.empty?
        raise ArgumentError, "creative visual title is incomplete" if plan["visual_title"].to_s.strip.empty?
        raise ArgumentError, "creative visual prompt is incomplete" if plan["visual_prompt"].to_s.length < 20
        raise ArgumentError, "creative frame is incomplete" unless %w[landscape square portrait].include?(plan["aspect_ratio"])
      end
    end

    def ensure_creative_core(flow)
      target_core_id = needs_music?(flow) ? "music" : "amd-free"
      status = @core_orchestration.status
      return status unless status.fetch("ok")
      return status if status.dig("data", "active_core_id") == target_core_id
      preview = @core_orchestration.preview(core_id: target_core_id)
      return preview unless preview.fetch("ok")
      data = preview.fetch("data")
      @core_orchestration.execute(core_id: target_core_id, target_profile_id: data.dig("target_core", "target_profile", "id") || data.dig("target_profile", "id"),
        confirmation: data.fetch("confirmation_phrase"), expected_digest: data.fetch("expected_digest"))
    end

    def generate_music(flow, progress)
      plan = flow.fetch("plan")
      created = @music_generation.create_project({ "title" => plan.fetch("title"), "intent" => plan.fetch("music_intent"),
        "target_duration_seconds" => plan.fetch("duration_seconds"), "vocal_mode" => plan.fetch("vocal_mode"), "rights_status" => plan.fetch("rights_status"),
        "caption" => plan.fetch("caption"), "lyrics" => plan.fetch("vocal_mode") == "instrumental" ? "" : plan.fetch("lyrics"),
        "bpm" => plan.fetch("bpm"), "keyscale" => plan.fetch("keyscale"), "timesignature" => plan.fetch("timesignature"),
        "language" => "en", "seed" => plan.fetch("seed") })
      return created unless created.fetch("ok")
      project = created.dig("data", "project")
      preview = @music_generation.generation_preview(project_id: project.fetch("project_id"))
      return preview unless preview.fetch("ok")
      gate = preview.fetch("data")
      generated = @music_generation.generation_execute(project_id: project.fetch("project_id"), candidate_id: gate.fetch("candidate_id"),
        confirmation: gate.fetch("confirmation_phrase"), expected_digest: gate.fetch("expected_digest"), progress: progress)
      return generated unless generated.fetch("ok")
      success({ "project" => project, "candidate" => generated.dig("data", "candidate") })
    end

    def generate_visual(flow, progress)
      plan = flow.fetch("plan")
      created = @visual_studio.create({ "title" => plan.fetch("visual_title"), "intent" => plan.fetch("visual_intent"),
        "prompt" => plan.fetch("visual_prompt"), "negative_prompt" => plan.fetch("negative_prompt"),
        "aspect_ratio" => plan.fetch("aspect_ratio"), "seed" => plan.fetch("visual_seed") })
      return created unless created.fetch("ok")
      project = created.dig("data", "project")
      preview = @visual_studio.generation_preview(project_id: project.fetch("project_id"))
      return preview unless preview.fetch("ok")
      gate = preview.fetch("data")
      generated = @visual_studio.generation_execute(project_id: project.fetch("project_id"), candidate_id: gate.fetch("candidate_id"),
        confirmation: gate.fetch("confirmation_phrase"), expected_digest: gate.fetch("expected_digest"), progress: progress)
      return generated unless generated.fetch("ok")
      success({ "project" => project, "candidate" => generated.dig("data", "candidate") })
    end

    def resolve_existing_music(title)
      listing = @music_generation.list_projects(limit: 200)
      return listing unless listing.fetch("ok")
      project = exact_title(Array(listing.dig("data", "projects")), title)
      return domain("awaiting_input", false, "no exact Music Studio project matches #{title.inspect}") unless project
      inspected = @music_generation.inspect_project(project_id: project.fetch("project_id"))
      return inspected unless inspected.fetch("ok")
      candidate = Array(inspected.dig("data", "generations")).find { |item| item.dig("review", "disposition") == "keep" }
      return domain("awaiting_input", false, "#{title.inspect} has no kept music candidate") unless candidate
      success({ "project" => project, "candidate" => candidate, "existing" => true })
    end

    def resolve_existing_visual(title)
      listing = @visual_studio.list(limit: 200)
      return listing unless listing.fetch("ok")
      project = exact_title(Array(listing.dig("data", "projects")), title)
      return domain("awaiting_input", false, "no exact Visual Studio project matches #{title.inspect}") unless project
      inspected = @visual_studio.inspect(project_id: project.fetch("project_id"))
      return inspected unless inspected.fetch("ok")
      full = inspected.dig("data", "project")
      candidate = Array(full["candidates"]).find { |item| item.dig("review", "disposition") == "keep" }
      return domain("awaiting_input", false, "#{title.inspect} has no kept visual candidate") unless candidate
      success({ "project" => full, "candidate" => candidate, "existing" => true })
    end

    def exact_title(records, title)
      matches = records.select { |item| item["title"].to_s.casecmp?(title.to_s.strip) }
      matches.one? ? matches.first : nil
    end

    def music_attachment(data)
      project = data.fetch("project"); candidate = data.fetch("candidate")
      { "kind" => "audio", "title" => project.fetch("title"), "project_id" => project.fetch("project_id"), "candidate_id" => candidate.fetch("candidate_id"),
        "player_url" => "/api/v1/music/audio/#{project.fetch('project_id')}/#{candidate.fetch('candidate_id')}/mp3",
        "lossless_url" => "/api/v1/music/audio/#{project.fetch('project_id')}/#{candidate.fetch('candidate_id')}/flac" }
    end

    def visual_attachment(data)
      project = data.fetch("project"); candidate = data.fetch("candidate")
      { "kind" => "image", "title" => project.fetch("title"), "project_id" => project.fetch("project_id"), "candidate_id" => candidate.fetch("candidate_id"),
        "image_url" => "/api/v1/visual/image/#{project.fetch('project_id')}/#{candidate.fetch('candidate_id')}" }
    end

    def current_attachments(flow)
      generated = flow.fetch("generated", {})
      [].tap do |attachments|
        attachments << music_attachment(generated.fetch("music")) if generated["music"]
        attachments << visual_attachment(generated.fetch("visual")) if generated["visual"]
      end
    end

    def generated_content(flow, generated)
      lines = ["The bounded creative pass is complete."]
      lines << "Music candidate: #{generated.dig('music', 'project', 'title')}" if generated["music"]
      lines << "Visual candidate: #{generated.dig('visual', 'project', 'title')}" if generated["visual"]
      lines << "Both remain candidates. Listen or inspect them here, then tell me what to keep, revise, or reject. I will not bind, render, export, or package them before that review."
      lines.join("\n")
    end

    def append_terminal(flow, outcome, prefix, attachments: [], generated: {})
      flow["lifecycle_state"] = outcome.fetch("lifecycle_state", "failed")
      flow["stage"] = "failed"
      flow["pending_action"] = nil
      flow["generated"] = generated
      reason = outcome["reason"] || outcome.dig("data", "reason") || "bounded dependency did not complete"
      message = append_assistant(flow.fetch("chat_id"), "#{prefix}: #{reason}.", flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      @flow_store.write(flow)
      domain(flow.fetch("lifecycle_state"), false, reason, data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments })
    end

    def append_assistant(chat_id, content, flow, attachments)
      @chat_store.add_message(chat_id, role: "assistant", content: content, metadata: {
        "responder" => "conversation_creative_workflow", "runtime" => { "creative_workflow" => public_flow(flow), "attachments" => attachments }
      })
    end

    def result(content, mode, flow, actions: [])
      { "content" => content, "mode" => mode, "metadata" => { "creative_workflow" => public_flow(flow), "actions" => actions } }
    end

    def failure_result(reason, flow)
      result("The creative path stopped safely: #{reason}", "creative_failed", flow || { "flow_id" => nil, "stage" => "failed", "lifecycle_state" => "failed" })
    end

    def public_flow(flow)
      flow.slice("flow_id", "chat_id", "kind", "stage", "lifecycle_state", "missing_required", "plan", "generated", "revision_draft", "visual_revision_draft", "disposition_action", "companion_action", "created_at", "updated_at")
    end

    def needs_music?(flow) = %w[music combined].include?(flow.fetch("kind"))
    def needs_visual?(flow) = %w[visual combined].include?(flow.fetch("kind"))
    def new_music?(flow) = needs_music?(flow) && flow.dig("plan", "existing_music_title").to_s.empty?
    def new_visual?(flow) = needs_visual?(flow) && flow.dig("plan", "existing_visual_title").to_s.empty?
    def value(item) = item.to_s.strip.empty? ? "to be drafted" : item
    def secure_compare(left, right) = left.to_s.bytesize == right.to_s.bytesize && left.to_s.bytes.zip(right.to_s.bytes).reduce(0) { |memo, (a, b)| memo | (a ^ b) }.zero?
    def success(data) = domain("complete", true, "complete", data: data)
    def domain(state, ok, reason, data: {}, mutation: "none") = { "ok" => ok, "lifecycle_state" => state, "reason" => reason, "data" => data, "mutation" => mutation }
  end
end
