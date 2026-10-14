# frozen_string_literal: true

require_relative "../continuity_lab/config"

module SoulCore
  # Detached advisory records, not a new Soul memory or authority channel.
  module Reviewer
    Lab = ContinuityLab
    class Contract
      ID = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z/
      HASH = /\Asha256:[a-f0-9]{64}\z/
      MAX_REQUEST_BYTES = 65_536
      MAX_RESPONSE_BYTES = 32_768
      REQUEST_KEYS = %w[schema review_id source_event_id source_answer source_revision evidence evidence_revision question constraints rubric validation_requirement created_at expires_at].freeze

      def self.digest(value) = "sha256:#{Lab.digest(value)}"
      def self.text_digest(value) = "sha256:#{Digest::SHA256.hexdigest(value)}"
      def self.copy(value) = Lab.parse(Lab.encode(value))

      def self.fields!(value, keys)
        raise Lab::ValidationError, "unexpected fields" unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } && value.keys.sort == keys.sort
      end

      def self.text!(value, maximum)
        unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
               !value.include?("\0") && value.bytesize.between?(1, maximum)
          raise Lab::ValidationError, "invalid bounded UTF-8 text"
        end
      end

      def self.id!(value)
        raise Lab::ValidationError, "invalid identifier" unless value.is_a?(String) && value.match?(ID)
      end

      def self.hash!(value)
        raise Lab::ValidationError, "invalid revision digest" unless value.is_a?(String) && value.match?(HASH)
      end

      def self.time!(value)
        raise Lab::ValidationError, "invalid epoch time" unless value.is_a?(Integer) && value.between?(1, 253_402_300_799)
      end

      def self.texts!(value, maximum: 1024, minimum: 0)
        raise Lab::ValidationError, "invalid bounded text list" unless value.is_a?(Array) && value.length.between?(minimum, 16)
        value.each { |text| text!(text, maximum) }
      end

      def self.request!(value)
        fields!(value, REQUEST_KEYS)
        raise Lab::ValidationError, "unsupported request schema" unless value["schema"] == "soul.reviewer.request.v1"
        %w[review_id source_event_id].each { |key| id!(value[key]) }
        text!(value["source_answer"], 16_384)
        text!(value["question"], 4096)
        texts!(value["constraints"])
        texts!(value["rubric"], minimum: 1)
        unless %w[advisory independent_required].include?(value["validation_requirement"])
          raise Lab::ValidationError, "invalid validation requirement"
        end
        %w[created_at expires_at].each { |key| time!(value[key]) }
        unless (value["expires_at"] - value["created_at"]).between?(1, 86_400)
          raise Lab::ValidationError, "invalid request lifetime"
        end
        evidence = value["evidence"]
        raise Lab::ValidationError, "invalid evidence list" unless evidence.is_a?(Array) && evidence.length <= 16
        evidence.each do |source|
          fields!(source, %w[id text sha256 provenance redacted])
          id!(source["id"])
          text!(source["text"], 16_384)
          text!(source["provenance"], 128)
          raise Lab::ValidationError, "invalid redaction marker" unless [true, false].include?(source["redacted"])
          raise Lab::ValidationError, "evidence text digest mismatch" unless source["sha256"] == text_digest(source["text"])
        end
        raise Lab::ValidationError, "duplicate evidence ID" unless evidence.map { |source| source["id"] }.uniq.length == evidence.length
        unless value["source_revision"] == text_digest(value["source_answer"]) && value["evidence_revision"] == digest(evidence)
          raise Lab::ValidationError, "request revision mismatch"
        end
        raise Lab::ValidationError, "request exceeds byte bound" if Lab.encode(value).bytesize > MAX_REQUEST_BYTES
        copy(value)
      end

      def self.response!(value, request:)
        request = request!(request)
        fields!(value, %w[review_id verdict findings omissions])
        unless value["review_id"] == request["review_id"] && %w[supported contradicted insufficient_evidence mixed].include?(value["verdict"])
          raise Lab::ValidationError, "invalid response identity or verdict"
        end
        findings = value["findings"]
        raise Lab::ValidationError, "invalid findings" unless findings.is_a?(Array) && findings.length <= 16
        ids = request["evidence"].map { |source| source["id"] }
        findings.each do |finding|
          fields!(finding, %w[claim evidence_refs confidence rationale proposed_check])
          %w[claim rationale proposed_check].each { |key| text!(finding[key], 2048) }
          refs = finding["evidence_refs"]
          unless refs.is_a?(Array) && refs.length <= 16 && refs.uniq == refs && (refs - ids).empty?
            raise Lab::ValidationError, "unknown or duplicate evidence reference"
          end
          unless %w[low medium high].include?(finding["confidence"])
            raise Lab::ValidationError, "invalid confidence label"
          end
        end
        texts!(value["omissions"], maximum: 2048)
        raise Lab::ValidationError, "response exceeds byte bound" if Lab.encode(value).bytesize > MAX_RESPONSE_BYTES
        copy(value)
      end

      # Identity is supplied by trusted local runner code, never by generated text.
      # M1 has no model runtime: this fingerprint must not imply GPU attestation.
      def self.fake_runtime
        implementation = %w[contract.rb store.rb fake_runner.rb].to_h do |name|
          [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest]
        end
        { "provider" => "deterministic_fixture", "reviewer_model" => "none-fake-reviewer-v1",
          "backend" => "fake_no_inference", "reviewer_config" => digest({ "version" => 1, "semantic_review" => false }),
          "implementation_sha256" => digest(implementation) }
      end

      def self.disposition(request)
        request.fetch("validation_requirement") == "independent_required" ? "pending_independent_validation" : "may_proceed_without_review"
      end
    end
  end
end
