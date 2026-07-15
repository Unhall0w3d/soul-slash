# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "time"

require_relative "conversation_artifact_inbox_store"
require_relative "conversation_artifact_store"
require_relative "skill_registry"
require_relative "skill_studio_service"

module SoulCore
  class CapabilityGapIntakeService
    PROPOSALS_ROOT = "Soul/proposals/skills"
    MAX_REQUEST_BYTES = 4 * 1024
    MAX_EVENTS = 1_000
    MAX_EVENTS_BYTES = 1024 * 1024
    STOP_WORDS = %w[
      about after again also and are build can could create do does for from have help how into
      its make need please run should that the their them then there these they this to use want
      what when where which with would you your soul
    ].freeze

    def initialize(root: Dir.pwd, clock: -> { Time.now }, skill_registry: nil, skill_studio: nil, artifact_store: nil, inbox_store: nil)
      @root = File.expand_path(root)
      @clock = clock
      @skill_registry = skill_registry || SkillRegistry.new(path: File.join(@root, "Soul", "skills", "registry.yaml"))
      @skill_studio = skill_studio || SkillStudioService.new(root: @root, clock: clock)
      @artifact_store = artifact_store || ConversationArtifactStore.new(root: @root, clock: clock)
      @inbox_store = inbox_store || ConversationArtifactInboxStore.new(root: @root, clock: clock)
    end

    def intake(chat_id:, request:, classification:, reason:, capability: nil)
      normalized_chat = require_chat_id(chat_id)
      normalized_request = require_request(request)
      normalized_classification = classification.to_s.strip
      raise ArgumentError, "gap classification is required" if normalized_classification.empty?

      coverage = coverage_for(normalized_request)
      return covered(coverage) if coverage

      fingerprint = fingerprint_for(normalized_request, normalized_classification, capability)
      directory = find_existing(fingerprint)
      created = directory.nil?
      directory ||= create_intake(
        chat_id: normalized_chat,
        request: normalized_request,
        classification: normalized_classification,
        reason: reason,
        capability: capability,
        fingerprint: fingerprint
      )
      event_recorded = append_event(directory, chat_id: normalized_chat, request: normalized_request, classification: normalized_classification)
      delivery = deliver(directory, normalized_chat)

      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "mutation" => created ? "capability_gap_intake_created" : "capability_gap_intake_reused",
        "status" => created ? "created" : "deduplicated",
        "proposal_id" => File.basename(directory),
        "proposal_path" => relative(directory),
        "gap_fingerprint" => fingerprint,
        "artifact_id" => delivery["artifact_id"],
        "delivery_id" => delivery["delivery_id"],
        "delivery_state" => delivery["delivery_state"],
        "event_recorded" => event_recorded,
        "cloud_provider_invoked" => false,
        "implementation_started" => false,
        "human_proposal_review_required" => true
      }
    rescue ArgumentError => error
      failure("awaiting_input", error.message)
    rescue RuntimeError => error
      failure("blocked_for_human_review", error.message)
    rescue StandardError => error
      failure("failed", "capability-gap intake failed safely: #{error.class}")
    end

    private

    def coverage_for(request)
      request_tokens = tokens(request)
      production = @skill_registry.list.filter_map do |skill_id, definition|
        next unless coverage_match?(request_tokens, "#{skill_id} #{definition['description']}")
        { "kind" => "production_skill", "skill_id" => skill_id, "description" => definition["description"] }
      end.first
      return production if production

      beta_result = @skill_studio.betas(limit: SkillStudioService::MAX_RECORDS)
      Array(beta_result.dig("data", "records")).find do |record|
        record["runnable"] == true && coverage_match?(request_tokens, "#{record['beta_id']} #{record['description']}")
      end&.then do |record|
        { "kind" => "beta_skill", "skill_id" => record["beta_id"], "description" => record["description"] }
      end
    end

    def coverage_match?(request_tokens, candidate)
      candidate_tokens = tokens(candidate)
      overlap = request_tokens & candidate_tokens
      overlap.length >= 2 || overlap.any? { |token| token.length >= 9 }
    end

    def covered(coverage)
      {
        "ok" => true,
        "lifecycle_state" => "complete",
        "mutation" => "none",
        "status" => "covered",
        "coverage" => coverage,
        "proposal_created" => false,
        "cloud_provider_invoked" => false
      }
    end

    def create_intake(chat_id:, request:, classification:, reason:, capability:, fingerprint:)
      timestamp = @clock.call.utc.strftime("%Y%m%dT%H%M%SZ")
      label = capability_value(capability, "label") || request
      proposal_id = "#{timestamp}-gap-#{slug(label)}"
      directory = File.join(full(PROPOSALS_ROOT), proposal_id)
      suffix = 1
      while File.exist?(directory)
        suffix += 1
        directory = File.join(full(PROPOSALS_ROOT), "#{proposal_id}-#{suffix}")
      end
      FileUtils.mkdir_p(directory)

      metadata = {
        "schema_version" => "soul.skill_proposal.v2",
        "artifact_type" => "skill_proposal",
        "purpose" => "capability_gap_intake",
        "created_at" => now,
        "title" => "Capability gap: #{title(label)}",
        "output_mode" => "local_intake_for_human_review",
        "direct_repo_mutation" => false,
        "human_review_required" => true,
        "provider" => nil,
        "model" => nil,
        "cloud_provider_invoked" => false,
        "data_class" => "local_private_conversation_request",
        "secrets_included" => false,
        "private_repo_content_included" => false,
        "user_memory_included" => false,
        "origin" => {
          "kind" => "capability_gap_intake",
          "chat_id" => chat_id,
          "classification" => classification,
          "reason" => reason.to_s[0, 500],
          "capability_id" => capability_value(capability, "id"),
          "capability_label" => capability_value(capability, "label")
        }.compact,
        "request_summary" => request,
        "gap_fingerprint" => fingerprint,
        "status" => "awaiting_proposal_review"
      }
      write_json(File.join(directory, "metadata.json"), metadata)
      File.write(File.join(directory, "proposal.md"), proposal_markdown(metadata, request))
      File.write(File.join(directory, "review_checklist.md"), review_checklist)
      File.write(File.join(directory, "sources.md"), "No external source or cloud provider was used. This intake was created locally from the originating conversation request.\n")
      write_json(File.join(directory, "studio_state.json"), {
        "schema_version" => "soul.skill_studio.v1",
        "intake" => { "status" => "awaiting_human_triage", "created_at" => now },
        "proposal_gate" => { "status" => "awaiting_review" },
        "beta_gate" => { "status" => "not_ready" }
      })
      directory
    rescue StandardError
      FileUtils.remove_entry_secure(directory) if directory && Dir.exist?(directory) && inside?(directory, full(PROPOSALS_ROOT))
      raise
    end

    def proposal_markdown(metadata, request)
      origin = metadata.fetch("origin")
      <<~MARKDOWN
        # Skill Proposal Intake: #{metadata.fetch("title").sub("Capability gap: ", "")}

        ## Intake status

        This is a local capability-gap intake, not a completed skill brief or implementation.

        ## Originating request

        #{request}

        ## Gap classification

        - Classification: `#{origin.fetch("classification")}`
        - Reason: #{origin.fetch("reason")}
        #{"- Declared capability: `#{origin['capability_id']}` — #{origin['capability_label']}" if origin["capability_id"]}

        ## Coverage checks

        Soul checked the registered production-skill inventory and runnable Beta inventory before creating this intake. No matching executable coverage was found.

        ## Proposed outcome

        Define a bounded Soul skill that can satisfy the originating request without weakening approval, privacy, memory, persistence, or review boundaries.

        ## Questions for proposal development

        - What exact user-visible outcome is required?
        - What inputs, outputs, configuration, permissions, and providers are necessary?
        - What risk class and confirmation behavior apply?
        - What must always happen, and what must never happen?
        - Which deterministic tests and local behavioral evals demonstrate usefulness?
        - What failure states, diagnostics, and rollback behavior are required?

        ## Lifecycle

        `awaiting_input` → `blocked_for_human_review` → Human Gate 1 → Beta implementation → testing and review → Human Gate 2 → later explicit promotion workflow.

        ## Cloud assistance

        No cloud provider was invoked. Optional Mistral drafting or review must be separately disclosed and human-initiated from Skill Studio.

        ## Current boundaries

        - No code has been generated or applied.
        - No Beta or production skill has been registered.
        - No implementation, execution, promotion, or merge has started.
        - This intake cannot approve itself.
      MARKDOWN
    end

    def review_checklist
      <<~MARKDOWN
        # Capability-Gap Intake Review

        - [ ] The originating request is represented accurately.
        - [ ] This is a genuine missing capability, not configuration, permission, policy, ambiguity, or transient failure.
        - [ ] No production skill already covers the request.
        - [ ] No runnable Beta already covers the request.
        - [ ] Scope and user-visible outcome are bounded.
        - [ ] Required inputs, outputs, permissions, providers, and privacy are identified.
        - [ ] Lifecycle and failure behavior are explicit.
        - [ ] Deterministic tests and local behavioral evals are identified.
        - [ ] Human Gate 1 is required before Beta implementation.
      MARKDOWN
    end

    def find_existing(fingerprint)
      root = full(PROPOSALS_ROOT)
      return nil unless Dir.exist?(root)
      Dir.children(root).sort.reverse.each do |name|
        next unless name.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,199}\z/)
        directory = File.join(root, name)
        metadata = read_json(File.join(directory, "metadata.json"))
        next unless metadata.is_a?(Hash) && metadata["purpose"] == "capability_gap_intake"
        return directory if metadata["gap_fingerprint"] == fingerprint && metadata["status"] != "closed"
      end
      nil
    end

    def append_event(directory, chat_id:, request:, classification:)
      path = File.join(directory, "gap_events.jsonl")
      return false if File.exist?(path) && File.size(path) >= MAX_EVENTS_BYTES
      count = File.exist?(path) ? File.foreach(path).take(MAX_EVENTS + 1).length : 0
      return false if count >= MAX_EVENTS
      event = { "timestamp" => now, "chat_id" => chat_id, "classification" => classification, "request" => request }
      File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) { |file| file.puts(JSON.generate(event)) }
      true
    end

    def deliver(directory, chat_id)
      delivery_path = File.join(directory, "delivery.json")
      delivery_state = read_json(delivery_path) || {}
      artifact = @artifact_store.find(delivery_state["artifact_id"])
      unless artifact
        artifact = @artifact_store.register(
          path: File.join(directory, "proposal.md"),
          title: "Skill proposal intake: #{File.basename(directory).sub(/\A\d{8}T\d{6}Z-gap-/, "")}",
          kind: "document",
          privacy: "local_private",
          source: { "kind" => "skill", "skill_id" => "capability_gap.intake" },
          chat_id: chat_id
        )
        delivery_state["artifact_id"] = artifact.fetch("artifact_id")
      end
      artifact = @artifact_store.attach(artifact.fetch("artifact_id"), chat_id: chat_id)
      delivery = @inbox_store.deliver(
        artifact: artifact,
        originating_chat_id: chat_id,
        recipient_chat_id: chat_id,
        reason: "capability_gap_proposal_intake"
      )
      delivery_state["last_delivery_id"] = delivery.fetch("delivery_id")
      write_json(delivery_path, delivery_state)
      { "artifact_id" => artifact.fetch("artifact_id"), "delivery_id" => delivery.fetch("delivery_id"), "delivery_state" => delivery.fetch("latest_delivery_state") }
    rescue StandardError => error
      { "artifact_id" => delivery_state && delivery_state["artifact_id"], "delivery_id" => nil, "delivery_state" => "failed", "reason" => "#{error.class}: #{error.message}" }
    end

    def fingerprint_for(request, classification, capability)
      identity = capability_value(capability, "id")
      identity = tokens(request).first(16).join("-") if identity.to_s.empty?
      Digest::SHA256.hexdigest([classification, identity].join("\0"))
    end

    def tokens(value)
      value.to_s.downcase.scan(/[a-z0-9]+/).select { |token| token.length >= 4 && !STOP_WORDS.include?(token) }.uniq.first(40)
    end

    def slug(value)
      result = tokens(value).first(8).join("-")
      result.empty? ? "missing-capability" : result[0, 80]
    end

    def title(value)
      value.to_s.strip.gsub(/\s+/, " ")[0, 120]
    end

    def capability_value(capability, key)
      return nil if capability.nil?
      return capability[key] || capability[key.to_sym] if capability.respond_to?(:[])
      capability.public_send(key) if capability.respond_to?(key)
    end

    def require_chat_id(value)
      chat_id = value.to_s.strip
      raise ArgumentError, "valid originating chat ID is required" unless chat_id.match?(/\Achat_[A-Za-z0-9_.-]+\z/)
      chat_id
    end

    def require_request(value)
      request = value.to_s.strip
      raise ArgumentError, "originating request is required" if request.empty?
      raise ArgumentError, "originating request exceeds #{MAX_REQUEST_BYTES} bytes" if request.bytesize > MAX_REQUEST_BYTES
      request
    end

    def write_json(path, value)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, "w", 0o600) { |file| file.write(JSON.pretty_generate(value)); file.write("\n") }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def read_json(path)
      JSON.parse(File.read(path, 128 * 1024))
    rescue Errno::ENOENT, JSON::ParserError, ArgumentError
      nil
    end

    def inside?(path, boundary)
      expanded = File.expand_path(path)
      root = File.expand_path(boundary)
      expanded == root || expanded.start_with?("#{root}#{File::SEPARATOR}")
    end

    def full(relative_path)
      File.expand_path(relative_path, @root)
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    end

    def now
      @clock.call.utc.iso8601
    end

    def failure(lifecycle, reason)
      { "ok" => false, "lifecycle_state" => lifecycle, "mutation" => "none", "reason" => reason, "cloud_provider_invoked" => false, "implementation_started" => false }
    end
  end
end
