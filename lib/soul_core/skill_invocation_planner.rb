
# frozen_string_literal: true

require_relative "intent_router"

module SoulCore
  class SkillInvocationPlanner
    Plan = Struct.new(
      :intent_id,
      :intent_label,
      :skill_id,
      :risk,
      :confirmation_required,
      :executable_now,
      :reason,
      :plan_steps,
      :blocked_by,
      :owner_message,
      keyword_init: true
    ) do
      def to_h
        {
          "intent_id" => intent_id,
          "intent_label" => intent_label,
          "skill_id" => skill_id,
          "risk" => risk,
          "confirmation_required" => confirmation_required,
          "executable_now" => executable_now,
          "reason" => reason,
          "plan_steps" => plan_steps,
          "blocked_by" => blocked_by,
          "owner_message" => owner_message
        }
      end
    end

    def initialize(router: IntentRouter.new)
      @router = router
    end

    def plan(message)
      intent = @router.route(message)
      build_plan(intent)
    end

    def explain(message)
      plan = plan(message)
      lines = []
      lines << "Skill invocation plan"
      lines << "intent: #{plan.intent_label} (#{plan.intent_id})"
      lines << "skill_id: #{plan.skill_id || 'none'}"
      lines << "risk: #{plan.risk}"
      lines << "confirmation_required: #{plan.confirmation_required}"
      lines << "executable_now: #{plan.executable_now}"
      lines << "reason: #{plan.reason}"
      lines << ""
      lines << "Plan steps:"
      plan.plan_steps.each_with_index { |step, index| lines << "#{index + 1}. #{step}" }
      lines << ""
      lines << "Blocked by:"
      if plan.blocked_by.empty?
        lines << "- none"
      else
        plan.blocked_by.each { |item| lines << "- #{item}" }
      end
      lines << ""
      lines << plan.owner_message
      lines.join("\n")
    end

    private

    def build_plan(intent)
      if intent.skill_id.nil?
        return Plan.new(
          intent_id: intent.id || intent.intent || "unknown",
          intent_label: intent.label || intent.intent || "Unknown",
          skill_id: nil,
          risk: intent.risk || "unknown",
          confirmation_required: false,
          executable_now: false,
          reason: "No candidate skill was mapped for this intent.",
          plan_steps: [
            "Respond directly if the deterministic responder can handle it.",
            "Otherwise wait for richer conversation support."
          ],
          blocked_by: ["no_candidate_skill"],
          owner_message: "I can understand the shape of this request, but I do not have a skill path for it yet."
        )
      end

      confirmation_required = intent.confirmation_required || intent.risk == "approval_required"
      blocked_by = ["chat_skill_execution_not_enabled"]

      blocked_by << "owner_confirmation_required" if confirmation_required

      steps = [
        "Identify the routed intent.",
        "Identify candidate skill #{intent.skill_id}.",
        "Explain the risk category: #{intent.risk || 'unknown'}.",
        "Do not execute the skill from chat in Phase 46."
      ]

      if confirmation_required
        steps << "Prepare an approval prompt before any future execution."
      else
        steps << "Wait for the future invocation executor to run this safely."
      end

      Plan.new(
        intent_id: intent.id || intent.intent || "unknown",
        intent_label: intent.label || intent.intent || "Unknown",
        skill_id: intent.skill_id,
        risk: intent.risk || "unknown",
        confirmation_required: confirmation_required,
        executable_now: false,
        reason: "Phase 46 creates safe skill invocation plans only. It does not execute skills.",
        plan_steps: steps,
        blocked_by: blocked_by,
        owner_message: owner_message_for(intent, confirmation_required)
      )
    end

    def owner_message_for(intent, confirmation_required)
      if confirmation_required
        "This maps to `#{intent.skill_id}`, but it requires confirmation and Phase 46 cannot execute it yet. Good. Tiny machines do not get unsupervised deletion privileges."
      else
        "This maps to `#{intent.skill_id}`. Phase 46 can prepare the plan, but execution waits for the approval-gated invocation layer."
      end
    end
  end
end
