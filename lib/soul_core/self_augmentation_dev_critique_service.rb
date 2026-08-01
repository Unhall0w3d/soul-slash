# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "dev_worker_service"

module SoulCore
  class SelfAugmentationDevCritiqueService
    SCHEMA = "soul.self_augmentation.dev_critique.v1"
    PROPOSALS_ROOT = File.join("Soul", "augmentation", "proposals")
    CRITIQUES_DIRECTORY = "dev_critiques"
    MAX_PROPOSAL_BYTES = 64 * 1024
    MAX_RECORD_BYTES = 384 * 1024
    MAX_RECORDS = 50
    MAX_STRING_BYTES = 4 * 1024
    DIMENSIONS = %w[scope compatibility migration rollback verification privacy authority_boundary].freeze
    SENSITIVE_KEY = /(?:password|passwd|secret|credential|authorization|cookie|private[_-]?key|access[_-]?token|api[_-]?key)/i

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc }, proposal_source:, dev_worker: nil)
      @root = File.expand_path(root)
      @clock = clock
      @proposal_source = proposal_source
      @dev_worker = dev_worker || DevWorkerService.new(root: @root, clock: -> { @clock.call.utc })
    end

    def preview(proposal_id:)
      prepared = prepared_request(proposal_id)
      return prepared if envelope?(prepared)

      worker_preview = @dev_worker.preview(request: prepared.fetch("request"))
      return worker_preview unless worker_preview["ok"]

      worker = worker_preview.fetch("data")
      success({
        "schema_version" => SCHEMA,
        "proposal_id" => prepared.fetch("proposal_id"),
        "proposal_sha256" => prepared.fetch("proposal_sha256"),
        "source_head" => prepared.fetch("proposal").fetch("head"),
        "expected_digest" => worker.fetch("expected_digest"),
        "confirmation_phrase" => worker.fetch("confirmation_phrase"),
        "model" => worker.fetch("model"),
        "advisory_only" => true,
        "gate_a1_authorized" => false,
        "worktree_creation_authorized" => false,
        "follow_on_execution_authorized" => false
      })
    rescue StandardError => error
      failed("Self Augmentation Dev critique preview failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def execute(proposal_id:, confirmation:, expected_digest:, on_progress: nil)
      prepared = prepared_request(proposal_id)
      return prepared if envelope?(prepared)

      worker_result = @dev_worker.execute(
        request: prepared.fetch("request"),
        confirmation: confirmation,
        expected_digest: expected_digest,
        on_progress: on_progress
      )
      return worker_result unless worker_result["ok"]

      candidate = worker_result.dig("data", "candidate")
      validation = validate_candidate(candidate, prepared.fetch("evidence_refs"))
      return failed(validation) if validation

      record = build_record(prepared, candidate, worker_result.dig("data", "provider_receipt"))
      created = persist_record(record)
      success({
        "schema_version" => SCHEMA,
        "critique" => public_record(record),
        "packet" => packet_relative_path(record),
        "human_review_required" => true,
        "gate_a1_authorized" => false,
        "worktree_creation_authorized" => false,
        "follow_on_execution_authorized" => false,
        "idempotent_replay" => !created
      }, mutation: created ? "self_augmentation_dev_critique_created" : "none")
    rescue Interrupt
      canceled("Self Augmentation Dev critique was canceled before completion")
    rescue StandardError => error
      failed("Self Augmentation Dev critique failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def inventory(limit: MAX_RECORDS)
      maximum = Integer(limit).clamp(1, MAX_RECORDS)
      records = proposal_ids.flat_map { |proposal_id| critique_ids(proposal_id).filter_map { |id| read_record(proposal_id, id, expose: false) } }
      records = records.sort_by { |record| record.fetch("created_at", "") }.reverse.first(maximum)
      success({ "records" => records.map { |record| public_record(record) }, "count" => records.length, "limit" => maximum })
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("Self Augmentation Dev critique inventory failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    private

    def prepared_request(proposal_id)
      source = @proposal_source.proposal(proposal_id: proposal_id.to_s)
      return source unless source["ok"]

      proposal = project(source.dig("data", "proposal"))
      encoded = JSON.generate(proposal)
      return blocked("augmentation proposal exceeds #{MAX_PROPOSAL_BYTES} bytes") if encoded.bytesize > MAX_PROPOSAL_BYTES
      evidence_refs = leaf_paths(proposal)
      return blocked("augmentation proposal contains no eligible scalar references") if evidence_refs.empty?

      proposal_sha256 = Digest::SHA256.hexdigest(encoded)
      context = JSON.pretty_generate({
        "critique_contract" => {
          "output_is_advisory_only" => true,
          "do_not_classify_safety_or_risk" => true,
          "do_not_approve_or_reject_gate_a1" => true,
          "do_not_propose_allowed_files_code_patches_commands_or_implementation_steps" => true,
          "do_not_create_a_worktree_or_authorize_follow_on_actions" => true,
          "cite_only_eligible_proposal_refs" => true,
          "each_strength_or_concern_must_use_one_directly_supporting_ref" => true
        },
        "eligible_proposal_refs" => evidence_refs,
        "augmentation_proposal" => proposal
      })
      {
        "proposal_id" => proposal.fetch("proposal_id"),
        "proposal" => proposal,
        "proposal_sha256" => proposal_sha256,
        "evidence_refs" => evidence_refs,
        "request" => {
          "schema_version" => DevWorkerService::REQUEST_SCHEMA,
          "request_id" => "self_augmentation_#{proposal.fetch('proposal_id')}_#{proposal_sha256[0, 12]}",
          "purpose" => "Critique the exact Self Augmentation proposal for human revision and Gate A1 review preparation only",
          "task_kind" => "critique",
          "repository_relative_paths" => [],
          "parent_supplied_context" => context,
          "expected_context_sha256" => Digest::SHA256.hexdigest(context),
          "output_schema" => output_schema(evidence_refs),
          "timeout_seconds" => 300
        }
      }
    rescue KeyError, JSON::GeneratorError => error
      failed("augmentation proposal is invalid: #{error.message}"[0, 1_000])
    end

    def output_schema(evidence_refs)
      cited_item = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[statement evidence_ref],
        "properties" => {
          "statement" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
          "evidence_ref" => { "type" => "string", "enum" => evidence_refs }
        }
      }
      {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[summary strengths concerns unknowns revision_questions],
        "properties" => {
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 2_000 },
          "strengths" => { "type" => "array", "maxItems" => 8, "items" => cited_item },
          "concerns" => {
            "type" => "array", "maxItems" => 12,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[dimension statement evidence_ref],
              "properties" => cited_item.fetch("properties").merge("dimension" => { "type" => "string", "enum" => DIMENSIONS })
            }
          },
          "unknowns" => {
            "type" => "array", "maxItems" => 12,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[question reason],
              "properties" => {
                "question" => { "type" => "string", "minLength" => 1, "maxLength" => 800 },
                "reason" => { "type" => "string", "minLength" => 1, "maxLength" => 800 }
              }
            }
          },
          "revision_questions" => { "type" => "array", "maxItems" => 8, "items" => { "type" => "string", "minLength" => 1, "maxLength" => 800 } }
        }
      }
    end

    def validate_candidate(candidate, evidence_refs)
      return "Dev critique result is not a structured object" unless candidate.is_a?(Hash)
      return "Dev critique fields are invalid" unless candidate.keys.sort == %w[concerns revision_questions strengths summary unknowns]
      return "Dev critique summary is invalid" unless bounded_string?(candidate["summary"], 2_000)
      return "Dev critique strengths are invalid" unless valid_cited_items?(candidate["strengths"], evidence_refs, maximum: 8)
      concerns = candidate["concerns"]
      return "Dev critique concerns are invalid" unless concerns.is_a?(Array) && concerns.length <= 12
      concerns.each do |concern|
        return "Dev critique concern shape is invalid" unless concern.is_a?(Hash) && concern.keys.sort == %w[dimension evidence_ref statement]
        return "Dev critique concern dimension is invalid" unless DIMENSIONS.include?(concern["dimension"])
        return "Dev critique concern statement is invalid" unless bounded_string?(concern["statement"], 1_000)
        return "Dev critique concern evidence reference is invalid" unless evidence_refs.include?(concern["evidence_ref"])
      end
      unknowns = candidate["unknowns"]
      return "Dev critique unknowns are invalid" unless unknowns.is_a?(Array) && unknowns.length <= 12
      unknowns.each do |unknown|
        return "Dev critique unknown shape is invalid" unless unknown.is_a?(Hash) && unknown.keys.sort == %w[question reason]
        return "Dev critique unknown text is invalid" unless bounded_string?(unknown["question"], 800) && bounded_string?(unknown["reason"], 800)
      end
      questions = candidate["revision_questions"]
      return "Dev critique revision questions are invalid" unless questions.is_a?(Array) && questions.length <= 8 && questions.all? { |value| bounded_string?(value, 800) }
      nil
    end

    def valid_cited_items?(items, evidence_refs, maximum:)
      items.is_a?(Array) && items.length <= maximum && items.all? do |item|
        item.is_a?(Hash) && item.keys.sort == %w[evidence_ref statement] && bounded_string?(item["statement"], 1_000) && evidence_refs.include?(item["evidence_ref"])
      end
    end

    def build_record(prepared, candidate, provider_receipt)
      digest = Digest::SHA256.hexdigest(JSON.generate({ "proposal_sha256" => prepared.fetch("proposal_sha256"), "candidate" => candidate }))
      {
        "schema_version" => SCHEMA,
        "critique_id" => "augmentation_critique_#{digest[0, 20]}",
        "created_at" => @clock.call.utc.iso8601,
        "proposal_id" => prepared.fetch("proposal_id"),
        "proposal_sha256" => prepared.fetch("proposal_sha256"),
        "proposal" => prepared.fetch("proposal"),
        "candidate" => candidate,
        "provider_receipt" => provider_receipt,
        "advisory_only" => true,
        "human_review_required" => true,
        "gate_a1_authorized" => false,
        "worktree_creation_authorized" => false,
        "follow_on_execution_authorized" => false
      }
    end

    def persist_record(record)
      root = critique_root(record.fetch("proposal_id"), create: true)
      directory = File.join(root, record.fetch("critique_id"))
      if File.directory?(directory) && !File.symlink?(directory)
        existing = read_record(record.fetch("proposal_id"), record.fetch("critique_id"), expose: false)
        raise "existing critique packet does not match candidate" unless existing && existing.fetch("proposal_sha256") == record.fetch("proposal_sha256") && existing.fetch("candidate") == record.fetch("candidate")
        return false
      end
      raise "critique packet target is unsafe" if File.exist?(directory) || File.symlink?(directory)
      staging = File.join(root, ".#{record.fetch('critique_id')}.tmp-#{Process.pid}")
      raise "critique packet staging target is unsafe" if File.exist?(staging) || File.symlink?(staging)
      Dir.mkdir(staging, 0o700)
      atomic_write(File.join(staging, "record.json"), JSON.pretty_generate(record) + "\n")
      atomic_write(File.join(staging, "REVIEW.md"), review_markdown(record))
      File.rename(staging, directory)
      true
    rescue StandardError
      FileUtils.remove_dir(staging) if defined?(staging) && File.directory?(staging) && !File.symlink?(staging)
      raise
    end

    def public_record(record)
      result = record.slice("schema_version", "critique_id", "created_at", "proposal_id", "proposal_sha256", "candidate", "provider_receipt", "advisory_only", "human_review_required", "gate_a1_authorized", "worktree_creation_authorized", "follow_on_execution_authorized")
      candidate = project(result.fetch("candidate"))
      (candidate.fetch("strengths", []) + candidate.fetch("concerns", [])).each do |item|
        value = evidence_value(record.fetch("proposal"), item.fetch("evidence_ref"))
        item["evidence_value"] = value.is_a?(String) ? value : JSON.generate(value)
      end
      result.merge("candidate" => candidate)
    end

    def read_record(proposal_id, critique_id, expose: true)
      return nil unless proposal_id.to_s.match?(/\Aaug_[a-f0-9]{16}\z/) && critique_id.to_s.match?(/\Aaugmentation_critique_[a-f0-9]{20}\z/)
      directory = File.join(critique_root(proposal_id, create: false), critique_id.to_s)
      path = File.join(directory, "record.json")
      return nil unless File.directory?(directory) && !File.symlink?(directory) && File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      return nil unless record["schema_version"] == SCHEMA && record["proposal_id"] == proposal_id && record["critique_id"] == critique_id
      expose ? public_record(record) : record
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def proposal_ids
      root = File.join(@root, PROPOSALS_ROOT)
      return [] unless File.directory?(root) && !File.symlink?(root)
      Dir.children(root).grep(/\Aaug_[a-f0-9]{16}\z/).sort
    end

    def critique_ids(proposal_id)
      root = critique_root(proposal_id, create: false)
      return [] unless File.directory?(root) && !File.symlink?(root)
      Dir.children(root).grep(/\Aaugmentation_critique_[a-f0-9]{20}\z/).sort
    end

    def critique_root(proposal_id, create:)
      raise "proposal ID is invalid" unless proposal_id.to_s.match?(/\Aaug_[a-f0-9]{16}\z/)
      proposal_directory = File.join(@root, PROPOSALS_ROOT, proposal_id.to_s)
      raise "proposal directory is unsafe" unless File.directory?(proposal_directory) && !File.symlink?(proposal_directory)
      root = File.join(proposal_directory, CRITIQUES_DIRECTORY)
      if create
        raise "critique root is unsafe" if File.symlink?(root)
        Dir.mkdir(root, 0o700) unless File.exist?(root)
        raise "critique root is not a directory" unless File.directory?(root)
      end
      root
    end

    def review_markdown(record)
      <<~MD
        # Self Augmentation Dev Critique Review

        - Critique: `#{record.fetch("critique_id")}`
        - Proposal: `#{record.fetch("proposal_id")}`
        - Proposal SHA-256: `#{record.fetch("proposal_sha256")}`
        - Advisory only: **yes**
        - Gate A1 authorized: **no**
        - Worktree creation authorized: **no**
        - Follow-on execution authorized: **no**

        ## Human checklist

        - [ ] Each strength and concern is supported by its displayed proposal field.
        - [ ] Unknowns remain questions rather than model-invented facts.
        - [ ] No safety or risk classification was delegated to the model.
        - [ ] No allowed-file list, code, patch, command, or implementation plan was introduced.
        - [ ] Gate A1 remains a separate exact human decision.
      MD
    end

    def packet_relative_path(record)
      File.join(PROPOSALS_ROOT, record.fetch("proposal_id"), CRITIQUES_DIRECTORY, record.fetch("critique_id"))
    end

    def project(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, out|
          next if key.match?(SENSITIVE_KEY)
          child = value.key?(key) ? value[key] : value[key.to_sym]
          out[key] = project(child)
        end
      when Array then value.first(100).map { |child| project(child) }
      when String then bounded_utf8(value)
      when Integer, Float, TrueClass, FalseClass, NilClass then value
      else bounded_utf8(value.to_s)
      end
    end

    def leaf_paths(value, path = "")
      case value
      when Hash then value.flat_map { |key, child| leaf_paths(child, "#{path}/#{key.to_s.gsub('~', '~0').gsub('/', '~1')}") }
      when Array then value.each_with_index.flat_map { |child, index| leaf_paths(child, "#{path}/#{index}") }
      else [path.empty? ? "/" : path]
      end
    end

    def evidence_value(value, pointer)
      pointer.to_s.split("/").drop(1).reduce(value) do |cursor, token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        cursor.is_a?(Hash) ? cursor.fetch(key) : cursor.fetch(Integer(key, 10))
      end
    end

    def atomic_write(path, content)
      raise "critique artifact already exists" if File.exist?(path) || File.symlink?(path)
      raise "critique artifact exceeds #{MAX_RECORD_BYTES} bytes" if content.bytesize > MAX_RECORD_BYTES
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.file?(temporary)
    end

    def bounded_utf8(value)
      return "[invalid encoding removed]" unless value.valid_encoding?
      value.encode(Encoding::UTF_8).byteslice(0, MAX_STRING_BYTES).to_s.scrub
    rescue EncodingError
      "[invalid encoding removed]"
    end

    def bounded_string?(value, maximum) = value.is_a?(String) && !value.strip.empty? && value.bytesize <= maximum && value.valid_encoding?
    def envelope?(value) = value.is_a?(Hash) && value.key?("lifecycle_state")
    def success(data, mutation: "none") = { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    def awaiting(reason) = { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    def blocked(reason) = { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "mutation" => "none" }
    def failed(reason) = { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "mutation" => "none" }
    def canceled(reason) = { "ok" => false, "lifecycle_state" => "canceled", "reason" => reason, "mutation" => "none" }
  end
end
