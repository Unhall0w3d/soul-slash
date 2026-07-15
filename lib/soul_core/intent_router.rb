
# frozen_string_literal: true

module SoulCore
  class IntentRouter
    class Result
      ATTRIBUTES = [
        :id,
        :label,
        :confidence,
        :skill_id,
        :risk,
        :confirmation_required,
        :reason,
        :next_step,
        :ok,
        :intent,
        :parameters,
        :source
      ].freeze

      attr_accessor(*ATTRIBUTES)

      def initialize(**kwargs)
        kwargs.each do |key, value|
          public_send("#{key}=", value) if ATTRIBUTES.include?(key)
        end
      end

      def to_h
        {
          "id" => id,
          "label" => label,
          "confidence" => confidence,
          "skill_id" => skill_id,
          "risk" => risk,
          "confirmation_required" => confirmation_required,
          "reason" => reason,
          "next_step" => next_step,
          "ok" => ok,
          "intent" => intent,
          "parameters" => parameters,
          "source" => source
        }.reject { |_key, value| value.nil? }
      end
    end

    Intent = Result

    RULES = [
      ["identity", "Soul identity", /\b(who are you|what are you|what is soul|explain yourself|your personality)\b/i, nil, "none", false, 0.95, "The request asks Soul to explain itself."],
      ["skill_catalog", "Skill catalog", /\b(what skills|list skills|skills do you have|what can you do|capabilities)\b/i, "assistant-skill-catalog", "read_only", false, 0.93, "The request asks for available skills or capabilities."],
      ["execution_history_summary", "Execution history summary", /\b(execution history summary|history summary|summarize execution history|summarize history)\b/i, "execution.history.summary", "read_only", false, 0.9, "The request asks for a summary of local chat execution history."],
      ["repo_status", "Repository/runtime status", /\b(repo|repository|doctor|runtime|health|status|curation|ruby runtime)\b/i, "system.status", "read_only", false, 0.78, "The request appears to ask about project or runtime condition."],
      ["pending_work", "Pending work / next build step", /\b(next|pending|todo|to do|build next|what should we build|roadmap|phase)\b/i, nil, "planning", false, 0.82, "The request asks about upcoming work or planning."],
      ["weather_request", "Weather request", /\b(weather|forecast|temperature|rain|snow|storm)\b/i, "weather.report", "read_only", false, 0.86, "The request appears to ask for weather information."],
      ["chats_forget", "Conversation deletion and forgetting", /\b(?:delete|forget|erase|purge)\b.*\b(?:chat|conversation)\b|\b(?:chat|conversation)\b.*\b(?:delete|forget|erase|purge)\b/i, "chats.forget", "approval_required", true, 0.97, "The request asks to permanently delete one local conversation or forget its derived memory."],
      ["chats_clear", "Conversation list clearing", /\b(?:clear|remove|archive|hide)\b.*\b(?:chat|chats|conversation|conversations)\b|\b(?:chat|chats|conversation|conversations)\b.*\b(?:clear|remove|archive|hide)\b/i, "chats.clear", "approval_required", true, 0.92, "The request changes which local conversations appear in the active list."],
      ["downloads_move_to_trash", "Downloads move to trash", /\b(move.*downloads.*trash|move.*trash|delete downloads|trash downloads|execute cleanup|remove downloads)\b/i, "downloads.move_to_trash", "approval_required", true, 0.89, "The request may change local filesystem state."],
      ["downloads_cleanup_plan", "Downloads cleanup planning", /\b(clean up downloads|cleanup downloads|downloads cleanup|plan.*downloads|safe cleanup)\b/i, "downloads.cleanup_plan", "review_only", false, 0.86, "The request asks for cleanup planning, not immediate deletion."],
      ["downloads_inspect", "Downloads inspection", /\b(downloads|download folder|inspect downloads|what is in downloads)\b/i, "downloads.inspect", "read_only", false, 0.86, "The request appears to ask about the local Downloads folder."],
      ["cloud_providers", "Cloud provider check", /\b(cloud provider|providers|provider connectivity|test providers|openai|gemini|codex)\b/i, "cloud.providers.list", "network_or_provider_check", false, 0.74, "The request appears related to configured cloud/model providers."],
      ["youtube_request", "YouTube lookup", /\b(youtube|song search|video resolve|find.*video|find.*song)\b/i, "youtube.song_search", "read_only", false, 0.78, "The request appears to ask for YouTube lookup/resolution."],
      ["skill_brief", "Skill brief drafting or review", /\b(skill brief|draft.*skill|review.*skill|new skill|skill proposal)\b/i, "skill.brief.draft", "review_only", false, 0.8, "The request appears to ask for skill design or review."]
    ].map do |id, label, regex, skill_id, risk, confirmation_required, confidence, reason|
      {
        id: id,
        label: label,
        regex: regex,
        skill_id: skill_id,
        risk: risk,
        confirmation_required: confirmation_required,
        confidence: confidence,
        reason: reason
      }
    end.freeze

    def route(message)
      text = message.to_s.strip
      return unknown("The message is empty.") if text.empty?

      rule = RULES.find { |candidate| text.match?(candidate.fetch(:regex)) }
      rule ? from_rule(rule) : unknown("No deterministic Phase 45+ rule matched this message.")
    end

    def explain(message)
      intent = route(message)
      [
        "Intent: #{intent.label || intent.intent || intent.id}",
        "id: #{intent.id || intent.intent || 'unknown'}",
        "confidence: #{format('%.2f', intent.confidence || 0.0)}",
        "skill_id: #{intent.skill_id || 'none'}",
        "risk: #{intent.risk || 'unknown'}",
        "confirmation_required: #{intent.confirmation_required || false}",
        "reason: #{intent.reason}",
        "next_step: #{intent.next_step}"
      ].join("\n")
    end

    private

    def from_rule(rule)
      Result.new(
        id: rule.fetch(:id),
        label: rule.fetch(:label),
        confidence: rule.fetch(:confidence),
        skill_id: rule.fetch(:skill_id),
        risk: rule.fetch(:risk),
        confirmation_required: rule.fetch(:confirmation_required),
        reason: rule.fetch(:reason),
        next_step: next_step_for(rule)
      )
    end

    def next_step_for(rule)
      if rule.fetch(:confirmation_required)
        "Prepare a plan and require explicit owner confirmation before execution."
      elsif rule.fetch(:skill_id)
        "Explain the mapped skill and wait for a safe invocation gate."
      else
        "Respond directly using deterministic chat behavior."
      end
    end

    def unknown(reason)
      Result.new(
        id: "unknown",
        label: "Unknown / conversational",
        confidence: 0.2,
        skill_id: nil,
        risk: "unknown",
        confirmation_required: false,
        reason: reason,
        next_step: "Respond with the current deterministic fallback until LLM-backed conversation or richer routing exists."
      )
    end
  end
end
