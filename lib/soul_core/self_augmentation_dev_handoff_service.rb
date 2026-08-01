# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "dev_worker_service"

module SoulCore
  class SelfAugmentationDevHandoffService
    SCHEMA = "soul.self_augmentation.dev_handoff.v1"
    EXPERIMENTS_ROOT = File.join("Soul", "augmentation", "experiments")
    DEV_HANDOFFS_DIRECTORY = "dev_handoffs"
    MAX_SOURCE_BYTES = 192 * 1024
    MAX_RECORD_BYTES = 512 * 1024
    MAX_RECORDS = 50
    MAX_STRING_BYTES = 4 * 1024
    SENSITIVE_KEY = /(?:password|passwd|secret|credential|authorization|cookie|private[_-]?key|access[_-]?token|api[_-]?key)/i

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc }, experiment_source:, dev_worker: nil)
      @root = File.expand_path(root)
      @clock = clock
      @experiment_source = experiment_source
      @dev_worker = dev_worker || DevWorkerService.new(root: @root, clock: -> { @clock.call.utc })
    end

    def preview(experiment_id:)
      prepared = prepared_request(experiment_id)
      return prepared if envelope?(prepared)

      worker_preview = @dev_worker.preview(request: prepared.fetch("request"))
      return worker_preview unless worker_preview["ok"]

      worker = worker_preview.fetch("data")
      success({
        "schema_version" => SCHEMA,
        "experiment_id" => prepared.fetch("experiment_id"),
        "experiment_sha256" => prepared.fetch("experiment_sha256"),
        "proposal_sha256" => prepared.fetch("proposal_sha256"),
        "original_handoff_sha256" => prepared.fetch("original_handoff_sha256"),
        "allowed_files" => prepared.fetch("allowed_files"),
        "source_head" => prepared.fetch("experiment").fetch("base_commit"),
        "expected_digest" => worker.fetch("expected_digest"),
        "confirmation_phrase" => worker.fetch("confirmation_phrase"),
        "model" => worker.fetch("model"),
        "advisory_only" => true,
        "gate_a1_authorized" => false,
        "worktree_creation_authorized" => false,
        "follow_on_execution_authorized" => false,
        "read_only" => true
      })
    rescue StandardError => error
      failed("Self Augmentation Dev handoff preview failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def execute(experiment_id:, confirmation:, expected_digest:, on_progress: nil)
      prepared = prepared_request(experiment_id)
      return prepared if envelope?(prepared)

      worker_result = @dev_worker.execute(
        request: prepared.fetch("request"),
        confirmation: confirmation,
        expected_digest: expected_digest,
        on_progress: on_progress
      )
      return worker_result unless worker_result["ok"]

      candidate = worker_result.dig("data", "candidate")
      validation = validate_candidate(candidate, prepared.fetch("evidence_refs"), prepared.fetch("allowed_files"))
      return failed(validation) if validation

      record = build_record(prepared, candidate, worker_result.dig("data", "provider_receipt"))
      created = persist_record(record)
      success({
        "schema_version" => SCHEMA,
        "handoff" => public_record(record),
        "packet" => packet_relative_path(record),
        "human_review_required" => true,
        "gate_a1_authorized" => false,
        "worktree_creation_authorized" => false,
        "follow_on_execution_authorized" => false,
        "idempotent_replay" => !created
      }, mutation: created ? "self_augmentation_dev_handoff_created" : "none")
    rescue Interrupt
      canceled("Self Augmentation Dev handoff was canceled before completion")
    rescue StandardError => error
      failed("Self Augmentation Dev handoff failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def inventory(limit: MAX_RECORDS)
      maximum = Integer(limit).clamp(1, MAX_RECORDS)
      root = File.join(@root, EXPERIMENTS_ROOT)
      return success({ "records" => [], "count" => 0, "limit" => maximum }) unless File.exist?(root)
      return failed("augmentation experiments inventory root is unsafe") unless File.directory?(root) && !File.symlink?(root)
      records = experiment_ids.flat_map do |experiment_id|
        handoff_ids_for(experiment_id).filter_map { |id| read_record(experiment_id, id, expose: false) }
      end
      records = records.sort_by { |record| record.fetch("created_at", "") }.reverse.first(maximum)
      success({ "records" => records.map { |record| public_record(record) }, "count" => records.length, "limit" => maximum })
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("Self Augmentation Dev handoff inventory failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    private

    def prepared_request(experiment_id)
      source = @experiment_source.dev_handoff_source(experiment_id: experiment_id.to_s)
      return source unless source["ok"]

      experiment = project(source.dig("data", "experiment"))
      proposal = project(source.dig("data", "proposal"))
      original_handoff = source.dig("data", "original_handoff")
      return blocked("original Gate A1 handoff is invalid") unless bounded_string?(original_handoff, 64 * 1024)
      source_projection = { "experiment" => experiment, "proposal" => proposal, "original_handoff" => original_handoff }
      encoded = JSON.generate(source_projection)
      return blocked("augmentation handoff evidence exceeds #{MAX_SOURCE_BYTES} bytes") if encoded.bytesize > MAX_SOURCE_BYTES
      evidence_refs = leaf_paths(source_projection)
      return blocked("augmentation handoff contains no eligible scalar references") if evidence_refs.empty?

      experiment_sha256 = Digest::SHA256.hexdigest(JSON.generate(experiment))
      proposal_sha256 = Digest::SHA256.hexdigest(JSON.generate(proposal))
      original_handoff_sha256 = Digest::SHA256.hexdigest(original_handoff)
      allowed_files = normalize_allowed_files(experiment.fetch("allowed_files"))
      return blocked("augmentation experiment has no allowed file guidance") if allowed_files.empty?

      context = JSON.pretty_generate({
        "handoff_contract" => {
          "output_is_advisory_only" => true,
          "do_not_authorize_gate_a1" => true,
          "do_not_create_source_code_patches_commands_or_scope_expansion" => true,
          "do_not_authorize_worktree_creation_or_integration" => true,
          "do_not_issue_follow_on_actions" => true,
          "cite_only_eligible_source_refs" => true,
          "gate_a1_allowed_file_scope_is_exact" => true,
          "unknowns_must_be_explicit_questions" => true
        },
        "eligible_source_refs" => evidence_refs,
        "exact_allowed_files" => allowed_files,
        "source_evidence" => source_projection
      })

      {
        "experiment_id" => experiment.fetch("experiment_id"),
        "experiment" => experiment,
        "proposal" => proposal,
        "original_handoff" => original_handoff,
        "experiment_sha256" => experiment_sha256,
        "proposal_sha256" => proposal_sha256,
        "original_handoff_sha256" => original_handoff_sha256,
        "source_projection" => source_projection,
        "allowed_files" => allowed_files,
        "evidence_refs" => evidence_refs,
        "request" => {
          "schema_version" => DevWorkerService::REQUEST_SCHEMA,
          "request_id" => "self_augmentation_#{experiment.fetch("experiment_id")}_#{experiment_sha256[0, 12]}",
          "purpose" => "Draft a bounded file-scoped implementation handoff for human or Codex review after Gate A1",
          "task_kind" => "analyze",
          "repository_relative_paths" => [],
          "parent_supplied_context" => context,
          "expected_context_sha256" => Digest::SHA256.hexdigest(context),
          "output_schema" => output_schema(evidence_refs, allowed_files),
          "timeout_seconds" => 300
        }
      }
    rescue KeyError, JSON::GeneratorError => error
      failed("augmentation experiment is invalid: #{error.message}"[0, 1_000])
    end

    def output_schema(evidence_refs, allowed_files)
      cited_item = {
        "type" => "object", "additionalProperties" => false,
        "required" => %w[statement evidence_ref],
        "properties" => {
          "statement" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
          "evidence_ref" => { "type" => "string", "enum" => evidence_refs }
        }
      }
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[summary implementation_objectives file_guidance compatibility_checks rollback_considerations unknowns],
        "properties" => {
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 2_000 },
          "implementation_objectives" => {
            "type" => "array", "maxItems" => 8,
            "items" => cited_item
          },
          "file_guidance" => {
            "type" => "array", "minItems" => allowed_files.length, "maxItems" => allowed_files.length,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[path responsibility verification_expectation],
              "properties" => {
                "path" => { "type" => "string", "enum" => allowed_files },
                "responsibility" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
                "verification_expectation" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 }
              }
            }
          },
          "compatibility_checks" => {
            "type" => "array", "maxItems" => 10,
            "items" => cited_item
          },
          "rollback_considerations" => {
            "type" => "array", "maxItems" => 8,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[consideration evidence_ref],
              "properties" => {
                "consideration" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
                "evidence_ref" => { "type" => "string", "enum" => evidence_refs }
              }
            }
          },
          "unknowns" => {
            "type" => "array", "maxItems" => 10,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[question reason],
              "properties" => {
                "question" => { "type" => "string", "minLength" => 1, "maxLength" => 800 },
                "reason" => { "type" => "string", "minLength" => 1, "maxLength" => 800 }
              }
            }
          }
        }
      }
    end

    def normalize_allowed_files(paths)
      raise ArgumentError, "allowed file scope must be an array" unless paths.is_a?(Array)
      normalized = paths.map(&:to_s).map(&:strip).reject(&:empty?)
      raise ArgumentError, "allowed file scope must be unique" unless normalized.length == normalized.uniq.length
      raise ArgumentError, "allowed file scope contains an invalid path" unless normalized.all? { |path| path.match?(%r{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\z}) }
      normalized
    end

    def validate_candidate(candidate, evidence_refs, allowed_files)
      required_fields = %w[summary implementation_objectives file_guidance compatibility_checks rollback_considerations unknowns]
      return "Dev handoff result is not a structured object" unless candidate.is_a?(Hash)
      return "Dev handoff required fields are missing" unless required_fields.all? { |field| candidate.key?(field) }
      return "Dev handoff candidate contains unexpected fields" unless candidate.keys - required_fields == []

      return "Dev handoff summary is invalid" unless bounded_string?(candidate.fetch("summary"), 2_000)
      return "Dev handoff candidate includes forbidden command-like text" unless candidate_string_fields(candidate).all? { |value| safe_text?(value) }

      objectives = candidate.fetch("implementation_objectives")
      return "Dev handoff implementation objectives are invalid" unless objectives.is_a?(Array) && objectives.length <= 8
      objectives.each do |item|
        return "Dev handoff implementation objective shape is invalid" unless item.is_a?(Hash) && item.keys.sort == %w[evidence_ref statement]
        return "Dev handoff implementation objective statement is invalid" unless bounded_string?(item.fetch("statement"), 1_000)
        return "Dev handoff implementation objective evidence reference is invalid" unless evidence_refs.include?(item.fetch("evidence_ref"))
      end

      file_guidance = candidate.fetch("file_guidance")
      return "Dev handoff file guidance is invalid" unless file_guidance.is_a?(Array) && file_guidance.length == allowed_files.length
      return "Dev handoff file guidance does not match exact Gate A1 scope" unless file_guidance.map { |item| item.is_a?(Hash) ? item["path"] : nil }.sort == allowed_files.sort
      file_guidance.each do |item|
        return "Dev handoff file guidance shape is invalid" unless item.keys.sort == %w[path responsibility verification_expectation]
        return "Dev handoff file guidance text is invalid" unless bounded_string?(item.fetch("responsibility"), 1_000) && bounded_string?(item.fetch("verification_expectation"), 1_000)
      end

      compatibility_checks = candidate.fetch("compatibility_checks")
      return "Dev handoff compatibility checks are invalid" unless compatibility_checks.is_a?(Array) && compatibility_checks.length <= 10
      compatibility_checks.each do |item|
        return "Dev handoff compatibility checklist shape is invalid" unless item.is_a?(Hash) && item.keys.sort == %w[evidence_ref statement]
        return "Dev handoff compatibility checklist statement is invalid" unless bounded_string?(item.fetch("statement"), 1_000)
        return "Dev handoff compatibility checklist evidence reference is invalid" unless evidence_refs.include?(item.fetch("evidence_ref"))
      end

      rollback = candidate.fetch("rollback_considerations")
      return "Dev handoff rollback considerations are invalid" unless rollback.is_a?(Array) && rollback.length <= 8
      rollback.each do |item|
        return "Dev handoff rollback consideration shape is invalid" unless item.is_a?(Hash) && item.keys.sort == %w[consideration evidence_ref]
        return "Dev handoff rollback consideration is invalid" unless bounded_string?(item.fetch("consideration"), 1_000)
        return "Dev handoff rollback consideration evidence reference is invalid" unless evidence_refs.include?(item.fetch("evidence_ref"))
      end

      unknowns = candidate.fetch("unknowns")
      return "Dev handoff unknowns are invalid" unless unknowns.is_a?(Array) && unknowns.length <= 10
      unknowns.each do |item|
        return "Dev handoff unknown shape is invalid" unless item.is_a?(Hash) && item.keys.sort == %w[question reason]
        return "Dev handoff unknown text is invalid" unless bounded_string?(item.fetch("question"), 800) && bounded_string?(item.fetch("reason"), 800)
      end

      nil
    end

    def candidate_string_fields(candidate)
      candidate.fetch("implementation_objectives", []).flat_map { |item| [item.fetch("statement")] } +
        [candidate.fetch("summary", "")] +
        candidate.fetch("file_guidance", []).flat_map { |item| [item.fetch("responsibility"), item.fetch("verification_expectation")] } +
        candidate.fetch("compatibility_checks", []).flat_map { |item| [item.fetch("statement")] } +
        candidate.fetch("rollback_considerations", []).flat_map { |item| [item.fetch("consideration")] } +
        candidate.fetch("unknowns", []).flat_map { |item| [item.fetch("question"), item.fetch("reason")] }
    end

    def safe_text?(value)
      text = value.to_s
      return false unless bounded_string?(text, MAX_STRING_BYTES)
      return false if text.include?("```")
      return false if text.match?(%r{(?im)^\s*(?:sudo|git|ruby|python|python3|node|npm|yarn|cargo|curl|wget|systemctl|rm|cp|mv|chmod|chown|sh|bash|zsh)\b})
      true
    end

    def build_record(prepared, candidate, provider_receipt)
      source_digests = {
        "experiment_sha256" => prepared.fetch("experiment_sha256"),
        "proposal_sha256" => prepared.fetch("proposal_sha256"),
        "original_handoff_sha256" => prepared.fetch("original_handoff_sha256")
      }
      digest = Digest::SHA256.hexdigest(JSON.generate({ "source_digests" => source_digests, "candidate" => candidate }))
      {
        "schema_version" => SCHEMA,
        "handoff_id" => "augmentation_handoff_#{digest[0, 20]}",
        "created_at" => @clock.call.utc.iso8601,
        "experiment_id" => prepared.fetch("experiment_id"),
        "experiment_sha256" => prepared.fetch("experiment_sha256"),
        "proposal_sha256" => prepared.fetch("proposal_sha256"),
        "original_handoff_sha256" => prepared.fetch("original_handoff_sha256"),
        "proposal_id" => prepared.fetch("experiment").fetch("proposal_id"),
        "base_commit" => prepared.fetch("experiment").fetch("base_commit"),
        "allowed_files" => prepared.fetch("experiment").fetch("allowed_files"),
        "source_evidence" => prepared.fetch("source_projection"),
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
      root = ensure_handoff_root(record.fetch("experiment_id"), create: true)
      directory = File.join(root, record.fetch("handoff_id"))

      if File.directory?(directory) && !File.symlink?(directory)
        existing = read_record(record.fetch("experiment_id"), record.fetch("handoff_id"), expose: false)
        raise "existing handoff packet does not match candidate" unless existing && existing.fetch("experiment_sha256") == record.fetch("experiment_sha256") && existing.fetch("proposal_sha256") == record.fetch("proposal_sha256") && existing.fetch("original_handoff_sha256") == record.fetch("original_handoff_sha256") && existing.fetch("candidate") == record.fetch("candidate")
        return false
      end

      raise "handoff packet target is unsafe" if File.exist?(directory) || File.symlink?(directory)

      staging = File.join(root, ".#{record.fetch('handoff_id')}.tmp-#{Process.pid}")
      raise "handoff packet staging target is unsafe" if File.exist?(staging) || File.symlink?(staging)
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
      result = record.slice(
        "schema_version", "handoff_id", "created_at", "experiment_id", "proposal_id", "base_commit", "experiment_sha256", "proposal_sha256", "original_handoff_sha256", "allowed_files",
        "candidate", "provider_receipt", "advisory_only", "human_review_required", "gate_a1_authorized", "worktree_creation_authorized", "follow_on_execution_authorized"
      )
      candidate = project(result.fetch("candidate"))
      (candidate.fetch("implementation_objectives", []) + candidate.fetch("compatibility_checks", []) + candidate.fetch("rollback_considerations", [])).each do |item|
        value = evidence_value(record.fetch("source_evidence"), item.fetch("evidence_ref"))
        item["evidence_value"] = value.is_a?(String) ? value : JSON.generate(value)
      end
      result.merge("candidate" => candidate)
    end

    def read_record(experiment_id, handoff_id, expose: true)
      return nil unless experiment_id.to_s.match?(%r{\Aexp_[a-f0-9]{16}\z}) && handoff_id.to_s.match?(%r{\Aaugmentation_handoff_[a-f0-9]{20}\z})
      directory = File.join(handoff_root(experiment_id.to_s), handoff_id.to_s)
      path = File.join(directory, "record.json")

      return nil unless File.directory?(directory) && !File.symlink?(directory) &&
        File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES

      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      return nil unless valid_record?(record, experiment_id.to_s, handoff_id.to_s)
      expose ? public_record(record) : record
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def experiment_ids
      return [] unless File.directory?(File.join(@root, EXPERIMENTS_ROOT))
      Dir.children(File.join(@root, EXPERIMENTS_ROOT)).grep(/\Aexp_[a-f0-9]{16}\z/).sort
    end

    def handoff_ids_for(experiment_id)
      root = handoff_root(experiment_id)
      return [] unless File.directory?(root) && !File.symlink?(root)
      Dir.children(root).grep(/\Aaugmentation_handoff_[a-f0-9]{20}\z/).sort
    end

    def valid_record?(record, experiment_id, handoff_id)
      return false unless record.is_a?(Hash) && record["schema_version"] == SCHEMA && record["experiment_id"] == experiment_id && record["handoff_id"] == handoff_id
      return false unless record["proposal_id"].to_s.match?(/\Aaug_[a-f0-9]{16}\z/) && record["base_commit"].to_s.match?(/\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z/)
      return false unless %w[experiment_sha256 proposal_sha256 original_handoff_sha256].all? { |key| record[key].to_s.match?(/\A[a-f0-9]{64}\z/) }
      return false unless record["advisory_only"] == true && record["human_review_required"] == true && record["gate_a1_authorized"] == false && record["worktree_creation_authorized"] == false && record["follow_on_execution_authorized"] == false
      source = record["source_evidence"]
      return false unless source.is_a?(Hash) && Digest::SHA256.hexdigest(JSON.generate(source["experiment"])) == record["experiment_sha256"] && Digest::SHA256.hexdigest(JSON.generate(source["proposal"])) == record["proposal_sha256"] && Digest::SHA256.hexdigest(source["original_handoff"].to_s) == record["original_handoff_sha256"]
      allowed_files = normalize_allowed_files(record["allowed_files"])
      validate_candidate(record["candidate"], leaf_paths(source), allowed_files).nil?
    rescue ArgumentError, JSON::GeneratorError
      false
    end

    def ensure_handoff_root(experiment_id, create:)
      raise "experiment id is invalid" unless experiment_id.to_s.match?(%r{\Aexp_[a-f0-9]{16}\z})
      experiment_directory = File.join(@root, EXPERIMENTS_ROOT, experiment_id.to_s)
      raise "experiment directory is unsafe" unless File.directory?(experiment_directory) && !File.symlink?(experiment_directory)

      root = handoff_root(experiment_id)
      if create
        raise "handoff root is unsafe" if File.symlink?(root)
        Dir.mkdir(root, 0o700) unless File.exist?(root)
        raise "handoff root is not a directory" unless File.directory?(root)
      end
      root
    end

    def handoff_root(experiment_id)
      File.join(@root, EXPERIMENTS_ROOT, experiment_id.to_s, DEV_HANDOFFS_DIRECTORY)
    end

    def leaf_paths(value, path = "")
      case value
      when Hash
        value.flat_map { |key, child| leaf_paths(child, "#{path}/#{key.to_s.gsub("~", "~0").gsub("/", "~1")}" ) }
      when Array
        value.each_with_index.flat_map { |child, index| leaf_paths(child, "#{path}/#{index}") }
      else
        [path.empty? ? "/" : path]
      end
    end

    def evidence_value(value, pointer)
      pointer.to_s.split("/").drop(1).reduce(value) do |cursor, token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        case cursor
        when Hash then cursor.fetch(key)
        when Array then cursor.fetch(Integer(key, 10))
        else raise KeyError, "experiment reference does not identify a leaf"
        end
      end
    end

    def project(value)
      case value
      when Hash
        value.keys.map(&:to_s).sort.each_with_object({}) do |key, out|
          next if key.match?(SENSITIVE_KEY)
          child = value.key?(key) ? value[key] : value[key.to_sym]
          out[key] = project(child)
        end
      when Array
        value.map { |child| project(child) }
      when String
        bounded_utf8(value)
      when Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        bounded_utf8(value.to_s)
      end
    end

    def bounded_utf8(value)
      return "[invalid encoding removed]" unless value.valid_encoding?
      value.encode(Encoding::UTF_8).byteslice(0, MAX_STRING_BYTES).to_s.scrub
    rescue EncodingError
      "[invalid encoding removed]"
    end

    def bounded_string?(value, maximum)
      value.is_a?(String) && !value.strip.empty? && value.bytesize <= maximum && value.valid_encoding?
    end

    def atomic_write(path, content)
      raise "handoff artifact already exists" if File.exist?(path) || File.symlink?(path)
      raise "handoff artifact exceeds #{MAX_RECORD_BYTES} bytes" if content.bytesize > MAX_RECORD_BYTES
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.file?(temporary)
    end

    def review_markdown(record)
      <<~MD
        # Self Augmentation Dev Handoff Review

        - Handoff: `#{record.fetch("handoff_id")}`
        - Experiment: `#{record.fetch("experiment_id")}`
        - Proposal: `#{record.fetch("proposal_id")}`
        - Experiment SHA-256: `#{record.fetch("experiment_sha256")}`
        - Proposal SHA-256: `#{record.fetch("proposal_sha256")}`
        - Original handoff SHA-256: `#{record.fetch("original_handoff_sha256")}`
        - Advisory only: **yes**
        - Gate A1 authorized: **no**
        - Worktree creation authorized: **no**
        - Follow-on execution authorized: **no**

        ## Human checklist

        - [ ] Objectives, compatibility checks, and rollback items cite eligible source evidence.
        - [ ] Every exact Gate A1 file appears once and no additional file is named.
        - [ ] Unknowns remain explicit questions.
        - [ ] No shell command text, patches, or implementation plan details are introduced.
        - [ ] Final handoff is advisory and does not authorize execution.
      MD
    end

    def packet_relative_path(record)
      File.join(EXPERIMENTS_ROOT, record.fetch("experiment_id"), DEV_HANDOFFS_DIRECTORY, record.fetch("handoff_id"))
    end

    def envelope?(value) = value.is_a?(Hash) && value.key?("lifecycle_state")
    def success(data, mutation: "none") = { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    def awaiting(reason) = { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    def blocked(reason) = { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "mutation" => "none" }
    def failed(reason) = { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "mutation" => "none" }
    def canceled(reason) = { "ok" => false, "lifecycle_state" => "canceled", "reason" => reason, "mutation" => "none" }
  end
end
