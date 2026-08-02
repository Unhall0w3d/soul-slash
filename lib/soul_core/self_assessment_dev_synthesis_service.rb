# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "dev_worker_service"

module SoulCore
  class SelfAssessmentDevSynthesisService
    SCHEMA = "soul.self_assessment.dev_review.v1"
    ROOT = File.join("Soul", "private", "self_assessment", "dev_reviews")
    MAX_EVIDENCE_BYTES = 160 * 1024
    MAX_RECORD_BYTES = 512 * 1024
    MAX_DEPTH = 10
    MAX_HASH_KEYS = 160
    MAX_ARRAY_ITEMS = 120
    MAX_STRING_BYTES = 4 * 1024
    MAX_EVIDENCE_REFS = 320
    MAX_RECORDS = 50
    ROUTING_SURFACES = %w[self_assessment skill_studio self_augmentation guided_maintenance none].freeze
    SENSITIVE_KEY = /(?:password|passwd|secret|credential|authorization|cookie|private[_-]?key|access[_-]?token|api[_-]?key)/i

    def initialize(root: Dir.pwd, clock: -> { Time.now.utc }, assessment_source:, dev_worker: nil)
      @root = File.expand_path(root)
      @clock = clock
      @assessment_source = assessment_source
      @dev_worker = dev_worker || DevWorkerService.new(root: @root, clock: -> { @clock.call.utc })
    end

    def preview(scope:)
      prepared = prepared_request(scope)
      return prepared if envelope?(prepared)

      dev_preview = @dev_worker.preview(request: prepared.fetch("request"))
      return dev_preview unless dev_preview["ok"]

      worker = dev_preview.fetch("data")
      success({
        "schema_version" => SCHEMA,
        "scope" => prepared.fetch("scope"),
        "evidence_generated_at" => prepared.fetch("evidence_generated_at"),
        "evidence_sha256" => prepared.fetch("evidence_sha256"),
        "evidence_reference_count" => prepared.fetch("evidence_refs").length,
        "expected_digest" => worker.fetch("expected_digest"),
        "confirmation_phrase" => worker.fetch("confirmation_phrase"),
        "model" => worker.fetch("model"),
        "advisory_only" => true,
        "follow_on_execution_authorized" => false,
        "artifact_root" => ROOT
      })
    rescue StandardError => error
      failed("Self Assessment Dev synthesis preview failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def execute(scope:, confirmation:, expected_digest:, on_progress: nil)
      prepared = prepared_request(scope)
      return prepared if envelope?(prepared)

      dev_result = @dev_worker.execute(
        request: prepared.fetch("request"),
        confirmation: confirmation,
        expected_digest: expected_digest,
        on_progress: on_progress
      )
      return dev_result unless dev_result["ok"]

      candidate = dev_result.dig("data", "candidate")
      validation = validate_candidate(candidate, prepared.fetch("evidence_refs"))
      return failed(validation) if validation

      record = build_record(prepared, candidate, dev_result.dig("data", "provider_receipt"))
      created = persist_record(record)
      success({
        "schema_version" => SCHEMA,
        "review" => public_record(record),
        "packet" => File.join(ROOT, record.fetch("review_id")),
        "human_review_required" => true,
        "follow_on_execution_authorized" => false,
        "idempotent_replay" => !created
      }, mutation: created ? "self_assessment_dev_review_created" : "none")
    rescue Interrupt
      canceled("Self Assessment Dev synthesis was canceled before completion")
    rescue StandardError => error
      failed("Self Assessment Dev synthesis failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    def inventory(limit: MAX_RECORDS)
      ensure_storage_root!
      maximum = Integer(limit).clamp(1, MAX_RECORDS)
      records = Dir.children(storage_root).filter_map { |id| read_record(id, expose: false) }.sort_by { |record| record.fetch("created_at", "") }.reverse.first(maximum)
      success({ "records" => records.map { |record| public_record(record) }, "count" => records.length, "limit" => maximum })
    rescue ArgumentError => error
      awaiting(error.message)
    rescue StandardError => error
      failed("Self Assessment Dev review inventory failed safely: #{error.class}: #{error.message}"[0, 1_000])
    end

    private

    def prepared_request(scope)
      scope = scope.to_s
      latest = @assessment_source.latest_assessment(scope: scope)
      return latest unless latest["ok"]

      evidence = project(latest.fetch("data"), depth: 0)
      encoded = JSON.generate(evidence)
      return blocked("projected assessment evidence exceeds #{MAX_EVIDENCE_BYTES} bytes") if encoded.bytesize > MAX_EVIDENCE_BYTES
      evidence_refs = leaf_paths(evidence).first(MAX_EVIDENCE_REFS)
      return blocked("assessment evidence contains no eligible scalar references") if evidence_refs.empty?

      evidence_sha256 = Digest::SHA256.hexdigest(encoded)
      context = JSON.pretty_generate({
        "review_contract" => {
          "output_is_advisory_only" => true,
          "do_not_assign_or_change_severity" => true,
          "do_not_generate_recommendations_or_plans" => true,
          "do_not_authorize_or_invoke_follow_on_actions" => true,
          "cite_only_eligible_evidence_refs" => true,
          "each_observation_must_use_one_directly_supporting_ref" => true,
          "do_not_cite_adjacent_or_unrelated_paths" => true,
          "keep_each_statement_to_one_evidence_supported_claim" => true
        },
        "eligible_evidence_refs" => evidence_refs,
        "assessment_evidence" => evidence
      })
      request_id = "self_assessment_#{scope}_#{evidence_sha256[0, 16]}"
      {
        "scope" => scope,
        "evidence" => evidence,
        "evidence_refs" => evidence_refs,
        "evidence_sha256" => evidence_sha256,
        "evidence_generated_at" => evidence.fetch("generated_at"),
        "request" => {
          "schema_version" => DevWorkerService::REQUEST_SCHEMA,
          "request_id" => request_id,
          "purpose" => "Synthesize the bound Self Assessment evidence into observations and explicit unknowns only",
          "task_kind" => "analyze",
          "repository_relative_paths" => [],
          "parent_supplied_context" => context,
          "expected_context_sha256" => Digest::SHA256.hexdigest(context),
          "output_schema" => output_schema(evidence_refs),
          "timeout_seconds" => 300
        }
      }
    rescue KeyError, JSON::GeneratorError => error
      failed("assessment evidence is invalid: #{error.message}"[0, 1_000])
    end

    def output_schema(evidence_refs)
      {
        "type" => "object",
        "additionalProperties" => false,
        "required" => %w[summary observations unknowns suggested_next_surfaces],
        "properties" => {
          "summary" => { "type" => "string", "minLength" => 1, "maxLength" => 2_000 },
          "observations" => {
            "type" => "array", "maxItems" => 12,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[statement evidence_ref],
              "properties" => {
                "statement" => { "type" => "string", "minLength" => 1, "maxLength" => 1_000 },
                "evidence_ref" => { "type" => "string", "enum" => evidence_refs }
              }
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
          "suggested_next_surfaces" => { "type" => "array", "maxItems" => 5, "items" => { "type" => "string", "enum" => ROUTING_SURFACES } }
        }
      }
    end

    def validate_candidate(candidate, evidence_refs)
      return "Dev synthesis result is not a structured object" unless candidate.is_a?(Hash)
      return "Dev synthesis summary is invalid" unless bounded_string?(candidate["summary"], 2_000)
      observations = candidate["observations"]
      return "Dev synthesis observations are invalid" unless observations.is_a?(Array) && observations.length <= 12
      observations.each do |observation|
        return "Dev synthesis observation shape is invalid" unless observation.is_a?(Hash) && observation.keys.sort == %w[evidence_ref statement]
        return "Dev synthesis observation statement is invalid" unless bounded_string?(observation["statement"], 1_000)
        return "Dev synthesis observation evidence reference is invalid" unless evidence_refs.include?(observation["evidence_ref"])
      end
      unknowns = candidate["unknowns"]
      return "Dev synthesis unknowns are invalid" unless unknowns.is_a?(Array) && unknowns.length <= 12
      unknowns.each do |unknown|
        return "Dev synthesis unknown shape is invalid" unless unknown.is_a?(Hash) && unknown.keys.sort == %w[question reason]
        return "Dev synthesis unknown text is invalid" unless bounded_string?(unknown["question"], 800) && bounded_string?(unknown["reason"], 800)
      end
      surfaces = candidate["suggested_next_surfaces"]
      return "Dev synthesis routing suggestions are invalid" unless surfaces.is_a?(Array) && surfaces.length <= 5 && surfaces.all? { |surface| ROUTING_SURFACES.include?(surface) }
      return "Dev synthesis none routing hint must stand alone" if surfaces.include?("none") && surfaces.length > 1
      nil
    end

    def build_record(prepared, candidate, provider_receipt)
      created_at = @clock.call.utc.iso8601
      review_digest = Digest::SHA256.hexdigest(JSON.generate({ "evidence_sha256" => prepared.fetch("evidence_sha256"), "candidate" => candidate }))
      {
        "schema_version" => SCHEMA,
        "review_id" => "assessment_review_#{review_digest[0, 20]}",
        "created_at" => created_at,
        "scope" => prepared.fetch("scope"),
        "evidence_generated_at" => prepared.fetch("evidence_generated_at"),
        "evidence_sha256" => prepared.fetch("evidence_sha256"),
        "evidence" => prepared.fetch("evidence"),
        "candidate" => candidate,
        "provider_receipt" => provider_receipt,
        "advisory_only" => true,
        "human_review_required" => true,
        "follow_on_execution_authorized" => false
      }
    end

    def persist_record(record)
      ensure_storage_root!
      directory = File.join(storage_root, record.fetch("review_id"))
      if File.directory?(directory) && !File.symlink?(directory)
        existing = read_record(record.fetch("review_id"), expose: false)
        raise "existing review packet does not match candidate" unless existing && existing.fetch("evidence_sha256") == record.fetch("evidence_sha256") && existing.fetch("candidate") == record.fetch("candidate")
        return false
      end
      raise "review packet target is unsafe" if File.exist?(directory) || File.symlink?(directory)
      staging = File.join(storage_root, ".#{record.fetch('review_id')}.tmp-#{Process.pid}")
      raise "review packet staging target is unsafe" if File.exist?(staging) || File.symlink?(staging)
      Dir.mkdir(staging, 0o700)
      atomic_write(File.join(staging, "record.json"), JSON.pretty_generate(record) + "\n")
      atomic_write(File.join(staging, "REVIEW.md"), review_markdown(record))
      File.rename(staging, directory)
      true
    rescue StandardError
      FileUtils.remove_dir(staging) if defined?(staging) && File.directory?(staging) && !File.symlink?(staging)
      raise
    end

    def review_markdown(record)
      <<~MD
        # Self Assessment Dev Synthesis Review

        - Review: `#{record.fetch("review_id")}`
        - Scope: `#{record.fetch("scope")}`
        - Evidence generated: `#{record.fetch("evidence_generated_at")}`
        - Evidence SHA-256: `#{record.fetch("evidence_sha256")}`
        - Advisory only: **yes**
        - Follow-on execution authorized: **no**

        ## Human checklist

        - [ ] Every observation is supported by its cited evidence path.
        - [ ] Unknowns are explicit rather than filled with inference.
        - [ ] No severity, recommendation, plan, or authorization was introduced.
        - [ ] Routing suggestions are treated only as navigation hints.
        - [ ] The source evidence remains the authority for assessed facts.
      MD
    end

    def public_record(record)
      result = record.slice("schema_version", "review_id", "created_at", "scope", "evidence_generated_at", "evidence_sha256", "candidate", "provider_receipt", "advisory_only", "human_review_required", "follow_on_execution_authorized")
      candidate = project(result.fetch("candidate"), depth: 0)
      candidate.fetch("observations", []).each do |observation|
        value = evidence_value(record.fetch("evidence"), observation.fetch("evidence_ref"))
        observation["evidence_value"] = value.is_a?(String) ? value : JSON.generate(value)
      end
      result.merge("candidate" => candidate)
    end

    def evidence_value(evidence, pointer)
      pointer.to_s.split("/").drop(1).reduce(evidence) do |cursor, token|
        key = token.gsub("~1", "/").gsub("~0", "~")
        case cursor
        when Hash then cursor.fetch(key)
        when Array then cursor.fetch(Integer(key, 10))
        else raise KeyError, "evidence reference does not identify a leaf"
        end
      end
    end

    def read_record(id, expose: true)
      return nil unless id.to_s.match?(/\Aassessment_review_[a-f0-9]{20}\z/)
      directory = File.join(storage_root, id.to_s)
      path = File.join(directory, "record.json")
      return nil unless File.directory?(directory) && !File.symlink?(directory) && File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_RECORD_BYTES
      record = JSON.parse(File.binread(path, MAX_RECORD_BYTES))
      expose ? public_record(record) : record
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def project(value, depth:)
      raise "assessment evidence nesting exceeds #{MAX_DEPTH}" if depth > MAX_DEPTH
      case value
      when Hash
        value.keys.map(&:to_s).sort.first(MAX_HASH_KEYS).each_with_object({}) do |key, out|
          next if key.match?(SENSITIVE_KEY)
          child = value.key?(key) ? value[key] : value[key.to_sym]
          out[key] = project(child, depth: depth + 1)
        end
      when Array then value.first(MAX_ARRAY_ITEMS).map { |child| project(child, depth: depth + 1) }
      when String then bounded_utf8(value)
      when Integer, Float, TrueClass, FalseClass, NilClass then value
      else bounded_utf8(value.to_s)
      end
    end

    def leaf_paths(value, path = "")
      case value
      when Hash
        value.flat_map { |key, child| leaf_paths(child, "#{path}/#{key.to_s.gsub('~', '~0').gsub('/', '~1')}") }
      when Array
        value.each_with_index.flat_map { |child, index| leaf_paths(child, "#{path}/#{index}") }
      else
        [path.empty? ? "/" : path]
      end
    end

    def ensure_storage_root!
      cursor = @root
      ROOT.split(File::SEPARATOR).each do |component|
        cursor = File.join(cursor, component)
        raise "Self Assessment review path must not traverse a symlink" if File.symlink?(cursor)
        Dir.mkdir(cursor, 0o700) unless File.exist?(cursor)
        raise "Self Assessment review path component is not a directory" unless File.directory?(cursor)
      end
    end

    def atomic_write(path, content)
      raise "review artifact already exists" if File.exist?(path) || File.symlink?(path)
      raise "review artifact exceeds #{MAX_RECORD_BYTES} bytes" if content.bytesize > MAX_RECORD_BYTES
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.flush; file.fsync }
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if defined?(temporary) && File.file?(temporary)
    end

    def storage_root = File.join(@root, ROOT)
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
