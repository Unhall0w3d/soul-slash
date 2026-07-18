# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "timeout"

require_relative "capability_matrix"
require_relative "environment_assessor"
require_relative "improvement_proposal_generator"
require_relative "improvement_proposal_paths"
require_relative "model_runtime_assessor"
require_relative "storage_retention_assessor"

module SoulCore
  class SelfImprovementService
    CONFIRMATION = "GENERATE_SELF_IMPROVEMENT_PROPOSALS"
    SCOPES = %w[environment updates models capabilities storage].freeze
    MAX_PROPOSALS = 100
    MAX_METADATA_BYTES = 256 * 1024
    ASSESSMENT_TIMEOUT_SECONDS = 30

    def initialize(root: Dir.pwd, clock: -> { Time.now }, environment_assessor: nil, model_assessor: nil, capability_matrix: nil, proposal_generator: nil, storage_assessor: nil, assessment_timeout_seconds: ASSESSMENT_TIMEOUT_SECONDS)
      @root = File.expand_path(root)
      @clock = clock
      @environment_assessor = environment_assessor
      @model_assessor = model_assessor
      @capability_matrix = capability_matrix
      @proposal_generator = proposal_generator
      @storage_assessor = storage_assessor
      @assessment_timeout_seconds = Float(assessment_timeout_seconds)
      raise ArgumentError, "assessment timeout must be positive" unless @assessment_timeout_seconds.positive?
    end

    def snapshot
      assessment = bounded_assessment { environment_assessor.assess(include_updates: false) }
      success({
        "schema_version" => "soul.self_improvement.v1",
        "generated_at" => @clock.call.iso8601,
        "assessment_scope" => "environment",
        "automatic" => true,
        "read_only" => true,
        "assessment" => assessment,
        "cached_capabilities" => cached_capabilities,
        "proposals" => proposal_inventory,
        "available_scopes" => SCOPES,
        "mutation_boundary" => mutation_boundary
      })
    rescue Timeout::Error
      failed("environment assessment exceeded the #{@assessment_timeout_seconds.to_i}-second foreground limit")
    end

    def refresh(scope:)
      scope = scope.to_s
      return awaiting("assessment scope must be one of: #{SCOPES.join(', ')}") unless SCOPES.include?(scope)

      assessment = bounded_assessment do
        case scope
        when "environment" then environment_assessor.assess(include_updates: false)
        when "updates" then environment_assessor.assess(include_updates: true)
        when "models" then model_assessor.assess(include_processes: false)
        when "capabilities" then capability_matrix.assess(persist: false)
        when "storage" then storage_assessor.inventory
        end
      end
      success({
        "schema_version" => "soul.self_improvement.v1",
        "generated_at" => @clock.call.iso8601,
        "assessment_scope" => scope,
        "automatic" => false,
        "read_only" => true,
        "assessment" => assessment,
        "proposals" => proposal_inventory,
        "mutation_boundary" => mutation_boundary
      })
    rescue Timeout::Error
      failed("#{scope} assessment exceeded the #{@assessment_timeout_seconds.to_i}-second foreground limit")
    end

    def storage_cleanup_preview(category:)
      bounded_assessment { storage_assessor.preview(category: category) }
    rescue Timeout::Error
      failed("storage cleanup preview exceeded the #{@assessment_timeout_seconds.to_i}-second foreground limit")
    end

    def proposal_preview
      report = proposal_generator.generate(write_files: false)
      payload = proposal_payload(report)
      digest = Digest::SHA256.hexdigest(JSON.generate(payload))
      success({
        "schema_version" => "soul.self_improvement.v1",
        "generated_at" => @clock.call.iso8601,
        "read_only" => true,
        "proposal_count" => report.fetch("proposal_count"),
        "proposals" => report.fetch("proposals"),
        "source_summary" => report.fetch("source_summary"),
        "expected_digest" => digest,
        "confirmation_phrase" => CONFIRMATION,
        "authorized_effect" => "write advisory improvement proposal packets only",
        "prohibited_effects" => mutation_boundary.fetch("unavailable_actions")
      })
    end

    def generate_proposals(confirmation:, expected_digest:)
      return awaiting("preview digest is required") if expected_digest.to_s.empty?
      return blocked("exact confirmation is required") unless confirmation.to_s == CONFIRMATION

      current = proposal_generator.generate(write_files: false)
      current_digest = Digest::SHA256.hexdigest(JSON.generate(proposal_payload(current)))
      return blocked("assessment changed; preview again") unless secure_equal?(current_digest, expected_digest.to_s)

      written = proposal_generator.generate(write_files: true)
      success(
        {
          "schema_version" => "soul.self_improvement.v1",
          "generated_at" => @clock.call.iso8601,
          "proposal_count" => written.fetch("proposal_count"),
          "written_count" => written.fetch("written_count", 0),
          "proposals" => proposal_inventory,
          "implementation_started" => false,
          "packages_changed" => false,
          "human_review_required" => true
        },
        mutation: written.fetch("written_count", 0).positive? ? "improvement_proposals_created" : "none"
      )
    end

    private

    def bounded_assessment
      Timeout.timeout(@assessment_timeout_seconds) { yield }
    end

    def environment_assessor
      @environment_assessor ||= EnvironmentAssessor.new(root: @root)
    end

    def model_assessor
      @model_assessor ||= ModelRuntimeAssessor.new(root: @root)
    end

    def capability_matrix
      @capability_matrix ||= CapabilityMatrix.new(root: @root)
    end

    def proposal_generator
      @proposal_generator ||= ImprovementProposalGenerator.new(root: @root)
    end

    def storage_assessor
      @storage_assessor ||= StorageRetentionAssessor.new(root: @root)
    end

    def proposal_payload(report)
      {
        "source_summary" => report.fetch("source_summary"),
        "proposals" => report.fetch("proposals").map { |proposal| proposal.reject { |key, _value| key == "path" || key == "content_digest" } }
      }
    end

    def proposal_inventory
      relative_root = ImprovementProposalPaths.relative_root(root: @root)
      root = File.join(@root, relative_root)
      records = Dir.glob(File.join(root, "*", "metadata.json")).sort.reverse.first(MAX_PROPOSALS).filter_map do |path|
        record = JSON.parse(File.binread(path, MAX_METADATA_BYTES))
        {
          "proposal_id" => record["id"],
          "title" => record["title"],
          "capability" => record["capability"],
          "priority" => record["priority"],
          "status" => record["status"],
          "requires_human_approval" => record["requires_human_approval"] == true,
          "implementation_allowed" => record["implementation_allowed"] == true,
          "folder" => File.basename(File.dirname(path))
        }
      rescue JSON::ParserError, Errno::ENOENT, ArgumentError
        nil
      end
      { "records" => records, "count" => records.length, "limit" => MAX_PROPOSALS }
    end

    def cached_capabilities
      path = File.join(@root, CapabilityMatrix::OUTPUT_PATH)
      return { "available" => false } unless File.file?(path) && File.size(path) <= 2 * 1024 * 1024

      report = JSON.parse(File.binread(path))
      { "available" => true, "generated_at" => report["generated_at"], "summary" => report["summary"] }
    rescue JSON::ParserError, Errno::ENOENT
      { "available" => false }
    end

    def mutation_boundary
      {
        "proposal_generation_available" => true,
        "requires_preview" => true,
        "requires_exact_confirmation" => true,
        "unavailable_actions" => [
          "install, update, downgrade, or remove packages",
          "apply operating-system updates",
          "remove orphaned packages or unused runtimes",
          "start, stop, enable, or reconfigure services",
          "download or delete models",
          "implement, register, promote, merge, or release a skill"
        ]
      }
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize
      left.bytes.zip(right.bytes).reduce(0) { |memo, pair| memo | (pair[0] ^ pair[1]) }.zero?
    end

    def success(data, mutation: "none")
      { "ok" => true, "lifecycle_state" => "complete", "data" => data, "mutation" => mutation }
    end

    def awaiting(reason)
      { "ok" => false, "lifecycle_state" => "awaiting_input", "reason" => reason, "mutation" => "none" }
    end

    def blocked(reason)
      { "ok" => false, "lifecycle_state" => "blocked_for_human_review", "reason" => reason, "mutation" => "none" }
    end

    def failed(reason)
      { "ok" => false, "lifecycle_state" => "failed", "reason" => reason, "mutation" => "none" }
    end
  end
end
