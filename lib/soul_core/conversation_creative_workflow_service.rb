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
    CORE_LABELS = {
      "daily" => "Soul Core",
      "amd-free" => "Soul-Lite Core",
      "music" => "Creative Core",
      "free" => "Free Core",
      "dev" => "Dev Core"
    }.freeze

    def initialize(root:, chat_store:, provider_client:, music_generation:, visual_studio:, core_orchestration:, music_disposition: nil, music_visual_companion: nil, publication_package: nil, flow_store: nil, planner: nil, review_planner: nil, revision_drafter: nil, visual_revision_drafter: nil, clock: -> { Time.now.utc })
      @root = File.expand_path(root)
      @chat_store = chat_store
      @music_generation = music_generation
      @music_disposition = music_disposition
      @music_visual_companion = music_visual_companion
      @publication_package = publication_package
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
        followup = plan_native_motion(prior, message)
        return followup if followup
        followup = plan_visual_revision(prior, message, provider, progress)
        return followup if followup
        followup = plan_companion_binding(prior, message)
        return followup if followup
        return nil unless @planner.explicit_request?(message)

        supersede(prior)
        prior = nil
      end
      if prior && prior["stage"] == "motion_generated"
        followup = plan_native_motion_revision(prior, message)
        return followup if followup
        return nil unless @planner.explicit_request?(message)
        supersede(prior)
        prior = nil
      end
      if prior && %w[bound presented rendered].include?(prior["stage"])
        followup = plan_companion_output(prior, message)
        return followup if followup
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
      flow["core_requirement"] = core_requirement(flow, action_id: "creative_generate")
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
      return execute_native_motion(flow, progress) if action.fetch("action_id") == "creative_native_motion"
      return execute_companion_binding(flow) if action.fetch("action_id") == "creative_companion_bind"
      return execute_companion_presentation(flow, progress) if action.fetch("action_id") == "creative_companion_presentation"
      return execute_companion_final(flow, progress) if action.fetch("action_id") == "creative_companion_final"
      return execute_publication_package(flow) if action.fetch("action_id") == "creative_publication_package"
      return execute_music_disposition(flow) if %w[creative_music_export creative_music_reject].include?(action.fetch("action_id"))

      progress&.call({ "stage" => "core", "message" => "Verifying the exact creative Core transition." })
      core = ensure_creative_core(flow, action_id: action.fetch("action_id"))
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

    def plan_native_motion(flow, message)
      return nil unless native_motion_source_eligible?(flow)
      intake = flow.fetch("motion_intake", {})
      return nil unless explicit_native_motion_request?(message) || intake["kind"] == "generate"

      duration = native_motion_duration(message) || intake["duration_seconds"]
      instruction = native_motion_instruction(message) || intake["instruction"]
      unless duration
        return native_motion_input_result(
          flow, "Choose a 4-, 8-, or 12-second native scene duration.",
          kind: "generate", instruction: instruction
        )
      end
      unless instruction
        return native_motion_input_result(
          flow, "Describe the chronological scene direction you want rendered.",
          kind: "generate", duration_seconds: duration
        )
      end

      visual = flow.dig("generated", "visual")
      preview = @visual_studio.native_motion_preview(
        project_id: visual.dig("project", "project_id"),
        instruction: instruction,
        seed: SecureRandom.random_number(2_147_483_648),
        duration_seconds: duration
      )
      return failure_result(preview.fetch("reason", "native motion preview did not complete"), flow) unless preview.fetch("ok")
      flow.delete("motion_intake")
      prepare_native_motion_action(flow, preview.fetch("data"), instruction: instruction, duration: duration, kind: "generate")
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("native motion planning failed safely: #{error.class}", flow)
    end

    def plan_native_motion_revision(flow, message)
      intake = flow.fetch("motion_intake", {})
      return nil unless explicit_native_motion_revision_request?(message) || intake["kind"] == "revision"
      visual = flow.dig("generated", "visual")
      motion = flow.dig("generated", "motion")
      return failure_result("the native motion source is unavailable", flow) unless visual && motion

      inspected = @visual_studio.inspect(project_id: visual.dig("project", "project_id"))
      return failure_result(inspected.fetch("reason", "visual project inspection did not complete"), flow) unless inspected.fetch("ok")
      source = Array(inspected.dig("data", "project", "motions")).find do |candidate|
        candidate["motion_candidate_id"] == motion["motion_candidate_id"]
      end
      return failure_result("the native motion source no longer exists", flow) unless source
      unless source.dig("review", "disposition") == "revise"
        return result(
          "Record a `revise` review for this exact native scene in Visual Studio before asking Chat to generate its linked revision.",
          "creative_native_motion_review_required", flow
        )
      end

      duration = native_motion_duration(message) || intake["duration_seconds"] || Integer(source.fetch("duration_seconds").round)
      instruction = native_motion_revision_instruction(message) || intake["instruction"]
      if intake["kind"] == "revision" && instruction.nil?
        followup = message.to_s.strip
        instruction = followup if followup.length.between?(20, 8_000)
      end
      unless instruction
        return native_motion_input_result(
          flow, "Describe what the native scene revision should change.",
          kind: "revision", duration_seconds: duration
        )
      end
      preview = @visual_studio.native_motion_revision_preview(
        project_id: visual.dig("project", "project_id"),
        source_motion_id: source.fetch("motion_candidate_id"),
        instruction: instruction,
        seed: SecureRandom.random_number(2_147_483_648),
        duration_seconds: duration
      )
      return failure_result(preview.fetch("reason", "native motion revision preview did not complete"), flow) unless preview.fetch("ok")
      flow.delete("motion_intake")
      prepare_native_motion_action(
        flow, preview.fetch("data"), instruction: instruction, duration: duration,
        kind: "revision", source_motion_id: source.fetch("motion_candidate_id")
      )
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("native motion revision planning failed safely: #{error.class}", flow)
    end

    def prepare_native_motion_action(flow, preview, instruction:, duration:, kind:, source_motion_id: nil)
      flow["motion_action"] = {
        "kind" => kind,
        "instruction" => instruction,
        "duration_seconds" => duration,
        "seed" => preview.fetch("seed"),
        "motion_candidate_id" => preview.fetch("motion_candidate_id"),
        "source_motion_candidate_id" => source_motion_id,
        "confirmation_phrase" => preview.fetch("confirmation_phrase"),
        "downstream_digest" => preview.fetch("expected_digest"),
        "preview_scope" => preview.reject { |key, _| %w[confirmation_phrase expected_digest].include?(key) }
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["core_requirement"] = core_requirement(flow, action_id: "creative_native_motion")
      flow["pending_action"] = build_native_motion_action(flow, kind)
      @flow_store.write(flow)
      result(render_native_motion(flow), "creative_native_motion_ready", flow, actions: [flow.fetch("pending_action")])
    end

    def build_native_motion_action(flow, kind)
      {
        "action_id" => "creative_native_motion",
        "operation" => "chats.creative.execute",
        "label" => kind == "revision" ? "Generate exact native scene revision" : "Generate exact native scene",
        "flow_id" => flow.fetch("flow_id"),
        "chat_id" => flow.fetch("chat_id"),
        "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow),
        "risk" => "bounded_native_video_generation",
        "core_requirement" => flow.fetch("core_requirement")
      }
    end

    def render_native_motion(flow)
      action = flow.fetch("motion_action")
      scope = action.fetch("preview_scope")
      [
        action.fetch("kind") == "revision" ? "The linked native scene revision is ready for exact review." : "The native scene is ready for exact review.",
        "Duration: #{action.fetch('duration_seconds')} seconds",
        "Direction: #{action.fetch('instruction')}",
        "Seed: #{action.fetch('seed')}",
        "Profile: #{scope['profile_id']}",
        "Generation / delivery: #{scope['generation_frames']} frames at #{scope['generation_fps']} fps → #{scope['frames']} frames at #{scope['fps']} fps",
        "Delivery method: #{scope['delivery_method']}",
        "Estimated runtime: #{scope['estimated_runtime_seconds'] || 'not yet measured'} seconds",
        "External publication: not included",
        "",
        *render_core_requirement(flow),
        "",
        "Clicking the action authorizes only this exact Core-aware bounded render."
      ].join("\n")
    end

    def execute_native_motion(flow, progress)
      action = flow.fetch("motion_action")
      visual = flow.dig("generated", "visual")
      core = ensure_creative_core(flow, action_id: "creative_native_motion")
      return append_terminal(flow, core, "Core transition did not complete; native motion was not started") unless core.fetch("ok")

      attributes = {
        project_id: visual.dig("project", "project_id"),
        motion_id: action.fetch("motion_candidate_id"),
        instruction: action.fetch("instruction"),
        seed: action.fetch("seed"),
        duration_seconds: action.fetch("duration_seconds"),
        confirmation: action.fetch("confirmation_phrase"),
        expected_digest: action.fetch("downstream_digest"),
        progress: progress
      }
      outcome = if action.fetch("kind") == "revision"
        @visual_studio.native_motion_revision_execute(
          **attributes, source_motion_id: action.fetch("source_motion_candidate_id")
        )
      else
        @visual_studio.native_motion_execute(**attributes)
      end
      return append_terminal(flow, outcome, "Native motion generation stopped safely") unless outcome.fetch("ok")

      motion = outcome.dig("data", "motion")
      flow["generated"]["motion"] = motion
      flow.delete("motion_action")
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["stage"] = "motion_generated"
      flow["pending_action"] = nil
      attachments = [native_motion_attachment(visual, motion)]
      content = "The native scene is ready for review. It remains a Visual Studio candidate and nothing was bound, exported, uploaded, or published. Record keep or revise in Visual Studio; a revise review can return here for another exact linked attempt."
      message = append_assistant(flow.fetch("chat_id"), content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_native_motion"
      @flow_store.write(flow)
      domain(
        "blocked_for_human_review", true, "native motion generated; Visual Studio review required",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, "motion" => motion },
        mutation: outcome.fetch("mutation", "visual_native_motion_generated")
      )
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "native motion execution failed safely: #{error.class}")
    end

    def native_motion_source_eligible?(flow)
      visual = flow.dig("generated", "visual")
      return false unless visual
      return true if visual["existing"]

      flow.dig("review_draft", "visual_disposition") == "keep"
    end

    def explicit_native_motion_request?(message)
      text = message.to_s.strip
      ConversationRequestShape.new.action_request?(text) &&
        text.match?(/\b(?:create|generate|make|render|build|produce)\b/i) &&
        text.match?(/\b(?:native video|native scene|text[- ]to[- ]video|generated video)\b/i)
    end

    def explicit_native_motion_revision_request?(message)
      text = message.to_s.strip
      text.match?(/\b(?:revise|retry|regenerate|redo)\b/i) &&
        text.match?(/\b(?:native video|native scene|motion|video|scene|it)\b/i)
    end

    def native_motion_duration(message)
      match = message.to_s.match(/\b(4|8|12)\s*(?:seconds?|secs?|s)\b/i)
      match && Integer(match[1])
    end

    def native_motion_instruction(message)
      text = message.to_s.strip
      instruction = if text.include?(":")
        text.split(":", 2).last.to_s.strip
      else
        text[/\b(?:native video|native scene|text[- ]to[- ]video|generated video)\b(?:\s+(?:of|showing|where|with|that))?\s+(.+)\z/i, 1].to_s.strip
      end
      instruction.length.between?(20, 8_000) ? instruction : nil
    end

    def native_motion_revision_instruction(message)
      text = message.to_s.strip
      instruction = if text.include?(":")
        text.split(":", 2).last.to_s.strip
      else
        text[/\b(?:revise|retry|regenerate|redo)\b.*?\b(?:to|so that|with)\b\s+(.+)\z/i, 1].to_s.strip
      end
      instruction.length.between?(20, 8_000) ? instruction : nil
    end

    def native_motion_input_result(flow, prompt, kind: nil, instruction: nil, duration_seconds: nil)
      flow["motion_intake"] = {
        "kind" => kind,
        "instruction" => instruction,
        "duration_seconds" => duration_seconds
      }.compact
      flow["lifecycle_state"] = "awaiting_input"
      flow["pending_action"] = nil
      @flow_store.write(flow)
      result(prompt, "creative_native_motion_awaiting_input", flow)
    end

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

    def plan_companion_output(flow, message)
      if explicit_publication_request?(message) || explicit_publication_continue?(flow, message)
        flow["completion_target"] = "publication"
        return plan_publication_path(flow)
      end
      return plan_music_export(flow, resume_stage: flow.fetch("stage")) if explicit_export_request?(message)
      return plan_companion_render(flow, target: "video") if explicit_companion_render_request?(message)
      return plan_companion_render(flow, target: flow["completion_target"]) if explicit_video_continue?(flow, message)

      nil
    end

    def plan_publication_path(flow)
      return plan_companion_render(flow, target: "publication") unless flow["stage"] == "rendered"
      return failure_result("finished-song export service is unavailable", flow) unless @music_disposition

      music = flow.dig("generated", "music")
      export = @music_disposition.export_preview(
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id")
      )
      return failure_result(export.fetch("reason", "music export preview did not complete"), flow) unless export.fetch("ok")
      unless export.fetch("lifecycle_state") == "complete"
        return prepare_music_disposition_action(
          flow, "export", export.fetch("data"),
          resume_stage: "rendered", package_after_export: true
        )
      end

      flow["outputs"] ||= {}
      flow["outputs"]["music_export"] = export.dig("data", "export")
      @flow_store.write(flow)
      plan_publication_package(flow)
    end

    def plan_companion_render(flow, target:)
      return failure_result("music visual companion service is unavailable", flow) unless @music_visual_companion
      companion = flow.dig("generated", "companion")
      return failure_result("the reviewed visual is not bound to this music candidate", flow) unless companion
      flow["completion_target"] = target if %w[video publication].include?(target)

      if companion.dig("artifacts", "preview")
        flow["stage"] = "rendered"
        flow["outputs"] ||= {}
        flow["outputs"]["visual_render"] = companion.dig("artifacts", "preview")
        @flow_store.write(flow)
        return target == "publication" ? plan_publication_path(flow) :
          result("The full-duration companion is already rendered. No duplicate file was created.", "creative_companion_render_complete", flow)
      end

      music = flow.dig("generated", "music")
      attributes = {
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id"),
        visual_id: companion.fetch("visual_id")
      }
      if companion["stage"] == "base_bound"
        preview = @music_visual_companion.loop_preview(**attributes, presentation: nil)
        return failure_result(preview.fetch("reason", "static presentation preview did not complete"), flow) unless preview.fetch("ok")
        return prepare_companion_render_action(flow, "presentation", preview.fetch("data"))
      end
      if companion["stage"] == "loop_ready"
        preview = @music_visual_companion.final_preview(**attributes)
        return failure_result(preview.fetch("reason", "full-duration render preview did not complete"), flow) unless preview.fetch("ok")
        return prepare_companion_render_action(flow, "final", preview.fetch("data"))
      end

      failure_result("the bound visual is not ready for a supported render step", flow)
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("companion render planning failed safely: #{error.class}", flow)
    end

    def prepare_companion_render_action(flow, kind, preview)
      flow["companion_render_action"] = {
        "kind" => kind,
        "confirmation_phrase" => preview.fetch("confirmation_phrase"),
        "downstream_digest" => preview.fetch("expected_digest"),
        "preview_scope" => preview.fetch("preview_scope")
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_companion_render_action(flow, kind)
      @flow_store.write(flow)
      mode = kind == "presentation" ? "creative_companion_presentation_ready" : "creative_companion_final_ready"
      result(render_companion_render(flow), mode, flow, actions: [flow.fetch("pending_action")])
    end

    def build_companion_render_action(flow, kind)
      {
        "action_id" => kind == "presentation" ? "creative_companion_presentation" : "creative_companion_final",
        "operation" => "chats.creative.execute",
        "label" => kind == "presentation" ? "Encode exact static review loop" : "Render exact full-duration companion",
        "flow_id" => flow.fetch("flow_id"),
        "chat_id" => flow.fetch("chat_id"),
        "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow),
        "risk" => "bounded_local_media_encode"
      }
    end

    def render_companion_render(flow)
      action = flow.fetch("companion_render_action")
      scope = action.fetch("preview_scope")
      if action.fetch("kind") == "presentation"
        [
          "The reviewed still needs one static presentation before the full song render.",
          "Duration: #{scope.dig('profile', 'duration_seconds') || scope['duration_seconds'] || 12} seconds",
          "Motion synthesis: none",
          "External publication: not included",
          "",
          "Clicking the action authorizes only this exact local presentation encode."
        ].join("\n")
      else
        [
          "The reviewed visual loop is ready to be repeated across the exact candidate audio.",
          "Output: #{scope['output']}",
          "External publication: #{scope['external_publication'] ? 'included' : 'not included'}",
          "",
          "Clicking the action authorizes only this exact full-duration local render."
        ].join("\n")
      end
    end

    def execute_companion_presentation(flow, progress)
      return domain("blocked_for_human_review", false, "music visual companion service is unavailable") unless @music_visual_companion
      stored = flow.fetch("companion_render_action")
      music = flow.dig("generated", "music")
      companion = flow.dig("generated", "companion")
      outcome = @music_visual_companion.loop_execute(
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id"),
        visual_id: companion.fetch("visual_id"),
        presentation: nil,
        confirmation: stored.fetch("confirmation_phrase"),
        expected_digest: stored.fetch("downstream_digest"),
        progress: progress
      )
      return outcome unless outcome.fetch("ok")

      updated = outcome.dig("data", "visual")
      flow["generated"]["companion"] = updated
      flow.delete("companion_render_action")
      flow["pending_action"] = nil
      flow["stage"] = "presented"
      flow["lifecycle_state"] = "blocked_for_human_review"
      attachments = [companion_video_attachment(flow, updated, "loop")]
      content = "The exact static presentation is ready for review. Ask me to render the full-duration companion#{flow['completion_target'] == 'publication' ? ' or continue the publication workflow' : ''} when it looks right."
      message = append_assistant(flow.fetch("chat_id"), content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_companion_presentation"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "static presentation encoded; full-duration render remains gated",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, "companion" => updated },
        mutation: outcome.fetch("mutation", "music_visual_loop_created"))
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "static presentation execution failed safely: #{error.class}")
    end

    def execute_companion_final(flow, progress)
      return domain("blocked_for_human_review", false, "music visual companion service is unavailable") unless @music_visual_companion
      stored = flow.fetch("companion_render_action")
      music = flow.dig("generated", "music")
      companion = flow.dig("generated", "companion")
      outcome = @music_visual_companion.final_execute(
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id"),
        visual_id: companion.fetch("visual_id"),
        confirmation: stored.fetch("confirmation_phrase"),
        expected_digest: stored.fetch("downstream_digest"),
        progress: progress
      )
      return outcome unless outcome.fetch("ok")

      updated = outcome.dig("data", "visual")
      flow["generated"]["companion"] = updated
      flow.delete("companion_render_action")
      flow["pending_action"] = nil
      flow["stage"] = "rendered"
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["outputs"] ||= {}
      flow["outputs"]["visual_render"] = updated.dig("artifacts", "preview")
      attachments = [companion_video_attachment(flow, updated, "preview")]
      content = "The full-duration companion is ready for review. Nothing was uploaded or published.#{flow['completion_target'] == 'publication' ? ' Ask me to continue the publication workflow when it looks right.' : ''}"
      message = append_assistant(flow.fetch("chat_id"), content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_companion_final"
      @flow_store.write(flow)
      domain("blocked_for_human_review", true, "full-duration companion rendered; publication remains separate",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, "companion" => updated },
        mutation: outcome.fetch("mutation", "music_visual_preview_created"))
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "full-duration companion execution failed safely: #{error.class}")
    end

    def plan_publication_package(flow)
      return failure_result("publication package service is unavailable", flow) unless @publication_package
      music = flow.dig("generated", "music")
      companion = flow.dig("generated", "companion")
      attributes = {
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id"),
        visual_id: companion.fetch("visual_id")
      }
      draft = @publication_package.draft(**attributes)
      return failure_result(draft.fetch("reason", "publication description draft did not complete"), flow) unless draft.fetch("ok")
      description = draft.dig("data", "description").to_s
      preview = @publication_package.preview(**attributes, description: description)
      return failure_result(preview.fetch("reason", "publication package preview did not complete"), flow) unless preview.fetch("ok")
      if preview.fetch("lifecycle_state") == "complete"
        flow["lifecycle_state"] = "complete"
        flow["stage"] = "packaged"
        flow["outputs"] ||= {}
        flow["outputs"]["publication_package"] = preview.dig("data", "package")
        @flow_store.write(flow)
        return result("The exact local upload package already exists. No duplicate files were created and nothing was uploaded.", "creative_publication_complete", flow)
      end

      data = preview.fetch("data")
      flow["publication_action"] = {
        "description" => description,
        "confirmation_phrase" => data.fetch("confirmation_phrase"),
        "downstream_digest" => data.fetch("expected_digest"),
        "preview_scope" => data.fetch("preview_scope")
      }
      flow["lifecycle_state"] = "blocked_for_human_review"
      flow["pending_action"] = build_publication_action(flow)
      @flow_store.write(flow)
      result(render_publication(flow), "creative_publication_ready", flow, actions: [flow.fetch("pending_action")])
    rescue KeyError, ArgumentError => error
      failure_result(error.message, flow)
    rescue StandardError => error
      failure_result("publication planning failed safely: #{error.class}", flow)
    end

    def build_publication_action(flow)
      {
        "action_id" => "creative_publication_package",
        "operation" => "chats.creative.execute",
        "label" => "Export exact local YouTube package",
        "flow_id" => flow.fetch("flow_id"),
        "chat_id" => flow.fetch("chat_id"),
        "confirmation_phrase" => EXECUTE_CONFIRMATION,
        "expected_digest" => action_digest(flow),
        "risk" => "write_local_publication_package"
      }
    end

    def render_publication(flow)
      action = flow.fetch("publication_action")
      scope = action.fetch("preview_scope")
      [
        "The local YouTube package is ready for exact review.",
        "Destination: #{scope['destination']}",
        "Upload performed: no",
        "Publication performed: no",
        "",
        "Description",
        action.fetch("description"),
        "",
        "Clicking the action exports only this exact local package."
      ].join("\n")
    end

    def execute_publication_package(flow)
      return domain("blocked_for_human_review", false, "publication package service is unavailable") unless @publication_package
      stored = flow.fetch("publication_action")
      music = flow.dig("generated", "music")
      companion = flow.dig("generated", "companion")
      outcome = @publication_package.execute(
        project_id: music.dig("project", "project_id"),
        candidate_id: music.dig("candidate", "candidate_id"),
        visual_id: companion.fetch("visual_id"),
        description: stored.fetch("description"),
        confirmation: stored.fetch("confirmation_phrase"),
        expected_digest: stored.fetch("downstream_digest")
      )
      return outcome unless outcome.fetch("ok")

      package = outcome.dig("data", "package")
      flow.delete("publication_action")
      flow["pending_action"] = nil
      flow["stage"] = "packaged"
      flow["lifecycle_state"] = "complete"
      flow["outputs"] ||= {}
      flow["outputs"]["publication_package"] = package
      content = "The local YouTube upload package is ready at #{package['destination']}. Nothing was uploaded or published."
      message = append_assistant(flow.fetch("chat_id"), content, flow, [])
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_publication_package"
      @flow_store.write(flow)
      domain("complete", true, "local publication package exported",
        data: { "flow" => public_flow(flow), "assistant_message" => message, "package" => package },
        mutation: outcome.fetch("mutation", "youtube_upload_package_exported"))
    rescue KeyError, ArgumentError => error
      domain("awaiting_input", false, error.message)
    rescue StandardError => error
      domain("failed", false, "publication package execution failed safely: #{error.class}")
    end

    def plan_music_export(flow, resume_stage: nil)
      return failure_result("music disposition service is unavailable", flow) unless @music_disposition
      music = flow.dig("generated", "music")
      preview = @music_disposition.export_preview(project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"))
      if preview.fetch("ok") && preview.fetch("lifecycle_state") == "complete"
        flow["outputs"] ||= {}
        flow["outputs"]["music_export"] = preview.dig("data", "export")
        flow["lifecycle_state"] = resume_stage ? "blocked_for_human_review" : "complete"
        flow["stage"] = resume_stage || "exported"
        @flow_store.write(flow)
        destination = preview.dig("data", "export", "destination")
        return result("The kept song is already exported#{destination ? " to #{destination}" : ''}. No duplicate files were created.", "creative_music_export_complete", flow)
      end
      return failure_result(preview.fetch("reason", "music export preview did not complete"), flow) unless preview.fetch("ok")
      prepare_music_disposition_action(flow, "export", preview.fetch("data"), resume_stage: resume_stage)
    end

    def plan_music_rejection(flow)
      return failure_result("music disposition service is unavailable", flow) unless @music_disposition
      music = flow.dig("generated", "music")
      preview = @music_disposition.reject_preview(project_id: music.dig("project", "project_id"), candidate_id: music.dig("candidate", "candidate_id"))
      return failure_result(preview.fetch("reason", "music rejection preview did not complete"), flow) unless preview.fetch("ok")
      prepare_music_disposition_action(flow, "reject", preview.fetch("data"))
    end

    def prepare_music_disposition_action(flow, kind, preview, resume_stage: nil, package_after_export: false)
      flow["disposition_action"] = {
        "kind" => kind, "confirmation_phrase" => preview.fetch("confirmation_phrase"),
        "downstream_digest" => preview.fetch("expected_digest"), "preview_scope" => preview.fetch("preview_scope"),
        "resume_stage" => resume_stage, "package_after_export" => package_after_export
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
        lines = ["The kept candidate is ready for its exact local export gate.", "Destination: #{scope['destination']}",
          "Files: #{Array(scope['files']).join(', ')}", "Overwrite: #{scope['overwrite'] ? 'allowed' : 'forbidden'}",
          "External publication: #{scope['external_publication'] ? 'included' : 'not included'}", "",
          "Clicking the action authorizes only this exact finished-song export."]
        lines << "The local upload package remains a separate exact step." if action["package_after_export"]
        lines.join("\n")
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
      resume_stage = stored["resume_stage"]
      package_after_export = stored["package_after_export"]
      flow.delete("disposition_action")
      flow["pending_action"] = nil
      resumable_export = kind == "export" && !resume_stage.to_s.empty?
      flow["lifecycle_state"] = resumable_export ? "blocked_for_human_review" : "complete"
      flow["stage"] = resumable_export ? resume_stage : (kind == "export" ? "exported" : "rejected")
      if kind == "export"
        flow["outputs"] ||= {}
        flow["outputs"]["music_export"] = outcome.dig("data", "export")
      end
      flow["generated"].delete("music") if kind == "reject"
      attachments = kind == "export" ? [music_attachment(music)] : []
      content = if kind == "export"
        suffix = package_after_export ? " Ask me to continue the publication workflow when you are ready." : ""
        "The kept song is exported locally to #{outcome.dig('data', 'export', 'destination')}. Nothing was uploaded or published.#{suffix}"
      else
        "The rejected music candidate and its owned audio, input, analysis, and current review were deleted. Its small rejection receipt remains."
      end
      message = append_assistant(flow.fetch("chat_id"), content, flow, attachments)
      flow["result_message_id"] = message.fetch("id")
      flow["last_action_id"] = "creative_music_#{kind}"
      @flow_store.write(flow)
      domain(flow.fetch("lifecycle_state"), true, "music #{kind} completed", data: { "flow" => public_flow(flow), "assistant_message" => message, "attachments" => attachments, kind => outcome.fetch("data") }, mutation: outcome.fetch("mutation", "none"))
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

    def explicit_companion_render_request?(message)
      message.to_s.strip.match?(
        /\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:build|create|encode|make|prepare|render)\b.*\b(?:video|visual companion|full[- ]duration companion|presentation)\b/i
      )
    end

    def explicit_publication_request?(message)
      message.to_s.strip.match?(
        /\A(?:okay[, ]+|ok[, ]+|alright[, ]+)?(?:please\s+)?(?:build|create|export|make|prepare)\b.*\b(?:youtube|upload|publication)\b.*\b(?:package|files?|bundle)?\b/i
      )
    end

    def explicit_publication_continue?(flow, message)
      flow["completion_target"] == "publication" &&
        message.to_s.strip.match?(/\A(?:please\s+)?continue\s+(?:the\s+)?publication\s+workflow[.!]*\z/i)
    end

    def explicit_video_continue?(flow, message)
      flow["completion_target"] == "video" &&
        message.to_s.strip.match?(/\A(?:please\s+)?continue\s+(?:the\s+)?(?:video|companion)\s+workflow[.!]*\z/i)
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
      flow["core_requirement"] = core_requirement(flow, action_id: "creative_music_revision")
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
        "expected_digest" => action_digest(flow), "risk" => "bounded_music_revision_generation",
        "core_requirement" => flow.fetch("core_requirement") }
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
        *render_core_requirement(flow),
        "",
        "Review the complete input. Clicking the action revalidates Creative Core and authorizes only this exact linked revision candidate."
      ].join("\n")
    end

    def execute_music_revision(flow, progress)
      draft = flow.fetch("revision_draft")
      music = flow.dig("generated", "music")
      progress&.call({ "stage" => "core", "message" => "Revalidating Creative Core for the exact revision." })
      core = ensure_creative_core(flow, action_id: "creative_music_revision")
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
      flow["core_requirement"] = core_requirement(flow, action_id: "creative_visual_revision")
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
        "expected_digest" => action_digest(flow), "risk" => "bounded_visual_revision_generation",
        "core_requirement" => flow.fetch("core_requirement") }
    end

    def render_visual_revision(flow)
      draft = flow.fetch("visual_revision_draft")
      visual = flow.dig("generated", "visual")
      [
        "I shaped the recorded visual evidence into this proposed guided edit.", "",
        "Visual: #{visual.dig('project', 'title')}", "Source candidate: #{draft['source_candidate_id']}",
        "Edit instruction: #{draft['instruction']}", "Seed: #{draft['seed']}",
        "Why this revision: #{draft['rationale']}", "",
        *render_core_requirement(flow),
        "",
        "Review the complete edit. Clicking the action revalidates the creative Core and authorizes only this exact linked image-guided revision."
      ].join("\n")
    end

    def execute_visual_revision(flow, progress)
      draft = flow.fetch("visual_revision_draft")
      visual = flow.dig("generated", "visual")
      progress&.call({ "stage" => "core", "message" => "Revalidating the creative Core for the exact visual revision." })
      core = ensure_creative_core(flow, action_id: "creative_visual_revision")
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
        "expected_digest" => action_digest(flow), "risk" => "write_local_state_and_bounded_generation",
        "core_requirement" => flow.fetch("core_requirement") }
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
      lines.concat(["", *render_core_requirement(flow)]) unless question
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

    def core_requirement(flow, action_id:)
      status = @core_orchestration.status
      raise ArgumentError, status.fetch("reason", "Core status is unavailable") unless status.fetch("ok")

      active_core_id = status.dig("data", "active_core_id").to_s
      raise ArgumentError, "active Core is unavailable" unless CORE_LABELS.key?(active_core_id)

      required_core_id = required_core_id(flow, action_id)
      {
        "active_core_id" => active_core_id,
        "active_core_label" => CORE_LABELS.fetch(active_core_id),
        "required_core_id" => required_core_id,
        "required_core_label" => required_core_id ? CORE_LABELS.fetch(required_core_id) : "No Core transfer",
        "transition_required" => !required_core_id.nil? && active_core_id != required_core_id,
        "authorization" => "included_in_exact_action_click",
        "reason" => core_requirement_reason(action_id, required_core_id)
      }
    end

    def required_core_id(flow, action_id)
      case action_id
      when "creative_music_revision" then "music"
      when "creative_visual_revision" then "amd-free"
      when "creative_native_motion" then "amd-free"
      when "creative_generate"
        return "music" if new_music?(flow)
        return "amd-free" if new_visual?(flow)
        nil
      else
        nil
      end
    end

    def core_requirement_reason(action_id, required_core_id)
      return "This action resolves reviewed local sources and does not start bounded generation." unless required_core_id
      return "Music generation reserves AMD for ACE-Step while NVIDIA carries chat." if %w[creative_generate creative_music_revision].include?(action_id) && required_core_id == "music"

      "Visual generation releases AMD chat before the bounded Vulkan render."
    end

    def render_core_requirement(flow)
      requirement = flow.fetch("core_requirement")
      transition = if requirement.fetch("transition_required")
        "#{requirement.fetch('active_core_label')} → #{requirement.fetch('required_core_label')} after your click"
      elsif requirement["required_core_id"]
        "Already in #{requirement.fetch('required_core_label')}; no transfer needed"
      else
        "No transfer needed"
      end
      [
        "Core preflight",
        "Active: #{requirement.fetch('active_core_label')}",
        "Required: #{requirement.fetch('required_core_label')}",
        "Transition: #{transition}",
        "Reason: #{requirement.fetch('reason')}"
      ]
    end

    def ensure_creative_core(flow, action_id:)
      target_core_id = required_core_id(flow, action_id)
      stored = flow.fetch("core_requirement")
      return domain("blocked_for_human_review", false, "creative Core requirement changed; review the action again") unless stored["required_core_id"] == target_core_id
      return success({ "core_transition" => "not_required" }) unless target_core_id

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

    def native_motion_attachment(visual, motion)
      project = visual.fetch("project")
      {
        "kind" => "video",
        "title" => "#{project.fetch('title')} · native scene",
        "project_id" => project.fetch("project_id"),
        "motion_candidate_id" => motion.fetch("motion_candidate_id"),
        "video_url" => "/api/v1/visual/motion/#{project.fetch('project_id')}/#{motion.fetch('motion_candidate_id')}",
        "note" => "Local Visual Studio motion candidate; not bound, exported, uploaded, or published."
      }
    end

    def companion_video_attachment(flow, companion, artifact)
      music = flow.dig("generated", "music")
      project = music.fetch("project")
      candidate = music.fetch("candidate")
      {
        "kind" => "video",
        "title" => "#{project.fetch('title')} · #{artifact == 'preview' ? 'full companion' : 'review loop'}",
        "project_id" => project.fetch("project_id"),
        "candidate_id" => candidate.fetch("candidate_id"),
        "visual_id" => companion.fetch("visual_id"),
        "video_url" => "/api/v1/music/visual/#{project.fetch('project_id')}/#{candidate.fetch('candidate_id')}/#{companion.fetch('visual_id')}/#{artifact}",
        "note" => artifact == "preview" ? "Local full-duration render; not uploaded or published." : "Local review loop; full-duration rendering remains separate."
      }
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
      flow.slice(
        "flow_id", "chat_id", "kind", "stage", "lifecycle_state", "missing_required",
        "plan", "core_requirement", "generated", "outputs", "completion_target",
        "revision_draft", "visual_revision_draft", "disposition_action",
        "companion_action", "companion_render_action", "publication_action", "motion_action", "motion_intake",
        "created_at", "updated_at"
      )
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
