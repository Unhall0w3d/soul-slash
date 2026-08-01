# frozen_string_literal: true

require_relative "conversation_request_shape"
require_relative "skill_registry"
require_relative "skill_studio_service"

module SoulCore
  class SkillStudioChatControls
    MAX_RECORDS = 100
    REQUEST_PATTERNS = [
      /\A\s*(?:please\s+)?(?:show|list|inspect|open|explain)\s+(?:the\s+)?skill studio(?:\s+(?:inventory|status|queue|proposals?|beta(?:\s+skills?)?|production(?:\s+skills?)?))?\s*[?.!]*\z/i,
      /\A\s*(?:please\s+)?(?:show|list|inspect|explain)\s+(?:the\s+)?(?:skill studio\s+)?(?:proposals?|beta skills?|beta candidates?|production skills?)\s*[?.!]*\z/i,
      /\A\s*what(?:'s|\s+is)\s+(?:in|pending\s+in)\s+(?:the\s+)?skill studio\s*[?.!]*\z/i,
      /\A\s*(?:show|inspect|explain|what\s+stage\s+is)\s+(?:the\s+)?skill studio\s+(?:proposal|beta)\s+.+\z/i,
      /\A\s*(?:approve|build|run|try|promote|close|delete|reject)\b.+\b(?:skill studio|beta skill|beta candidate)\b.+\z/i
    ].freeze

    MUTATION_PATTERN = /\A\s*(?:approve|build|run|try|promote|close|delete|reject)\b/i

    def initialize(root: Dir.pwd, studio: nil, registry: nil)
      expanded_root = File.expand_path(root)
      @studio = studio || SkillStudioService.new(root: expanded_root)
      @registry = registry || SkillRegistry.new(path: File.join(expanded_root, "Soul", "skills", "registry.yaml"))
    end

    def match?(message)
      text = message.to_s.strip
      return true if text.match?(MUTATION_PATTERN) && text.match?(REQUEST_PATTERNS.last)

      ConversationRequestShape.new.request?(text) && REQUEST_PATTERNS.any? { |pattern| text.match?(pattern) }
    end

    def respond(message)
      text = message.to_s.strip
      return protected_action_response if text.match?(MUTATION_PATTERN)
      return render_production if text.match?(/\bproduction skills?\b/i)
      return render_proposals if text.match?(/\b(?:show|list)\b.*\bproposals?\b/i)
      return render_betas if text.match?(/\b(?:show|list)\b.*\bbeta(?:\s+(?:skills?|candidates?))?\b/i)

      detail = requested_detail(text)
      return render_detail(detail) if detail
      token = requested_token(text)
      return render_missing(token) if token

      render_overview
    rescue RuntimeError, KeyError => error
      [
        "Skill Studio inventory is unavailable.",
        "Failure: #{error.class}",
        "No proposal, Beta, production, or gate state was changed.",
        "Lifecycle: failed. Mutation: none."
      ].join("\n")
    end

    private

    def render_overview
      proposals = proposal_records
      betas = beta_records
      production = production_records
      lines = [
        "Skill Studio inventory",
        "",
        "Proposals: #{proposals.length}",
        "Beta skills: #{betas.length}",
        "Production skills: #{production.length}"
      ]
      lines.concat(stage_lines(proposals))
      lines.concat([
        "",
        "This is a current read-only projection. Ask to list proposals, Beta skills, production skills, or inspect one exact proposal or Beta.",
        authority_boundary,
        "Lifecycle: complete. Mutation: none."
      ])
      lines.join("\n")
    end

    def render_proposals
      records = proposal_records
      lines = ["Skill Studio proposals", "Count: #{records.length}", ""]
      if records.empty?
        lines << "- none"
      else
        records.each do |record|
          lines << "- #{record.fetch('title')}"
          lines << "  ID: #{record.fetch('proposal_id')}"
          lines << "  Stage: #{record.fetch('stage')}"
          lines << "  Proposal gate: #{record.fetch('proposal_gate')}"
          lines << "  Beta present: #{record.fetch('beta_present')}"
        end
      end
      lines.concat(["", authority_boundary, "Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_betas
      records = beta_records
      lines = ["Skill Studio Beta skills", "Count: #{records.length}", ""]
      if records.empty?
        lines << "- none"
      else
        records.each do |record|
          lines << "- #{record.fetch('beta_id')}"
          lines << "  Maturity: #{record['maturity'] || 'unknown'}"
          lines << "  Runnable: #{record.fetch('runnable', false)}"
          lines << "  Test state: #{record['test_status'] || record['test_state'] || 'not recorded'}"
          lines << "  Promotion state: #{record['beta_gate'] || 'not ready'}"
        end
      end
      lines.concat(["", authority_boundary, "Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_production
      records = production_records
      lines = ["Skill Studio production skills", "Count: #{records.length}", ""]
      records.each do |skill_id, record|
        status = record["status"].to_s.empty? ? "available" : record["status"]
        lines << "- #{skill_id} — #{status}; #{record['risk'] || 'unclassified'}"
      end
      lines.concat(["", "This is registry inventory only; listing it invokes nothing.", authority_boundary, "Lifecycle: complete. Mutation: none."])
      lines.join("\n")
    end

    def render_detail(detail)
      kind, record = detail
      return render_proposal_detail(record) if kind == :proposal

      render_beta_detail(record)
    end

    def render_proposal_detail(record)
      [
        "Skill Studio proposal",
        "Title: #{record.fetch('title')}",
        "ID: #{record.fetch('proposal_id')}",
        "Stage: #{record.fetch('stage')}",
        "Proposal gate: #{record.fetch('proposal_gate')}",
        "Beta gate: #{record.fetch('beta_gate')}",
        "Beta present: #{record.fetch('beta_present')}",
        "Linked skill: #{record['linked_skill_id'] || 'none'}",
        "Production registered: #{record.fetch('production_registered')}",
        "Human review required: #{record.fetch('human_review_required')}",
        "",
        authority_boundary,
        "Lifecycle: complete. Mutation: none."
      ].join("\n")
    end

    def render_beta_detail(record)
      [
        "Skill Studio Beta",
        "ID: #{record.fetch('beta_id')}",
        "Description: #{record['description'] || 'not recorded'}",
        "Maturity: #{record['maturity'] || 'unknown'}",
        "Runnable: #{record.fetch('runnable', false)}",
        "Risk: #{record['risk'] || 'unclassified'}",
        "Test state: #{record['test_status'] || record['test_state'] || 'not recorded'}",
        "Promotion state: #{record['beta_gate'] || 'not ready'}",
        "",
        authority_boundary,
        "Lifecycle: complete. Mutation: none."
      ].join("\n")
    end

    def requested_detail(text)
      token = requested_token(text)
      return nil unless token

      normalized = token.strip.downcase
      proposal = proposal_records.find do |record|
        record.fetch("proposal_id").downcase == normalized || record.fetch("title").downcase == normalized
      end
      return [:proposal, proposal] if proposal

      beta = beta_records.find { |record| record.fetch("beta_id").downcase == normalized }
      return [:beta, beta] if beta

      nil
    end

    def requested_token(text)
      text[/\b(?:proposal|beta)\s+(.+?)\s*[?.!]*\z/i, 1]&.strip
    end

    def render_missing(token)
      [
        "Skill Studio item was not found.",
        "Requested identifier: #{token}",
        "Ask to list Skill Studio proposals or Beta skills and use one exact current ID or proposal title.",
        "Lifecycle: awaiting_input. Mutation: none."
      ].join("\n")
    end

    def stage_lines(records)
      return ["Pending proposal stages: none."] if records.empty?

      counts = records.group_by { |record| record.fetch("stage") }.transform_values(&:length)
      ["Pending proposal stages: #{counts.sort.map { |stage, count| "#{stage}=#{count}" }.join(', ')}."]
    end

    def proposal_records
      result = @studio.proposals(limit: MAX_RECORDS)
      result.fetch("data").fetch("records")
    end

    def beta_records
      result = @studio.betas(limit: MAX_RECORDS)
      result.fetch("data").fetch("records")
    end

    def production_records
      @registry.list.sort.to_h
    end

    def protected_action_response
      [
        "Skill Studio action remains protected.",
        "I can inspect the current proposal, Beta, test, and production state, but I cannot authorize or execute approval, build, trial, promotion, closeout, or deletion through this conversational read.",
        "Use the exact reviewed action in Skill Studio for the appropriate gate.",
        "Lifecycle: blocked_for_human_review. Mutation: none."
      ].join("\n")
    end

    def authority_boundary
      "Authority: proposal approval, Beta build or trial, promotion, closeout, and deletion remain exact Operator-controlled Skill Studio actions."
    end
  end
end
